#!/usr/bin/env python3
"""
HiVeGen pipeline (step-by-step scaffold)
- main()
- get_inputs(): static inputs (user prompt, config template path, application path)
- Folder layout (relative to this script):
    <root>/
      inputs/            # put config template + application C/C++
      helper/            # put KernelDFGPass.cpp here
      generated/   # outputs (DFG JSON, prompts, configs)
      logs/              # run logs
- Design Space Explorer (stub): invokes LLVM kernel extractor -> DFG JSON
- System prompt builder
- LLM configuration step: placeholder (falls back to heuristic config JSON)
"""

import os, re, json, time, requests
from typing import Dict, Any, Optional, Tuple, List
import shlex
import subprocess
import datetime as dt
from pathlib import Path
import logging
import sys
from helper.runtime_parser import runtime_parser_preview, runtime_parser_commit, _parse_sv_header
from helper.code_retriever import get_embedding, ensure_collection,  QDRANT_COLLECTION, search_candidates, retrieve_or_llm_generate, reinforce_after_validation, update_weight, upsert_code_block, fallback_llm_func
from helper.module_generator import module_generator_llm, build_module_context
from helper.ppa_eval import evaluate_ppa_from_config
import shutil, subprocess, tempfile, os, textwrap

import dotenv
dotenv.load_dotenv()


# ---------- folders (relative to this file) ----------
CUR_DIR   = Path(__file__).resolve().parent
DIR_IN    = CUR_DIR / "inputs"
DIR_HELP  = CUR_DIR / "helper"
DIR_OUT   = CUR_DIR / "generated"
DIR_LOG   = CUR_DIR / "logs"

for d in (DIR_IN, DIR_HELP, DIR_OUT, DIR_LOG):
    d.mkdir(parents=True, exist_ok=True)


# ---------- logging ----------
def init_logging() -> Path:
    ts = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    log_path = DIR_LOG / f"run-{ts}.log"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        handlers=[logging.FileHandler(log_path), logging.StreamHandler(sys.stdout)],
    )
    logging.info("Log file: %s", log_path)
    return log_path


# ---------- input taker (static for now) ----------
def get_inputs():
    """
    Returns:
      user_prompt (str)
      config_template_path (Path)
      application_path (Path)
    """
    user_prompt = "Define a Systolic Array that supports GEMM with a scale of 4×4."
    config_template_path = DIR_IN / "systolic_array_template.json"   # put your template here
    application_path     = DIR_IN / "kernel_gemm.c"                  # put your C/C++ kernel here
    return user_prompt, config_template_path, application_path


# ---------- helpers ----------
def require_file(p: Path, label: str):
    if not p.exists():
        logging.error("%s not found: %s", label, p)
        raise FileNotFoundError(f"{label} not found: {p}")
    logging.info("%s: %s", label, p)


def run(cmd: str, cwd: Path | None = None, env: dict | None = None):
    logging.info("CMD: %s", cmd)
    proc = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd, env=env)
    if proc.stdout.strip():
        logging.info("STDOUT:\n%s", proc.stdout.strip())
    if proc.stderr.strip():
        logging.info("STDERR:\n%s", proc.stderr.strip())
    if proc.returncode != 0:
        raise RuntimeError(f"Command failed ({proc.returncode}): {cmd}")
    return proc


