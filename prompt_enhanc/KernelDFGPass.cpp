// KernelDFGPass.cpp
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/ScalarEvolution.h"
#include "llvm/Analysis/ScalarEvolutionExpressions.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/InstrTypes.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/PassManager.h"
#include "llvm/IR/Operator.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/raw_ostream.h"
#include <map>
#include <set>
#include <string>
#include <utility>
using namespace llvm;

static cl::opt<std::string> DFGOut(
    "dfg-out", cl::desc("Output JSON filepath"), cl::init("kernel_dfg.json"));

namespace {

// --- helpers ---------------------------------------------------------------
static std::string tyBits(Type *T) {
  if (T->isIntegerTy())  return std::to_string(T->getIntegerBitWidth());
  if (T->isHalfTy())     return "16";
  if (T->isFloatTy())    return "32";
  if (T->isDoubleTy())   return "64";
  if (auto *VT = dyn_cast<VectorType>(T))
    return std::to_string((unsigned)VT->getScalarSizeInBits()) + "v";
  return "unknown";
}

static std::string scevToStr(const SCEV *S) {
  std::string Tmp; raw_string_ostream OS(Tmp);
  if (S) S->print(OS); else OS << "?";
  return OS.str();
}

static StringRef opKind(const Instruction &I) {
  switch (I.getOpcode()) {
    case Instruction::Add:
    case Instruction::FAdd: return "add";
    case Instruction::Mul:
    case Instruction::FMul: return "mul";
    case Instruction::Sub:
    case Instruction::FSub: return "sub";
    case Instruction::PHI:  return "phi";
    case Instruction::Load: return "load";
    case Instruction::Store:return "store";
    default:                return "other";
  }
}

// Return base pointer (argument) if GEP/bitcast chain originates from arg.
static const Value* traceBasePtr(const Value *V) {
  const Value *Cur = V;
  while (true) {
    if (auto *BC = dyn_cast<BitCastOperator>(Cur)) {
      Cur = BC->getOperand(0); continue;
    }
    if (auto *G = dyn_cast<GEPOperator>(Cur)) {
      Cur = G->getPointerOperand(); continue;
    }
    if (auto *I = dyn_cast<Instruction>(Cur)) {
      if (auto *BCI = dyn_cast<BitCastInst>(I)) { Cur = BCI->getOperand(0); continue; }
      if (auto *GEP = dyn_cast<GetElementPtrInst>(I)) { Cur = GEP->getPointerOperand(); continue; }
    }
    break;
  }
  return Cur;
}

static bool isInnermost(Loop *L) { return L && L->getSubLoops().empty(); }

// --- PASS -------------------------------------------------------------------
struct KernelDFGPass : PassInfoMixin<KernelDFGPass> {
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &FAM) {
    if (F.isDeclaration()) return PreservedAnalyses::all();

    auto &LI = FAM.getResult<LoopAnalysis>(F);
    auto &SE = FAM.getResult<ScalarEvolutionAnalysis>(F);

    // Map pointer arguments -> tensor names (A,B,C...) in function order
    std::map<const Argument*, std::string> tensorOfArg;
    const char *DefaultNames[] = {"A","B","C","D","E"};
    unsigned tix = 0;
    for (auto &Arg : F.args()) {
      if (Arg.getType()->isPointerTy()) {
        std::string nm = Arg.hasName() ? Arg.getName().str() : DefaultNames[std::min(tix,(unsigned)4)];
        // If param name looks like a known tensor, keep it; else assign A/B/C...
        if (!(nm == "A" || nm == "B" || nm == "C" || nm == "D" || nm == "E"))
          nm = DefaultNames[std::min(tix,(unsigned)4)];
        tensorOfArg[&Arg] = nm; tix++;
      }
    }

    // Collect loops (order = pre-order)
    struct LoopRec { std::string name, lb, ub, step; bool innermost=false; };
    std::vector<LoopRec> loops;
    std::set<const Loop*> loopSet;

    auto collectLoopTree = [&](Loop *Top) {
      SmallVector<Loop*, 8> stk{Top};
      while (!stk.empty()) {
        Loop *L = stk.pop_back_val();
        loopSet.insert(L);
        const SCEV *BTC  = SE.getBackedgeTakenCount(L);
        const SCEV *Step = nullptr;
        if (PHINode *Iv = L->getCanonicalInductionVariable()) {
            if (const auto *AR = dyn_cast<SCEVAddRecExpr>(SE.getSCEV(Iv))) {
                Step = AR->getStepRecurrence(SE);
            }
        }

        LoopRec R;
        R.name  = (L->getHeader() && L->getHeader()->hasName())
                  ? std::string(L->getHeader()->getName()) : "loop";
        R.lb    = "0";
        R.ub    = scevToStr(BTC);
        R.step  = scevToStr(Step);
        R.innermost = isInnermost(L);
        loops.push_back(R);
        stk.append(L->begin(), L->end());
      }
    };
    for (auto *Top : LI.getTopLevelLoops()) collectLoopTree(Top);

    // Node & edge storage
    struct Node {
      unsigned id; std::string op; std::string bw;
      std::string tensor;  // for load/store
      std::string index;   // pretty SCEV addr expr
      std::string redVar;  // "k" if reduction PHI over k
    };
    struct Edge { unsigned src, dst; std::string type; };
    std::map<const Instruction*, unsigned> idOf;
    std::vector<Node> nodes;
    std::vector<Edge> edges;
    unsigned nextId = 0;

    auto addNode = [&](const Instruction *I, StringRef kind) {
      auto it = idOf.find(I);
      if (it != idOf.end()) return it->second;
      std::string bw = I->getType()->isVoidTy() ? "void" : tyBits(I->getType());
      nodes.push_back({nextId, std::string(kind), bw, "", "", ""});
      idOf[I] = nextId;
      return nextId++;
    };

    // Build nodes for interesting ops + annotate load/store with tensor/index.
    for (auto &BB : F) {
      for (auto &I : BB) {
        StringRef kind = opKind(I);
        switch (I.getOpcode()) {
          case Instruction::Add: case Instruction::FAdd:
          case Instruction::Mul: case Instruction::FMul:
          case Instruction::Sub: case Instruction::FSub:
          case Instruction::PHI:
          case Instruction::Load: case Instruction::Store: {
            unsigned nid = addNode(&I, kind);
            if (auto *Ld = dyn_cast<LoadInst>(&I)) {
              const Value *Ptr = Ld->getPointerOperand();
              const Value *Base = traceBasePtr(Ptr);
              std::string tensor="";
              if (auto *A = dyn_cast<Argument>(Base)) {
                auto it = tensorOfArg.find(A);
                if (it != tensorOfArg.end()) tensor = it->second;
              }
              // Index using SCEV on pointer
              const SCEV *AddrS = SE.getSCEV(const_cast<Value*>(Ptr));
              nodes[nid].tensor = tensor;
              nodes[nid].index  = scevToStr(AddrS);
            } else if (auto *St = dyn_cast<StoreInst>(&I)) {
              const Value *Ptr = St->getPointerOperand();
              const Value *Base = traceBasePtr(Ptr);
              std::string tensor="";
              if (auto *A = dyn_cast<Argument>(Base)) {
                auto it = tensorOfArg.find(A);
                if (it != tensorOfArg.end()) tensor = it->second;
              }
              const SCEV *AddrS = SE.getSCEV(const_cast<Value*>(Ptr));
              nodes[nid].tensor = tensor;
              nodes[nid].index  = scevToStr(AddrS);
            }
            break;
          }
          default: break;
        }
      }
    }

    // Def-use data edges
    for (auto &BB : F) {
      for (auto &I : BB) {
        auto jt = idOf.find(&I);
        if (jt == idOf.end()) continue;
        for (auto &Op : I.operands()) {
          if (auto *DefI = dyn_cast<Instruction>(Op)) {
            auto it = idOf.find(DefI);
            if (it != idOf.end())
              edges.push_back({it->second, jt->second, "data"});
          }
        }
      }
    }

    // Reduction detection: innermost loop, PHI used in Add with backedge.
    for (auto &BB : F) {
      auto *L = LI.getLoopFor(&BB);
      if (!L || !L->getSubLoops().empty()) continue; // only innermost
      for (auto &I : BB) {
        if (auto *Phi = dyn_cast<PHINode>(&I)) {
          // Pattern: acc_{t+1} = acc_t (+) f(k)
          for (User *U : Phi->users()) {
            if (auto *Add = dyn_cast<BinaryOperator>(U)) {
              if (Add->getOpcode() != Instruction::FAdd &&
                  Add->getOpcode() != Instruction::Add) continue;
              // One operand is the PHI itself
              if (Add->getOperand(0) != Phi && Add->getOperand(1) != Phi) continue;
              // Check recurrence: Add result feeds back to Phi on backedge
              bool feedsBack = false;
              for (unsigned i = 0; i < Phi->getNumIncomingValues(); ++i) {
                if (Phi->getIncomingValue(i) == Add &&
                    L->contains(Phi->getIncomingBlock(i))) {
                  feedsBack = true; break;
                }
              }
              if (!feedsBack) continue;
              // Tag PHI node as reduction over L (name ≈ induction var header)
              auto it = idOf.find(Phi);
              if (it != idOf.end()) {
                // Try to name the reduction var from the inner loop header
                std::string red = "k";
                if (L->getHeader() && L->getHeader()->hasName())
                  red = L->getHeader()->getName().str();
                nodes[it->second].redVar = red;
              }
            }
          }
        }
      }
    }

    // --- JSON dump ----------------------------------------------------------
    std::error_code EC;
    raw_fd_ostream OS(DFGOut, EC, sys::fs::OF_Text);
    if (EC) {
      errs() << "Failed to open " << DFGOut << " : " << EC.message() << "\n";
      return PreservedAnalyses::all();
    }

    OS << "{\n";
    OS << "  \"kernel\": \"" << F.getName() << "\",\n";

    // loops
    OS << "  \"loops\": [\n";
    for (size_t i = 0; i < loops.size(); ++i) {
      auto &Lr = loops[i];
      OS << "    {\"name\":\"" << Lr.name << "\","
         << "\"lb\":\"" << Lr.lb << "\","
         << "\"ub\":\"" << Lr.ub << "\","
         << "\"step\":\"" << Lr.step << "\","
         << "\"innermost\":" << (Lr.innermost ? "true":"false") << "}";
      OS << (i + 1 == loops.size() ? "\n" : ",\n");
    }
    OS << "  ],\n";

    // nodes
    OS << "  \"dfg\": {\n";
    OS << "    \"nodes\": [\n";
    for (size_t i = 0; i < nodes.size(); ++i) {
      auto &N = nodes[i];
      OS << "      {\"id\":\"n" << N.id << "\","
         << "\"op\":\"" << N.op << "\","
         << "\"bw\":\"" << N.bw << "\"";
      if (!N.tensor.empty()) OS << ",\"tensor\":\"" << N.tensor << "\"";
      if (!N.index.empty())  OS << ",\"index\":\""  << N.index  << "\"";
      if (!N.redVar.empty()) OS << ",\"reduction\":\"" << N.redVar << "\"";
      OS << "}";
      OS << (i + 1 == nodes.size() ? "\n" : ",\n");
    }
    OS << "    ],\n";

    // edges
    OS << "    \"edges\": [\n";
    for (size_t i = 0; i < edges.size(); ++i) {
      auto &E = edges[i];
      OS << "      {\"src\":\"n" << E.src << "\","
         << "\"dst\":\"n" << E.dst << "\","
         << "\"type\":\"" << E.type << "\"}";
      OS << (i + 1 == edges.size() ? "\n" : ",\n");
    }
    OS << "    ]\n";
    OS << "  }\n";
    OS << "}\n";

    return PreservedAnalyses::all();
  }
};

} // namespace

// Plugin registration (new PM)
extern "C" ::llvm::PassPluginLibraryInfo llvmGetPassPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "KernelDFGPass", "0.2",
          [](PassBuilder &PB) {
            PB.registerPipelineParsingCallback(
                [](StringRef Name, FunctionPassManager &FPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name == "kernel-dfg") {
                    FPM.addPass(KernelDFGPass());
                    return true;
                  }
                  return false;
                });
          }};
}
