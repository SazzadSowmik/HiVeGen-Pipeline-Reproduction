import os, re, time, requests
from typing import List, Optional, Dict
import logging
import dotenv
dotenv.load_dotenv()

OPENAI_API_KEY   = os.getenv("OPENAI_API_KEY")
OPENAI_BASE_URL  = "https://api.openai.com/v1"
OPENAI_MODEL     = "gpt-5-chat-latest"

def _extract_code_block(content: str) -> str:
    m = re.search(r"```(?:systemverilog|verilog)?\s*([\s\S]*?)```", content, flags=re.IGNORECASE)
    return (m.group(1).strip() if m else content.strip())

def sv_header_from_code(code: str) -> str:
    # extract "module ... (...);" line(s) only
    import re
    m = re.search(r'(?is)^\s*module\s+[A-Za-z_]\w*\s*(?:#\s*\(.*?\))?\s*\(.*?\)\s*;', code)
    return m.group(0) if m else ""

def _format_child_headers(child_headers: Dict[str, str]) -> str:
    """child_headers: {child_name: 'module child(...);'}  (headers only)"""
    if not child_headers:
        return ""
    blocks = []
    for ch, hdr in child_headers.items():
        blocks.append(f"// child: {ch}\n{hdr}")
    return "Prior lower-level module interfaces (headers only):\n```systemverilog\n" + "\n\n".join(blocks) + "\n```"

def build_module_context(module_name: str, mods: dict, accum_sources: dict) -> str:
    """
    For the module being generated, gather child module headers and a compact design summary.
    accum_sources: {name: accepted_code_text} of lower modules already generated.
    """
    children = mods.get(module_name, {}).get("children", [])
    headers = []
    for ch in children:
        code = accum_sources.get(ch)
        if code:
            hdr = sv_header_from_code(code)
            if hdr:
                headers.append(f"// child: {ch}\n{hdr}")
    ctx = ""
    if headers:
        ctx += "Prior lower-level module interfaces (headers only):\n"
        ctx += "```systemverilog\n" + "\n\n".join(headers) + "\n```\n"
    # You can add a compact config summary here (bitwidths, stationarity, etc.)
    return ctx

def module_generator_llm(
    module_name: str,
    description: str,
    interface_sig: List[str],
    *,
    child_headers: Optional[Dict[str, str]] = None,   # {child_name: header_line}
    retrieved_code: Optional[str] = None,             # full code from retriever (optional)
    retrieved_weight: Optional[float] = None,
    extra_notes: Optional[str] = None,
    previous_generation: Optional[str] = None,        # previous code that had errors (if any)
    design_facts: Optional[Dict[str, str]] = None,    # e.g., {"DATA_W":"16", "stationarity":"output", ...}
    temperature: float = 0.15,
    timeout_secs: int = 60,
    max_retries: int = 3,
) -> str:
    """
    Always produce final SystemVerilog for `module_name`, adapted to `interface_sig`.
    Context includes:
      - headers of already-built children (non-LLM), to improve instantiation correctness
      - retrieved reference code (if any) + its weight (confidence hint)
      - optional design facts (bitwidth, handshake, tiling)
    """
    if not OPENAI_API_KEY:
        raise RuntimeError("Missing OPENAI_API_KEY")

    ports_text = ", ".join(interface_sig) if interface_sig else "(no ports specified)"
    headers_ctx = _format_child_headers(child_headers or {})

    ref_ctx = ""
    if retrieved_code:
        wtxt = f"{retrieved_weight:.3f}" if retrieved_weight is not None else "n/a"
        ref_ctx = (
            f"Retrieved reference (confidence weight={wtxt}). "
            f"Use it only as inspiration; final code must match the required interface exactly:\n"
            f"```systemverilog\n{retrieved_code}\n```"
        )

    facts_ctx = ""
    if design_facts:
        kv = "\n".join(f"- {k}: {v}" for k, v in design_facts.items())
        facts_ctx = f"Design facts (constraints/hints):\n{kv}\n"

    system_msg = (
        "You generate synthesizable SystemVerilog for exactly ONE module.\n"
        "HARD RULES:\n"
        " - Don't use any code comments or explanations outside the code block.\n"
        " - Output ONLY the module inside a ```systemverilog fence.\n"
        " - Module name MUST equal the requested name precisely.\n"
        " - Port names MUST match the requested list exactly (order may differ).\n"
        " - No testbenches, no includes, no packages outside the module.\n"
        " - Use synthesizable constructs; avoid delays and $display/$dump.\n"
        " - Logic must be COMPLETED correctly.\n"
        " - If the submodule has children, instantiate them correctly using the provided headers.\n"
        " - Instead of Array slice assignments use the explicit **nested loops**, So that, I don't get syntax error on iVerilog 'Assignment to an entire array or to an array slice is not yet supported'.\n"
    )

    user_msg = (
        f"Target module name: {module_name}\n"
        f"Description: {description}\n"
        f"Required ports (names must match): {ports_text}\n\n"
        f"{facts_ctx}"
        f"{headers_ctx}\n"
        f"{ref_ctx}\n"
        f"{'Previous code with syntax errors: ```systemverilog\n' + previous_generation + '\n```' if previous_generation else ''}\n"
        f"{'Fix the Previous Error where I am validating syntax with iVerlog: ',extra_notes or ''}\n"
        "Emit the finalized SystemVerilog module now.\n"
        "DO NOT send me same code again if I ask you to fix errors even if It's a direct match from Code library.\n"
        "- MUST REUSE the module name and port names as specified on the submodule to make the next module in the hierarchy.\n"
        "- We'll put all the submodule in a single file later. So, just reuse the previous submodule's name without any worries.\n"
    ).strip()

    print(f"[LLM Prompt] Generating module '{module_name}' via LLM...")
    print(f"[LLM System Prompt] {system_msg}")
    print("--------------------------------------------------")
    print(f"[LLM User Prompt] {user_msg}")
    print("--------------------------------------------------")

    url = f"{OPENAI_BASE_URL}/chat/completions"
    headers = {"Authorization": f"Bearer {OPENAI_API_KEY}", "Content-Type": "application/json"}
    payload = {
        "model": OPENAI_MODEL,
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user",   "content": user_msg},
        ],
        "temperature": temperature,
        "max_tokens": 2500,
    }

    last_err = None
    for attempt in range(1, max_retries + 1):
        try:
            resp = requests.post(url, headers=headers, json=payload, timeout=timeout_secs)
            resp.raise_for_status()
            content = resp.json()["choices"][0]["message"]["content"]
            code = _extract_code_block(content)
            return code
        except Exception as e:
            last_err = e
            time.sleep(1.2 * attempt)
    raise RuntimeError(f"module_generator_llm failed after {max_retries} retries: {last_err}")