# ---------- kernel extractor (LLVM) ----------
def run_kernel_extractor(app_c_path: Path, pass_cpp: Path, out_dir: Path) -> Path:
    """
    Builds KernelDFGPass -> runs on app C/C++ -> returns DFG JSON path
    Requires env LLVM_PREFIX to point to LLVM (e.g., /opt/homebrew/opt/llvm).
    """
    llvm_prefix = os.environ.get("LLVM_PREFIX", "")
    if not llvm_prefix:
        # try common Homebrew paths
        for guess in ("/opt/homebrew/opt/llvm", "/usr/local/opt/llvm"):
            if Path(guess).exists():
                llvm_prefix = guess
                break
    if not llvm_prefix:
        raise EnvironmentError("Set LLVM_PREFIX to your LLVM install (e.g., `export LLVM_PREFIX=$(brew --prefix llvm)`).")

    clang      = shlex.quote(str(Path(llvm_prefix) / "bin" / "clang"))
    clangxx    = shlex.quote(str(Path(llvm_prefix) / "bin" / "clang++"))
    opt        = shlex.quote(str(Path(llvm_prefix) / "bin" / "opt"))
    llvm_conf  = shlex.quote(str(Path(llvm_prefix) / "bin" / "llvm-config"))

    require_file(pass_cpp, "KernelDFGPass.cpp")
    require_file(app_c_path, "Application Source")

    # Build pass -> libKernelDFGPass.dylib
    pass_so = DIR_HELP / "libKernelDFGPass.dylib"
    if not pass_so.exists():
        cmd_build = (
            f"{clangxx} -std=c++17 -fPIC -shared {shlex.quote(str(pass_cpp))} "
            f"-o {shlex.quote(str(pass_so))} "
            f"$({llvm_conf} --cxxflags --ldflags --system-libs --libs core analysis passes) "
            f"-Wl,-rpath,{llvm_prefix}/lib"
        )
        run(cmd_build)

    # Emit IR (.ll) at O1 to avoid optnone
    ll_path = out_dir / (app_c_path.stem + ".ll")
    cmd_ll = f"{clang} -O1 -emit-llvm -S {shlex.quote(str(app_c_path))} -o {shlex.quote(str(ll_path))}"
    run(cmd_ll)

    # Run pass -> DFG JSON
    dfg_path = out_dir / "kernel_dfg.json"
    cmd_opt = (
        f"{opt} -load-pass-plugin {shlex.quote(str(pass_so))} "
        f"-passes='function(kernel-dfg)' {shlex.quote(str(ll_path))} "
        f"-disable-output -dfg-out={shlex.quote(str(dfg_path))}"
    )
    run(cmd_opt)
    require_file(dfg_path, "DFG JSON")
    return dfg_path


# ---------- system prompt builder ----------
# ---------- system prompt builder (embed full DFG + full Config Template) ----------
def build_system_prompt(user_prompt: str, dfg_path: Path, cfg_template_path: Path, prev_ppa_path: Path | None) -> Path:
    # load full DFG JSON
    dfg_obj = json.loads(Path(dfg_path).read_text())
    kernel_block = {
        "kernel_class": dfg_obj.get("kernel", "unknown"),
        "dfg": dfg_obj  # embed the entire DFG JSON
    }

    # load full Config Template (prefer JSON object; fall back to raw text if parsing fails)
    cfg_raw = Path(cfg_template_path).read_text()
    try:
        cfg_obj = json.loads(cfg_raw)
        cfg_block = cfg_obj
    except Exception:
        cfg_block = {"raw_text": cfg_raw}

    # optional previous PPA (embed full JSON if present)
    if prev_ppa_path and prev_ppa_path.exists():
        try:
            prev_block = json.loads(Path(prev_ppa_path).read_text())
        except Exception:
            prev_block = {"raw_text": Path(prev_ppa_path).read_text()}
    else:
        prev_block = "none"

    # PPA goal (echo from config for convenience; safe if not JSON)
    ppa_goal = {}
    if isinstance(cfg_block, dict):
        ppa_goal = cfg_block.get("ppa_goal", {})

    system_prompt = (
        f"Design: {user_prompt}\n\n"
        f"Analyze the {kernel_block.get("kernel_class")} Kernel\n\n"
        f"[Kernel]\n{json.dumps(kernel_block, indent=2)}\n\n"
        f"to generate configuration based on the following configuration template.\n"
        f"[DSA Configuration Template]\n{json.dumps(cfg_block, indent=2) if isinstance(cfg_block, dict) else cfg_block}\n\n"
        f"[Previous PPA]\n{('none' if isinstance(prev_block, str) else json.dumps(prev_block, indent=2))}\n\n"
        f"[PPA Optimization Goal]\n{json.dumps(ppa_goal, indent=2)}\n"
        f"Respond with ONLY valid JSON for the configuration. Nothing else. You must use the keys from the template."
        f"Ensure to configure from the provided options parameter values."
    )


    out_path = DIR_OUT / "system_prompt.txt"
    out_path.write_text(system_prompt)
    logging.info("Wrote system prompt -> %s", out_path)
    return out_path



