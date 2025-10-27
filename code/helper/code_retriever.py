# ---------- Weight-Based Retrieving Engine (Step 1: RAG setup w/ OpenAI + Qdrant) ----------
# deps: pip install qdrant-client requests xxhash
import os, time, json, hashlib, datetime as dt
import requests
from pathlib import Path
from typing import List, Dict, Any, Tuple, Optional
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct, Filter, FieldCondition, MatchValue
import xxhash
import uuid
import logging
import re
from dotenv import load_dotenv
load_dotenv()

# ---- Config (env-driven) ----
OPENAI_API_KEY   = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL     = os.getenv("OPENAI_MODEL", "gpt-5-chat-latest")
EMB_MODEL        = os.getenv("OPENAI_EMB_MODEL", "text-embedding-3-small")  # 1536 dims
EMB_BASE_URL     = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")
OPENAI_BASE_URL  = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")
QDRANT_URL       = os.getenv("QDRANT_URL", "http://localhost:6333")
QDRANT_API_KEY   = os.getenv("QDRANT_API_KEY")  # optional if local
QDRANT_COLLECTION = os.getenv("QDRANT_COLLECTION", "hivegen_code_lib")
EMB_DIMS = int(os.getenv("OPENAI_EMB_DIMS", "1536"))  # 1536 for -small, 3072 for -large

# ---- Helpers ----
def _now_iso() -> str:
    return dt.datetime.utcnow().isoformat() + "Z"

def _sha1(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8")).hexdigest()

def _fast_hash(s: str) -> str:
    return xxhash.xxh64(s).hexdigest()

def get_embedding(text: str) -> List[float]:
    if not OPENAI_API_KEY:
        raise RuntimeError("Missing OPENAI_API_KEY")
    url = f"{EMB_BASE_URL.rstrip('/')}/embeddings"
    headers = {"Authorization": f"Bearer {OPENAI_API_KEY}", "Content-Type": "application/json"}
    payload = {"model": EMB_MODEL, "input": text}
    for attempt in range(1, 4):
        resp = requests.post(url, headers=headers, json=payload, timeout=60)
        try:
            resp.raise_for_status()
            return resp.json()["data"][0]["embedding"]
        except Exception as e:
            if attempt == 3: raise
            time.sleep(1.2 * attempt)

def qdrant() -> QdrantClient:
    return QdrantClient(url=QDRANT_URL, api_key=QDRANT_API_KEY)

def ensure_collection():
    client = qdrant()
    exists = False
    try:
        client.get_collection(QDRANT_COLLECTION)
        exists = True
    except Exception:
        exists = False
    if not exists:
        client.recreate_collection(
            collection_name=QDRANT_COLLECTION,
            vectors_config=VectorParams(size=EMB_DIMS, distance=Distance.COSINE),
        )

# ---- Library: upsert / search ----
def build_module_query_token(name: str, description: str, interface_sig: List[str]) -> str:
    # compact, stable text for embedding similarity
    sig = ", ".join(interface_sig) if interface_sig else ""
    return f"module: {name}\ndesc: {description}\nports: {sig}"

def upsert_code_block(
    module_name: str,
    description: str,
    interface_sig: List[str],
    code_text: str,
    weight: float = 0.5,
    tags: Optional[List[str]] = None,
) -> str:
    ensure_collection()
    client = qdrant()
    token = build_module_query_token(module_name, description, interface_sig)
    vec = get_embedding(token)
    h = _sha1(code_text)
    # point_id must be UUID or int — use uuid5 for deterministic ID
    point_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, module_name + ":" + h))

    payload = {
        "module_name": module_name,
        "description": description,
        "interface_sig": interface_sig,
        "code_text": code_text,
        "weight": float(weight),
        "added_at": _now_iso(),
        "last_used": None,
        "success_count": 0,
        "fail_count": 0,
        "content_hash": h,
        "tags": tags or [],
    }
    client.upsert(
        collection_name=QDRANT_COLLECTION,
        points=[PointStruct(id=point_id, vector=vec, payload=payload)],
        wait=True,
    )
    return point_id

def search_candidates(
    module_name: str,
    description: str,
    interface_sig: List[str],
    top_k: int = 5,
    min_cosine: float = 0.30,
) -> List[Dict[str, Any]]:
    """Return top-k by (cosine * weight), including raw cosine and payload."""
    ensure_collection()
    client = qdrant()
    query = build_module_query_token(module_name, description, interface_sig)
    q_vec = get_embedding(query)

    results = client.search(
        collection_name=QDRANT_COLLECTION,
        query_vector=q_vec,
        limit=max(20, top_k * 3),  # broaden first, we'll re-rank with weight
        with_payload=True,
        score_threshold=min_cosine,  # cosine threshold
    )
    ranked = []
    for r in results:
        pl = r.payload or {}
        w = float(pl.get("weight", 0.5))
        ranked.append({
            "point_id": r.id,
            "cosine": float(r.score),
            "weight": w,
            "score": float(r.score) * w,
            "payload": pl,
        })
    ranked.sort(key=lambda x: x["score"], reverse=True)
    return ranked[:top_k]

