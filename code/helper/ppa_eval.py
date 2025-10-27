import math, json
from pathlib import Path
from typing import Dict, Any, Optional

def ceil_div(a: float, b: float) -> int:
    return int(math.ceil(a / b))

def bits_of(prec: str) -> int:
    # supports "int8","int16","fp16" etc.
    import re
    m = re.search(r'(\d+)', prec)
    return int(m.group(1)) if m else 16

def evaluate_ppa_from_config(
    assembled_sv_path: Path,
    config_path: Path,
    *,
    ppa_goal_override: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """
    Heuristic PPA evaluator guided by your configuration JSON.
    - Estimates DSPs, LUTs, BRAMs, bandwidth, and achievable frequency.
    - Checks against budgets + PPA goals.
    """
    cfg = json.loads(Path(config_path).read_text())

    knobs        = cfg.get("knobs", {})
    tech         = cfg.get("tech_profile", {})
    constraints  = cfg.get("constraints", {})
    ppa_goal_in  = cfg.get("ppa_goal", {})
    ppa_goal     = {**ppa_goal_in, **(ppa_goal_override or {})}

    rows = int(knobs.get("rows", 4))
    cols = int(knobs.get("cols", 4))
    pe_pipeline_depth = int(knobs.get("pe_pipeline_depth", 1))
    a_lb = int(knobs.get("a_linebuf_depth", 64))
    b_lb = int(knobs.get("b_linebuf_depth", 64))
    c_acc = int(knobs.get("c_accum_depth", 2))
    stationarity = str(knobs.get("stationarity", "output")).lower()
    bitwidth = str(knobs.get("bitwidth", cfg.get("params", {}).get("precision", "int16")))
    bw_bits = bits_of(bitwidth)

    dsp_per_mul = tech.get("dsp_per_mul", {}).get(bitwidth, 1.0)
    adder_cost  = tech.get("adder_cost_lut", {}).get(bitwidth, 64)
    bram_word_w = int(tech.get("bram_word_width", 32))

    dsp_budget  = constraints.get("dsp_budget", None)
    bram_budget = constraints.get("bram_budget", None)
    lut_budget  = constraints.get("lut_budget", None)
    ff_budget   = constraints.get("ff_budget", None)
    mem_bw_cap  = float(constraints.get("mem_bw_gbps_max", 12.8))
    fmax_cap    = float(constraints.get("clock_mhz_max", 300))

    freq_goal   = float(ppa_goal.get("freq_mhz", 200))
    optimize_for= list(ppa_goal.get("optimize_for", ["latency"]))

    # -------------------------
    # 1) Array scale / PE math
    # -------------------------
    pes = rows * cols
    # Mult count per PE per cycle (GEMM MAC): 1 multiply per PE per cycle
    mults_per_cycle = pes
    adds_per_cycle  = pes  # accumulators (one add per PE per cycle)
    # DSP/LUT usage (coarse)
    est_dsps = mults_per_cycle * dsp_per_mul
    est_luts = adds_per_cycle * adder_cost \
             + pes * 20  # control & misc overhead

    # -------------------------
    # 2) On-chip memory (BRAM)
    # -------------------------
    # Line buffers for A (rows) and B (cols). Each entry is one element of 'bitwidth'.
    words_A = rows * a_lb
    words_B = cols * b_lb
    # C accumulation storage (simplified): one accumulation register/entry per PE * depth.
    words_C = pes * c_acc

    # Translate words → BRAM blocks based on BRAM word width
    # (pack elements into BRAM words)
    elems_per_bram_word = max(1, bram_word_w // bw_bits)
    bram_words_A = ceil_div(words_A, elems_per_bram_word)
    bram_words_B = ceil_div(words_B, elems_per_bram_word)
    bram_words_C = ceil_div(words_C, elems_per_bram_word)

    # Assume 1 BRAM block per 1024 "words" (this scalar is technology dependent; tune as needed)
    BRAM_BLOCK_WORDS = 1024
    est_brams = ceil_div(bram_words_A, BRAM_BLOCK_WORDS) \
              + ceil_div(bram_words_B, BRAM_BLOCK_WORDS) \
              + ceil_div(bram_words_C, BRAM_BLOCK_WORDS)

    # -------------------------
    # 3) External memory bandwidth
    # -------------------------
    # Bytes/cycle to feed A and B (GEMM):
    #   - output-stationary tends to read A row-streams and B col-streams
    # Simplified bytes per cycle:
    bytes_per_elem = bw_bits / 8.0
    if stationarity == "output":
        bytes_per_cycle = rows * bytes_per_elem + cols * bytes_per_elem
    elif stationarity == "weight":  # weight-stationary → stream A heavily
        bytes_per_cycle = rows * cols * 0.25 * bytes_per_elem + rows * bytes_per_elem
    else:  # input-stationary etc.
        bytes_per_cycle = rows * bytes_per_elem + cols * bytes_per_elem

    # Achievable frequency estimate before caps/penalties (MHz)
    # Base frequency decreases with array size due to routing:
    base_freq = 600.0 / max(1.0, math.sqrt(pes))  # empirical shape
    # Pipeline helps frequency a bit:
    base_freq *= (1.0 + 0.06 * max(0, pe_pipeline_depth - 1))
    # Cap by tech limit:
    est_fmax_raw = min(base_freq, fmax_cap)

    # Bandwidth-limited frequency (GB/s = bytes/cycle * MHz / 1000)
    # Ensure we don’t exceed mem_bw_cap
    if bytes_per_cycle > 0:
        bw_limited_fmax = (mem_bw_cap * 1000.0) / bytes_per_cycle
    else:
        bw_limited_fmax = est_fmax_raw

    # Final achievable freq is the minimum of raw/capped and bandwidth-limited
    est_freq_mhz = min(est_fmax_raw, bw_limited_fmax)

    # -------------------------
    # 4) Power (very rough proxy)
    # -------------------------
    # Dynamic power ~ switching activity ~ mults + adds scaled by freq
    est_power_w = 0.0005 * (mults_per_cycle + adds_per_cycle) * (est_freq_mhz / 200.0)

    # -------------------------
    # 5) Budget checks
    # -------------------------
    meets = True
    reasons = []

    if dsp_budget is not None and est_dsps > dsp_budget:
        meets = False; reasons.append(f"DSP over budget: {est_dsps:.1f} > {dsp_budget}")
    if bram_budget is not None and est_brams > bram_budget:
        meets = False; reasons.append(f"BRAM over budget: {est_brams} > {bram_budget}")
    if lut_budget is not None and est_luts > lut_budget:
        meets = False; reasons.append(f"LUT over budget: {est_luts} > {lut_budget}")
    # freq goal
    if est_freq_mhz < freq_goal:
        meets = False; reasons.append(f"Freq shortfall: {est_freq_mhz:.1f} < {freq_goal}")

    # If optimizing for area, also gate on a coarse “area” proxy (LUT + DSP*200 + BRAM*500)
    if "area" in [s.lower() for s in optimize_for]:
        est_area_eq = est_luts + est_dsps * 200 + est_brams * 500
        # If area budget is present, use it; otherwise compare to a loose bound
        area_ok = True
        if lut_budget is not None and dsp_budget is not None and bram_budget is not None:
            bound = lut_budget + dsp_budget * 200 + bram_budget * 500
            area_ok = est_area_eq <= bound
        if not area_ok:
            meets = False; reasons.append("Composite area proxy beyond implied bound")

    return {
        "array": {"rows": rows, "cols": cols, "pes": pes},
        "precision_bits": bw_bits,
        "resources": {
            "est_dsps": float(est_dsps),
            "est_luts": int(est_luts),
            "est_brams": int(est_brams),
        },
        "performance": {
            "est_freq_mhz": float(est_freq_mhz),
            "mem_bw_gbps_cap": float(mem_bw_cap),
            "bytes_per_cycle": float(bytes_per_cycle),
        },
        "power": {
            "est_power_w": float(est_power_w),
        },
        "goals": {
            "freq_goal_mhz": float(freq_goal),
            "optimize_for": optimize_for,
            "budgets": {
                "dsp_budget": dsp_budget,
                "bram_budget": bram_budget,
                "lut_budget": lut_budget,
                "ff_budget": ff_budget,
            },
        },
        "meets_goal": meets,
        "violations": reasons,
    }