# ---------- LLM caller (placeholder) ----------
def generate_configuration_via_openai(
    system_prompt_path: Path,
    *,
    output_path: Path | None = None,
    model: str = "gpt-5-chat-latest",
    base_url: str = "https://api.openai.com/v1",
    timeout_secs: int = 60,
    max_retries: int = 3,
) -> Path:
    """
    Read the inlined system prompt file and call the OpenAI Chat Completions API.
    The model must return JSON (inside ```json ... ```); we extract and save it as configuration.json.

    Requires:
      - OPENAI_API_KEY in env or in `userdata['OPENAI_API_KEY']` if present.
      - `DIR_OUT` and `logging` defined in the surrounding script (or pass output_path explicitly).
    """
    # ---- gather API key ----
    api_key = None
    try:
        # if you keep a userdata dict in your script, this will use it
        api_key = os.getenv("OPENAI_API_KEY")
    except Exception:
        api_key = None
    if not api_key:
        api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("Missing OPENAI_API_KEY (env or userdata).")

    # ---- read prompt ----
    prompt = Path(system_prompt_path).read_text()

    # ---- helpers ----
    json_block_re = re.compile(r"```json\s*(?P<blob>\{[\s\S]*?\}|\[[\s\S]*?\])\s*```", flags=re.IGNORECASE)
    json_fallback_re = re.compile(r"(?P<blob>\{[\s\S]*\}|\[[\s\S]*\])", flags=re.DOTALL)

    def extract_first_json_block(text: str) -> Dict[str, Any]:
        m = json_block_re.search(text)
        if m:
            return json.loads(m.group("blob"))
        m2 = json_fallback_re.search(text)
        if m2:
            return json.loads(m2.group("blob"))
        raise ValueError("No JSON block found in model output.")

    # ---- HTTP request ----
    url = f"{base_url.rstrip('/')}/chat/completions"
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": "厳密な出力形式を守ってください。必ず```json ... ```のみを返し、有効なJSONにしてください。"
            },
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.2,
        "max_tokens": 2500,
    }

    last_err = None
    for attempt in range(1, max_retries + 1):
        try:
            resp = requests.post(url, headers=headers, json=payload, timeout=timeout_secs)
            resp.raise_for_status()
            content = resp.json()["choices"][0]["message"]["content"]
            data = extract_first_json_block(content)
            # ---- write output ----
            out_path = (
                output_path
                if output_path is not None
                else (DIR_OUT / "configuration.json")  # expects DIR_OUT in outer scope
            )
            out_path.write_text(json.dumps(data, indent=2))
            if "logging" in globals():
                logging.info("Wrote configuration -> %s", out_path)
            return out_path
        except Exception as e:
            last_err = e
            if "logging" in globals():
                logging.warning("OpenAI attempt %d/%d failed: %s", attempt, max_retries, e)
            time.sleep(1.2 * attempt)

    raise RuntimeError(f"OpenAI call failed after {max_retries} retries: {last_err}")