# ---- Weight updates (paper-style) ----
def update_weight(point_id: str, *, success: bool, second_chance_given: bool = False) -> None:
    """
    W *= 1.06 on success; W *= 0.9 on fail.
    If fail and W < 0.3 and not second_chance_given -> reset to 0.5 once.
    If W < 0.2 -> mark for GC (set 'gc': true).
    """
    client = qdrant()
    pts = client.retrieve(QDRANT_COLLECTION, ids=[point_id], with_payload=True)
    if not pts: return
    pl = pts[0].payload or {}
    w = float(pl.get("weight", 0.5))
    succ = int(pl.get("success_count", 0))
    fail = int(pl.get("fail_count", 0))

    if success:
        w *= 1.06
        succ += 1
    else:
        if w < 0.3 and not second_chance_given:
            w = 0.5
            pl["second_chance_given"] = True
        else:
            w *= 0.9
            fail += 1

    gc = bool(pl.get("gc", False))
    if w < 0.2:
        gc = True

    pl.update({
        "weight": float(w),
        "success_count": succ,
        "fail_count": fail,
        "last_used": _now_iso(),
        "gc": gc,
    })
    client.set_payload(QDRANT_COLLECTION, payload=pl, points=[point_id])

# ---- Convenience: retrieve-or-generate decision ----
def retrieve_or_llm_generate(
    module_name: str,
    description: str,
    interface_sig: List[str],
    *,
    score_threshold: float = 0.35,
    top_k: int = 5,
) -> Tuple[str, Dict[str, Any], bool]:
    """
    Returns (code_text, meta, from_library)
      - If best (cosine*weight) >= threshold -> return library code
      - Else -> signal caller to LLM-generate; caller should upsert & return that
    """
    cands = search_candidates(module_name, description, interface_sig, top_k=top_k, min_cosine=0.15)
    if not cands:
        return "", {"reason": "no_candidates"}, False
    best = cands[0]
    if best["score"] >= score_threshold:
        code = best["payload"]["code_text"]
        update_weight(best["point_id"], success=True)  # optimistic; caller may override after validation
        return code, {"source": "library", "point_id": best["point_id"], "cosine": best["cosine"], "weight": best["weight"], "tags": best["payload"].get("tags")}, True
    return "", {"reason": f"below_threshold({best['score']:.3f}<{score_threshold})"}, False

# ---- Example: wiring into our pipeline AFTER Task Manager ----
def use_retriever_for_module(
    module_name: str,
    description: str,
    interface_sig: List[str],
    *,
    fallback_llm_func,   # callable(name, desc, ports)-> code_text
) -> str:
    """
    Try library; if miss, call LLM to generate, then upsert to library.
    Returns code_text.
    """
    code, meta, hit = retrieve_or_llm_generate(module_name, description, interface_sig)
    if hit:
        if "logging" in globals(): logging.info("Retriever hit: %s (cos=%.3f, w=%.3f)", module_name, meta.get("cosine",0.0), meta.get("weight",0.0))
        return code

    # Fallback to LLM generator provided by caller
    code = (module_name, description, interface_sig)
    # Upsert new code with initial weight
    upsert_code_block(module_name, description, interface_sig, code_text=code, weight=0.5)
    if "logging" in globals(): logging.info("Retriever miss -> LLM generated & inserted: %s", module_name)
    return code


def reinforce_after_validation(meta: dict, success: bool) -> None:
    pid = meta.get("point_id")
    if not pid:
        print("[Reinforce] No point_id in meta; skip.")
        return
    update_weight(pid, success=success)
    print(f"[Reinforce] Updated weight for {pid}: success={success}")


def _extract_code_block(content: str) -> str:
    """Return first ```...``` block or raw text if none."""
    m = re.search(r"```(?:verilog|systemverilog)?\s*([\s\S]*?)```", content)
    return m.group(1).strip() if m else content.strip()

def fallback_llm_func(module_name: str, description: str, interface_sig: list[str]) -> str:
    """Generate a new Verilog module if retriever misses."""
    if not OPENAI_API_KEY:
        raise RuntimeError("Missing OPENAI_API_KEY in environment.")
    prompt = (
        f"Generate synthesizable SystemVerilog code for module '{module_name}'.\n"
        f"Description: {description}\n"
        f"Ports: {', '.join(interface_sig)}\n"
        f"Include module header and endmodule.\n"
        f"Do not add testbench or commentary."
    )

    print(f"[LLM Prompt] Generating module '{prompt}' via LLM...")

    url = f"{OPENAI_BASE_URL}/chat/completions"
    headers = {
        "Authorization": f"Bearer {OPENAI_API_KEY}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": OPENAI_MODEL,
        "messages": [
            {"role": "system", "content": "Return valid Verilog code only inside triple backticks."},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.2,
        "max_tokens": 1500,
    }

    for attempt in range(1, 4):
        try:
            resp = requests.post(url, headers=headers, json=payload, timeout=60)
            resp.raise_for_status()
            msg = resp.json()["choices"][0]["message"]["content"]
            code = _extract_code_block(msg)
            return code
        except Exception as e:
            if attempt == 3:
                raise
            time.sleep(1.5 * attempt)