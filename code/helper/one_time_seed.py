# ---------- Import VerilogEval V1 JSONL into the Code Library (Qdrant) ----------
# Assumes you already defined:
#   - upsert_code_block(module_name, description, interface_sig, code_text, weight=0.5, tags=None)
#   - get_embedding(), ensure_collection(), etc. (from the retriever setup we added)

import json, re
from pathlib import Path
from typing import List, Tuple
from code_retriever import upsert_code_block, ensure_collection, QDRANT_COLLECTION
import logging

# Simple SV header parser (reuses the idea from runtime parser)
_HDR_RE = re.compile(
    r'(?is)^\s*module\s+(?P<name>[A-Za-z_]\w*)\s*'
    r'(?:#\s*\((?P<params>.*?)\))?\s*'
    r'\((?P<ports>.*?)\)\s*;'
)

def _parse_prompt_header(prompt_sv: str) -> Tuple[str, List[str]]:
    """
    Extract (module_name, port_names[]) from the 'prompt' header.
    Types/widths are ignored; we only need names for the signature.
    """
    m = _HDR_RE.search(prompt_sv)
    if not m:
        return ("", [])
    mod = m.group("name")
    ports_raw = m.group("ports")
    ports: List[str] = []
    for chunk in ports_raw.split(","):
        token = re.sub(r'//.*', '', chunk)
        token = re.sub(r'/\*.*?\*/', '', token, flags=re.S)
        token = token.strip()
        if not token:
            continue
        token = re.sub(r'\b(input|output|inout|logic|wire|reg|signed|unsigned)\b', '', token)
        token = re.sub(r'\[[^\]]*\]', '', token)  # strip widths
        name = token.split()[-1] if token.split() else ""
        name = re.sub(r'[^A-Za-z0-9_$]', '', name)
        if name:
            ports.append(name)
    return (mod, ports)

def import_verilogEval_jsonl(jsonl_path: Path, *, default_weight: float = 0.5) -> int:
    """
    Read the verilogEval human-eval JSONL and ingest entries into Qdrant.
    Each line must have: task_id, prompt (SV header), canonical_solution (SV module).
    Returns the count of inserted/updated entries.
    """
    count = 0
    ensure_collection()
    with open(jsonl_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            task_id = rec.get("task_id", "unknown")
            prompt_sv = rec.get("prompt", "")
            code_sv = rec.get("canonical_solution", "")
            if not prompt_sv or not code_sv:
                continue

            mod_name, ports = _parse_prompt_header(prompt_sv)
            # Many tasks use "top_module" — make a unique library key but keep the literal module name in the code
            unique_name = f"{task_id}__{mod_name or 'module'}"
            description = f"verilogEval::{task_id} — seed entry for retrieval; prompt-derived module '{mod_name or 'module'}'."

            # Upsert into Qdrant (embedding built from module name + description + ports)
            upsert_code_block(
                module_name=unique_name,
                description=description,
                interface_sig=ports,
                code_text=code_sv,
                weight=default_weight,
                tags=["verilogEval", task_id],
            )
            count += 1
    if "logging" in globals():
        logging.info("Imported %d verilogEval entries into Qdrant collection '%s'", count, QDRANT_COLLECTION)
    return count


# point to your downloaded JSONL
verilogEval_path = Path("/Users/sazzadsowmik/Documents/Personal/dr_hao_zheng/HiVeGen/code/code_library/VerilogEval_Human.jsonl")
imported = import_verilogEval_jsonl(verilogEval_path, default_weight=0.5)
print("Imported:", imported)