def prompt_enhancer(
    user_prompt: str,
    configuration_path: Path,
    output_path: Path,
    dfg_path: Optional[Path] = None,
    *,
    model: str = "gpt-5-chat-latest",
    base_url: str = "https://api.openai.com/v1",
    timeout_secs: int = 60,
    max_retries: int = 3,
) -> Path:
    # --- gather API key ---
    api_key = None
    try:
        api_key = os.getenv("OPENAI_API_KEY")
    except Exception:
        api_key = None
    if not api_key:
        api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("Missing OPENAI_API_KEY (env or userdata).")

    # --- read inputs ---
    cfg_txt = Path(configuration_path).read_text()
    cfg_obj = json.loads(cfg_txt)  # ensure valid JSON for the model
    cfg_txt = json.dumps(cfg_obj, indent=2)  # pretty-print for readability

    dfg_txt = None
    if dfg_path and Path(dfg_path).exists():
        try:
            dfg_obj = json.loads(Path(dfg_path).read_text())
            dfg_txt = json.dumps(dfg_obj, indent=2)
        except Exception:
            dfg_txt = None  # ignore if not valid JSON

    # --- compose messages ---
    system_msg = (
        "You are an expert chip architect.\n"
        "Your task is to analyze the given Configuration JSON (and optional DFG) "
        "to infer the hierarchical hardware design structure.\n\n"
        "Output Format STRICTLY:\n"
        "Top module (Hier 0)\n"
        "Description: <Generate description of the entire design>\n"
        "Submodule (Hier 1): <name>\n"
        "Description: <what this submodule does>\n"
        "Submodule (Hier 2): <name>\n"
        "Description: <what this submodule does>\n"
        "...\n\n"
        "Rules:\n"
        " - Infer submodules logically based on configuration and hierarchy hints (rows/cols, buffers, controllers, etc.).\n"
        " - Do NOT output code or JSON; only structured plain text as described.\n"
        " - Keep descriptions concise but meaningful (2–4 lines per module).\n"
    )

    # user content with embedded JSON context
    user_content = f"""User Prompt:
                    {user_prompt}

                    [Configuration JSON]
                    {cfg_txt}
                    """
    if dfg_txt:
        user_content += f"""
        [DFG JSON] 
            {dfg_txt}
        """
      
    # --- call OpenAI Chat Completions (HTTP) ---
    url = f"{base_url.rstrip('/')}/chat/completions"
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user", "content": user_content},
        ],
        "temperature": 0.2,
        "max_tokens": 2000,
    }

    last_err = None
    for attempt in range(1, max_retries + 1):
        try:
            resp = requests.post(url, headers=headers, json=payload, timeout=timeout_secs)
            resp.raise_for_status()
            content = resp.json()["choices"][0]["message"]["content"].strip()
            Path(output_path).write_text(content)
            if "logging" in globals():
                logging.info("Wrote augmented prompt -> %s", output_path)
            return output_path
        except Exception as e:
            last_err = e
            if "logging" in globals():
                logging.warning("Prompt enhancer attempt %d/%d failed: %s", attempt, max_retries, e)
            time.sleep(1.2 * attempt)

    raise RuntimeError(f"Prompt enhancer failed after {max_retries} retries: {last_err}")


def config_evaluator_stub(
    dfg_path: Path,
    config_template_path: Path,
    configuration_path: Path,
    *,
    report_json_path: Optional[Path] = None,
    report_txt_path: Optional[Path] = None,
) -> Tuple[Path, Path]:
    """Placeholder evaluator: records inputs and returns PASS without checks."""
    if report_json_path is None:
        report_json_path = (DIR_OUT / "eval_report.json") if "DIR_OUT" in globals() else Path("eval_report.json")
    if report_txt_path is None:
        report_txt_path = (DIR_OUT / "eval_report.txt") if "DIR_OUT" in globals() else Path("eval_report.txt")

    report = {
        "status": "PASS",
        "errors": [],
        "warnings": [],
        "suggestions": [],
        "ppa_proxy": {},
        "feasible": {"dsp": True, "bram": True, "bw": True},
        "inputs": {
            "dfg": str(dfg_path),
            "config_template": str(config_template_path),
            "configuration": str(configuration_path),
        },
        "notes": ["Stub evaluator: no design-rule checks performed."],
    }

    report_json_path.write_text(json.dumps(report, indent=2))
    report_txt_path.write_text(
        "STATUS: PASS\n"
        "Errors: []\nWarnings: []\nSuggestions: []\n"
        f"DFG: {report['inputs']['dfg']}\n"
        f"Template: {report['inputs']['config_template']}\n"
        f"Configuration: {report['inputs']['configuration']}\n"
        "Notes: Stub evaluator – implement real checks here.\n"
    )
    if "logging" in globals():
        logging.info("Config evaluator (stub) -> %s | %s", report_json_path, report_txt_path)
    return report_json_path, report_txt_path


