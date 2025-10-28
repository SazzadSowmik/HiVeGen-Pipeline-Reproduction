# 🧠 HiVeGen: Hierarchical HDL Generation Pipeline  
**Reproduction of the HiVeGen Framework (Sazzadul Islam, 2025)**  
Target Design: 4×4 Systolic Array for GEMM Acceleration

---

## 📘 Overview

This repository implements a complete **hierarchical HDL generation pipeline** inspired by the *HiVeGen* paper.  
The goal is to reproduce its multi-stage workflow for automatic, LLM-driven generation and verification of hardware designs.

Each stage of the pipeline corresponds to one component described in the paper:
```
Prompt → LLVM Kernel Extractor → Config Generator (LLM)
→ Prompt Enhancer → Task Manager → Retriever (RAG)
→ Module Generator (LLM Retry Loop) → Syntax Validator
→ Design Assembler → PPA Evaluator
```

---

## 🧩 Folder Structure

```
HiVeGen/
├── code/
│   ├── demo.py                      # Main pipeline entrypoint
│   ├── helper/
│   │   ├── KernelDFGPass.cpp        # LLVM kernel extractor pass
│   │   ├── libKernelDFGPass.dylib   # Compiled LLVM pass
│   ├── inputs/
│   │   ├── systolic_array_template.json  # Configuration template
│   │   ├── kernel_gemm.c                 # Application kernel source
│   ├── generated/
│   │   ├── kernel_dfg.json          # Generated DFG
│   │   ├── configuration.json       # LLM configuration output
│   │   ├── augmented_prompt.txt     # Hierarchical prompt
│   │   ├── module_index.json        # Task manager output
│   │   ├── assembled_design.sv      # Final HDL design
│   │   ├── ppa_report.json          # PPA evaluation report
│   └── logs/
│       ├── run-<timestamp>.log
├── code_library/
│   ├── VerilogEval_Human.jsonl      # Codebase for retriever
├── HiVeGen_Reproduction_Report_SystolicArray.docx
└── README.md
```

---

## 🧠 Pipeline Summary

| Stage | Description | Input | Output | User Input |
|--------|--------------|--------|----------|-------------|
| **1. User Prompt** | Design request | Text | System prompt | ✅ Required |
| **2. Config Template** | Design knobs | JSON file | Template object | ✅ Required |
| **3. Kernel Extractor** | Extract DFG | `kernel_gemm.c` | `kernel_dfg.json` | ✅ Required |
| **4. Config Generator** | Generate config | System prompt | `configuration.json` | Auto |
| **5. Prompt Enhancer** | Build hierarchy | Config JSON | `augmented_prompt.txt` | Auto |
| **6. Retriever** | Find HDL examples | Module query | Retrieved HDL | Auto |
| **7. Module Generator** | Generate/refine HDL | Retrieval + hierarchy | HDL code | Auto |
| **8. Syntax Validator** | Validate HDL | HDL | Pass/Fail | Auto |
| **9. Assembler** | Combine modules | HDL modules | `assembled_design.sv` | Auto |
| **10. PPA Evaluator** | Evaluate design | Assembled RTL + config | `ppa_report.json` | Auto |

---

## 🧾 Inputs

### 🟢 User Prompt
```
Define a Systolic Array that supports GEMM with a scale of 4×4.
```

### 🟢 Configuration Template
```json
{
  "template": "systolic_array",
  "params": {"M": 4, "N": 4, "K": 4, "precision": "int16"},
  "knobs": {
    "rows": 4, "cols": 4,
    "a_linebuf_depth": 64, "b_linebuf_depth": 64,
    "pe_pipeline_depth": 1, "c_accum_depth": 2,
    "bitwidth": "int16", "stationarity": "output"
  },
  "constraints": {
    "dsp_budget": 256, "bram_budget": 128,
    "mem_bw_gbps_max": 12.8, "clock_mhz_max": 300
  },
  "ppa_goal": {
    "freq_mhz": 200, "optimize_for": ["latency", "area"], "power_hint": "low"
  }
}
```

### 🟢 Kernel Source
```c
void gemm(int M, int N, int K, float A[M][K], float B[K][N], float C[M][N]) {
  for(int i=0;i<M;i++)
    for(int j=0;j<N;j++)
      for(int k=0;k<K;k++)
        C[i][j] += A[i][k] * B[k][j];
}
```

---

## 🚀 Run the Pipeline

### 1️⃣ Setup
```bash
brew install llvm
pip install openai qdrant-client python-docx
export OPENAI_API_KEY="your-key"
```

### 2️⃣ Compile LLVM Pass
```bash
$LLVM_PREFIX/bin/clang++ -std=c++17 -fPIC -shared helper/KernelDFGPass.cpp   -o helper/libKernelDFGPass.dylib   $($LLVM_PREFIX/bin/llvm-config --cxxflags --ldflags --system-libs --libs core analysis passes)
```

### 3️⃣ Execute Pipeline
```bash
cd code
python3 demo.py
```

---

## 🧮 PPA Evaluation (Heuristic)

| Metric | Description |
|---------|--------------|
| **Frequency (MHz)** | Based on array size, pipeline depth, memory bandwidth |
| **DSP / LUT / BRAM** | From config + tech profile |
| **Power (W)** | Estimated switching activity |
| **Pass/Fail** | Compared with `ppa_goal` |

Example:
```json
{
  "achieved_freq": 230.0,
  "achieved_area": 4400,
  "achieved_power": 0.34,
  "meets_goal": true
}
```

---

## 🧩 User Interaction

| Stage | User Input | Type | Required |
|--------|-------------|------|-----------|
| User Prompt | Design target | Text | ✅ |
| Config Template | System parameters | JSON | ✅ |
| Runtime Parser | Optional manual fix | Interactive | ❌ |
| All Other Stages | Automated | LLM / Scripts | ✅ Auto |

---

## 📊 Example Outputs

| File | Description |
|------|--------------|
| `kernel_dfg.json` | LLVM DFG output |
| `configuration.json` | LLM config |
| `augmented_prompt.txt` | Hierarchical prompt |
| `assembled_design.sv` | Final RTL |
| `ppa_report.json` | PPA results |

---

## 🧠 Result Summary

| Metric | Result |
|---------|---------|
| Syntax Pass Rate | 100% |
| Retrieval Accuracy | ~80% |
| Final Frequency | 230 MHz |
| Power Estimate | 0.34 W |
| Meets PPA Goal | ✅ Yes |

---

## 📚 References
- HiVeGen: Hierarchy-aware LLM-based Design Space Exploration Framework for DSAs (2024)
- VerilogEval Dataset (2023)
- Vitis Libraries (BLAS)

---

### 🧭 Maintainer
**Sazzadul Islam**  
[LinkedIn](https://www.linkedin.com/in/sazzad-sowmik/) | [Website](https://sites.google.com/view/sazzadul-islam-sowmik/home?authuser=0)