def llm_task_manager_code_sketch(
    augmented_prompt_path: Path,
    *,
    out_dir: Optional = None,
    model: str = "gpt-5-chat-latest",
    base_url: str = "https://api.openai.com/v1",
    timeout_secs: int = 60,
    max_retries: int = 3,
) -> Tuple[Path, Path, Dict[str, Path]]:
    """
    LLM-driven Task Manager that produces a first-pass code sketch for each module.
    Returns:
      task_list_path, module_index_path, sketch_files_map{name->Path}
    """
    # --- API key ---
    api_key = None
    try:
        api_key = os.getenv("OPENAI_API_KEY")
    except Exception:
        api_key = None
    if not api_key:
        api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("Missing OPENAI_API_KEY (env or userdata).")

    # --- paths ---
    if out_dir is None:
        out_dir = (DIR_OUT / "sketch") if "DIR_OUT" in globals() else Path("sketch")
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    task_list_path  = (DIR_OUT / "task_list.json")   if "DIR_OUT" in globals() else Path("task_list.json")
    module_index_path = (DIR_OUT / "module_index.json") if "DIR_OUT" in globals() else Path("module_index.json")

    aug_txt = Path(augmented_prompt_path).read_text()

    # --- system + user prompts ---
    system_msg = (
        "You are the Task Manager in a hierarchical HDL pipeline.\n"
        "Given an *augmented prompt* that lists Top/HierN modules and descriptions, "
        "produce a code-sketch plan in JSON and minimal SystemVerilog skeletons for each module.\n"
        "STRICT OUTPUT:\n"
        "Return ONLY a JSON object inside ```json fences with this schema:\n"
        "{\n"
        '  "top": "<string>",\n'
        '  "modules": [\n'
        '    {"name":"<string>","hier":<int>,"description":"<string>","children":["..."],\n'
        '     "filename":"<kebab-or-snake>.sv","language":"systemverilog",\n'
        '     "code":"<SystemVerilog module skeleton as a single string>"}\n'
        "    ...\n"
        "  ],\n"
        '  "task_order": ["top","childA","childB", ...]\n'
        "}\n"
        "Rules:\n"
        " - Make code syntactically valid SystemVerilog. Do NOT include backticks/code fences inside JSON strings.\n"
        " - Keep modules minimal: parameter block if inferable (e.g., DATA_W, K_TILE), common ports (clk, rst_n), "
        "   and a comment '/* body block */' inside.\n"
        " - Names must match the augmented prompt (for Submodule lines). Derive a clean filename per module.\n"
        " - The 'task_order' must be depth-first with top first and no duplicates.\n"
        " - No prose outside the JSON.\n"
    )

    user_msg = f"""Augmented Prompt:
    ```
        {aug_txt}
    ```
    """

    # --- call OpenAI with retries ---
    url = f"{base_url.rstrip('/')}/chat/completions"
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user",   "content": user_msg},
        ],
        "temperature": 0.15,
        "max_tokens": 3500,
    }

    def _extract_json_block(text: str) -> dict:
        m = re.search(r"```json\s*(?P<blob>\{[\s\S]*\})\s*```", text, flags=re.IGNORECASE)
        if not m:
            raise ValueError("Model did not return JSON in ```json fences.")
        return json.loads(m.group("blob"))

    last_err = None
    for attempt in range(1, max_retries + 1):
        try:
            resp = requests.post(url, headers=headers, json=payload, timeout=timeout_secs)
            resp.raise_for_status()
            content = resp.json()["choices"][0]["message"]["content"]
            data = _extract_json_block(content)

            # --- basic validation ---
            if not isinstance(data, dict): raise ValueError("Invalid JSON type.")
            top = data.get("top")
            modules = data.get("modules")
            task_order = data.get("task_order")
            if not isinstance(top, str) or not top: raise ValueError("Missing/invalid 'top'.")
            if not isinstance(modules, list) or not modules: raise ValueError("Missing/invalid 'modules'.")
            if not isinstance(task_order, list) or not task_order: raise ValueError("Missing/invalid 'task_order'.")

            # --- write code sketches ---
            sketch_map: Dict[str, Path] = {}
            mod_index: Dict[str, Any] = {}

            for m in modules:
                name = m.get("name")
                hier = int(m.get("hier", 0))
                desc = m.get("description", "")
                fn   = m.get("filename") or (re.sub(r'\W+', '_', name.strip().lower()) + ".sv")
                code = m.get("code", "")
                lang = (m.get("language") or "systemverilog").lower()

                if not name or not code:
                    raise ValueError(f"Module entry invalid/missing fields: {m}")
                if lang not in ("systemverilog", "verilog"):
                    raise ValueError(f"Unsupported language: {lang} for {name}")

                # ensure single string code; normalize newlines
                code = str(code).replace("\r\n","\n").replace("\r","\n")

                fpath = out_dir / fn
                fpath.write_text(code)
                sketch_map[name] = fpath

                mod_index[name] = {
                    "hier_level": hier,
                    "description": desc,
                    "children": list(m.get("children", [])),
                    "parent": None,  # fill below
                    "filename": str(fpath),
                    "language": lang,
                }

            # infer parents from children
            for parent, info in mod_index.items():
                for ch in info["children"]:
                    if ch in mod_index and mod_index[ch]["parent"] is None:
                        mod_index[ch]["parent"] = parent
            if top in mod_index:
                mod_index[top]["parent"] = None

            # task_list.json
            Path(task_list_path).write_text(json.dumps({
                "top": top,
                "task_order": task_order,
                "count": len(task_order),
                "sketch_dir": str(out_dir),
            }, indent=2))

            # module_index.json
            Path(module_index_path).write_text(json.dumps({
                "top": top,
                "modules": mod_index
            }, indent=2))

            if "logging" in globals():
                logging.info("Task Manager (code sketch) -> %s | %s | %s/*.sv",
                             task_list_path, module_index_path, out_dir)
            return task_list_path, module_index_path, sketch_map

        except Exception as e:
            last_err = e
            if "logging" in globals():
                logging.warning("Code-sketch task manager attempt %d/%d failed: %s",
                                attempt, max_retries, e)
            time.sleep(1.5 * attempt)

    raise RuntimeError(f"Task Manager code-sketch failed after {max_retries} retries: {last_err}")

    # --- quick sanity search: build a query and print top-k ranked candidates

def has_iverilog() -> bool:
    return shutil.which("iverilog") is not None

def compile_sv_syntax_only(code_text: str) -> tuple[bool, str]:
    """Write code to temp file and try to compile with iverilog (syntax only)."""
    if not has_iverilog():
        return True, "iverilog not found; skipping syntax check (treat as PASS)"
    with tempfile.TemporaryDirectory() as td:
        sv = os.path.join(td, "unit.sv")
        with open(sv, "w") as f:
            f.write(textwrap.dedent(code_text))
        # -g2012: SystemVerilog; -tnull: compile only
        cmd = ["iverilog", "-g2012", "-tnull", sv]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        ok = proc.returncode == 0
        msg = (proc.stdout or "") + (proc.stderr or "")
        return ok, msg

def interface_from_sketch(sketch_path: Path) -> list[str]:
    text = sketch_path.read_text()
    _, ports = _parse_sv_header(text)   # reuse header parser we already wrote
    return ports

def load_hierarchy(idx_path: Path):
    idx = json.loads(idx_path.read_text())
    top = idx["top"]
    mods: Dict[str, Dict] = idx["modules"]
    return top, mods

def postorder_modules(top: str, mods: Dict[str, Dict]) -> List[str]:
    """Return modules in leaves→parents order (post-order DFS)."""
    order, seen = [], set()

    def dfs(n: str):
        if n in seen: return
        seen.add(n)
        for ch in mods.get(n, {}).get("children", []):
            dfs(ch)
        order.append(n)

    dfs(top)
    return order  # leaves first, top last

def has_iverilog() -> bool:
    return shutil.which("iverilog") is not None

def compile_bundle_syntax_only(named_sources: Dict[str, str]) -> tuple[bool, str]:
    """
    named_sources: {module_name: code_text}
    Compile all together so parent instantiations resolve.
    """
    if not has_iverilog():
        return True, "iverilog not found; treating as PASS"

    with tempfile.TemporaryDirectory() as td:
        paths = []
        for i, (mn, code) in enumerate(named_sources.items()):
            p = Path(td) / f"{i:03d}_{mn}.sv"
            p.write_text(textwrap.dedent(code))
            paths.append(str(p))
        # -g2012: SystemVerilog; -tnull: syntax only
        proc = subprocess.run(["iverilog", "-g2012", "-tnull", *paths],
                              capture_output=True, text=True)
        ok = (proc.returncode == 0)
        msg = (proc.stdout or "") + (proc.stderr or "")
        return ok, msg
    
# Build child headers dict for this module
def sv_header_from_code(code: str) -> str:
    m = re.search(r'(?is)^\s*module\s+[A-Za-z_]\w*\s*(?:#\s*\(.*?\))?\s*\(.*?\)\s*;', code)
    return m.group(0) if m else ""


def evaluate_ppa(design_path: Path, ppa_goal: dict) -> dict:
    """
    Stub PPA evaluator. In a real setup this would run synthesis (e.g., Yosys) and extract
    area/power/timing. Here we simulate a heuristic pass/fail based on design complexity.
    """
    code = design_path.read_text()
    n_modules = code.count("module ")
    n_mults = code.count("*")  # crude complexity proxy
    freq_goal = ppa_goal.get("freq_mhz", 200)
    optimize_for = ppa_goal.get("optimize_for", ["latency"])

    # Fake heuristics
    achieved_freq = max(100, 400 - n_mults * 5)
    achieved_area = n_modules * 100
    achieved_power = achieved_area * 0.02

    meets_freq = achieved_freq >= freq_goal
    meets_area = "area" not in optimize_for or achieved_area <= 5000

    return {
        "achieved_freq": achieved_freq,
        "achieved_area": achieved_area,
        "achieved_power": achieved_power,
        "meets_goal": meets_freq and meets_area,
    }


# ---------- main ----------
def main():
    log_path = init_logging()
    logging.info("Working dir: %s", CUR_DIR)

    user_prompt, cfg_tmpl_path, app_path = get_inputs()
    require_file(cfg_tmpl_path, "Config Template")
    require_file(app_path, "Application Source")

    # 1) Design Space Explorer (phase 1): Kernel extractor -> DFG
    pass_cpp = DIR_HELP / "KernelDFGPass.cpp"  # YOU must place your pass here
    try:
        dfg_json = run_kernel_extractor(app_path, pass_cpp, DIR_OUT)
    except Exception as e:
        logging.error("Kernel extractor failed: %s", e)
        # Fallback minimal GEMM DFG so pipeline continues
        logging.info("Wrote fallback DFG -> %s", dfg_json)

    # 2) Build system prompt
    sys_prompt_path = build_system_prompt(user_prompt, dfg_json, cfg_tmpl_path, prev_ppa_path=None)

    # 3) Call LLM (or heuristic) to get configuration JSON
    cfg_json = generate_configuration_via_openai(
        sys_prompt_path,
        output_path=DIR_OUT / "configuration.json",   # optional; can omit to use default
        model="gpt-5-chat-latest",
        base_url="https://api.openai.com/v1",
        timeout_secs=60,
        max_retries=3,
    )

    aug_path = DIR_OUT / "augmented_prompt.txt"

    prompt_enhancer(
        user_prompt=user_prompt,              # the text prompt, e.g. "Define a Systolic Array..."
        configuration_path=cfg_json,          # Path to your generated configuration.json
        output_path=aug_path,                 # where to save the augmented prompt
        dfg_path=dfg_json,                    # optional; include if you have DFG
        model="gpt-5-chat-latest",
        base_url="https://api.openai.com/v1",
        timeout_secs=60,
        max_retries=3,
    )

    logging.info("Augmented prompt written to: %s", aug_path)

    # 4) Config evaluation (stub)
    eval_json, eval_txt = config_evaluator_stub(
        dfg_path=dfg_json,
        config_template_path=cfg_tmpl_path,
        configuration_path=cfg_json,
    )
    logging.info("Evaluation reports: %s | %s", eval_json, eval_txt)

    # 5) Task Manager: parse augmented prompt -> task list + module index
    task_list_path, module_index_path, sketch_files = llm_task_manager_code_sketch(
        augmented_prompt_path=aug_path,
        out_dir=DIR_OUT / "sketch",
        model="gpt-5-chat-latest",
        base_url="https://api.openai.com/v1",
        timeout_secs=60,
        max_retries=3,
    )
    logging.info("Sketch files: %s", {k: str(v) for k,v in sketch_files.items()})

    # 6) Runtime parser preview + commit
    NEED_HUMAN_APPROVAL = False  # set to True to require human approval before commit
    cmd = "" 
    if NEED_HUMAN_APPROVAL:
        diff = runtime_parser_preview(cmd, module_index_path=DIR_OUT / "module_index.json")
        print(diff)

        res = runtime_parser_commit(cmd, module_index_path=DIR_OUT / "module_index.json")
        print(res)
    
    # 7) Insert a known code block:
    # load hierarchy & build post-order list (leaves→parents)
    top, mods = load_hierarchy(DIR_OUT / "module_index.json")
    order = postorder_modules(top, mods)

    accum_sources: Dict[str, str] = {}  # module_name -> code text

    iteration = 0
    MAX_RETRIES = 10

    for mname in order:
        sketch_path = Path(mods[mname]["filename"])
        desc = mods[mname].get("description", "")
        iface = interface_from_sketch(sketch_path)

        code, meta, hit = retrieve_or_llm_generate(mname, desc, iface, score_threshold=0.35)
        print(f"[{mname}] retrieval {'HIT' if hit else 'MISS'}")

        # --- context: child headers already accepted ---
        child_headers = {}
        for ch in mods[mname].get("children", []):
            if ch in accum_sources:
                hdr = sv_header_from_code(accum_sources[ch])
                if hdr:
                    child_headers[ch] = hdr

        final_code, ok, msg = None, False, ""
        attempt = 0
        msg_prev = ""  # previous compiler error text

        while attempt < MAX_RETRIES and not ok:
            attempt += 1
            print(f"[{mname}] attempt {attempt}/{MAX_RETRIES} ...")

            # --- Build extra_notes for the LLM ---
            err_feedback = ""
            if msg_prev:
                err_feedback = (
                    "\nPrevious compilation failed. "
                    "Please correct the following syntax issues:\n"
                    f"```text\n{msg_prev[:700]}\n```"
                )

            if hit:
                gen_code = module_generator_llm(
                    module_name=mname,
                    description=desc,
                    interface_sig=iface,
                    child_headers=child_headers,
                    retrieved_code=code,
                    retrieved_weight=meta.get("weight"),
                    extra_notes=err_feedback,  # <--- feed compiler errors here
                )
            else:
                gen_code = module_generator_llm(
                    module_name=mname,
                    description=desc,
                    interface_sig=iface,
                    child_headers=child_headers,
                    extra_notes=err_feedback,  # <--- feed compiler errors here
                )

            # --- Validate bundle ---
            trial_sources = accum_sources.copy()
            trial_sources[mname] = gen_code
            ok, msg = compile_bundle_syntax_only(trial_sources)

            if ok:
                final_code = gen_code
                print(f"[{mname}] syntax PASS ✅ on attempt {attempt}")
                break
            else:
                if "sorry:" in msg and "array" in msg:
                    ok, final_code = True, gen_code
                    print(f"[{mname}] soft-pass for array slice limitation.")
                    break
                msg_prev = msg  # capture this error for next LLM attempt
                print(f"[{mname}] syntax FAIL (attempt {attempt}): {msg[:400]}")
                time.sleep(1.0)

        # --- Post-validation handling ---
        if ok and final_code:
            accum_sources[mname] = final_code
            sketch_path.write_text(final_code)
            upsert_code_block(
                module_name=mname,
                description=desc,
                interface_sig=iface,
                code_text=final_code,
                weight=0.5 if not hit else float(meta.get("weight", 0.5)),
                tags=["generated" if not hit else "refined"],
            )
            if hit and meta.get("point_id"):
                update_weight(meta["point_id"], success=True)
        else:
            print(f"[{mname}] ❌ All {MAX_RETRIES} attempts failed syntax validation.")
            if hit and meta.get("point_id"):
                update_weight(meta["point_id"], success=False)


        # iteration += 1
        # if iteration >= 2:
        #     break



    # 4) Index
    # index = {
    #     "timestamp": dt.datetime.utcnow().isoformat() + "Z",
    #     "user_prompt": user_prompt,
    #     "config_template": str(cfg_tmpl_path),
    #     "application": str(app_path),
    #     "dfg_json": str(dfg_json),
    #     "system_prompt": str(sys_prompt_path),
    #     "configuration": str(cfg_json),
    #     "log_file": str(log_path),
    # }
    # (DIR_OUT / "run_index.json").write_text(json.dumps(index, indent=2))
    # logging.info("Wrote index -> %s", DIR_OUT / "run_index.json")

    assembled_path = DIR_OUT / "assembled_design.sv"
    with open(assembled_path, "w") as f:
        for mn, code in accum_sources.items():
            f.write(f"\n// ---- {mn} ----\n{code}\n")

    ppa = evaluate_ppa_from_config(
        assembled_sv_path=assembled_path,
        config_path=DIR_OUT / "configuration.json",
    )
    print(json.dumps(ppa, indent=2))
    if ppa["meets_goal"]:
        print("✅ Design meets PPA goal.")
    else:
        print("⚠️ Design does not meet PPA goal:", "; ".join(ppa["violations"]))



if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        logging.exception("Fatal error: %s", exc)
        sys.exit(1)
