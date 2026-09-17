#!/usr/bin/env python3
"""Reference implementation of ledger-default@0.1.0 and ledger-strict@0.1.0
(spec 03 §4, §8, §9, §13). Not production code: an independent cross-check that
reproduces the golden values in 08 §8 (public demo) and
examples/watchers/README.md §7 (stress test). Run: python3 reference_scorer.py
"""
import json, math, os
from decimal import Decimal, ROUND_HALF_EVEN

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = {
    "default": json.load(open(os.path.join(HERE, "..", "scoring-config-v0.1.json"))),
    "strict": json.load(open(os.path.join(HERE, "..", "scoring-config-strict-v0.1.json"))),
}

def q(x, places):
    return Decimal(x).quantize(Decimal(1).scaleb(-places), rounding=ROUND_HALF_EVEN)

def sigmoid4(x):
    return q(1 / (1 + math.exp(-float(x))), 4)

def score(claim, links, evidence, sources, checks, model="default"):
    """claim: {type, truth_evaluable, reason}; links: links counted at S;
    checks: task-based checklist items satisfied at S."""
    CFG = MODELS[model]
    counted_ev = [evidence[l["evidence"]] for l in links]

    primary = any(sources[e["source"]] in CFG["primary_source_types"] for e in counted_ev)
    indep = (len(counted_ev) > 0 and all(e.get("group") for e in counted_ev)) or "independence_check" in checks
    items = {
        "primary_source_reviewed": primary,
        "opposing_search_done": "opposing_search_done" in checks,
        "independence_reviewed": indep,
        "qualifiers_reviewed": "qualifiers_reviewed" in checks,
    }
    declared = CFG["review_checklist"]
    cov = q(Decimal(sum(items[k] for k in declared)) / len(declared), 2)
    unrev = sum(1 for e in counted_ev if not e.get("group"))
    base = dict(review_coverage=str(cov), independence_unreviewed=unrev)
    na = lambda reason: dict(base, state="NOT_APPLICABLE", p=None, stability=None, sg=0, cg=0, reason=reason)

    # Step 0
    if not claim["truth_evaluable"]:
        return na(claim["reason"])
    if claim["type"] not in CFG["scored_types"]:
        return na("NOT_SCORED_BY_MODEL")

    # Step 2
    pen = Decimal(CFG["interpretive_step_penalty"])
    weighted = []
    for l in sorted(links, key=lambda l: l["id"]):
        e = evidence[l["evidence"]]
        mag = (Decimal(CFG["relevance_weight"][l["rel"]])
               * Decimal(CFG["observation_weight"][e["obs"]])
               * max(Decimal(0), 1 - pen * l.get("steps", 0)))
        weighted.append((l, q(mag, 6), CFG["direction_sign"][l["dir"]],
                         e.get("group") or "solo:" + l["evidence"]))

    # Step 3: strongest-only per (group, sign); ties -> lowest evidence id, then link id
    kept = {}
    for l, mag, sign, g in weighted:
        if sign == 0:
            continue
        k = (g, sign)
        cur = kept.get(k)
        if cur is None or mag > cur[1] or (mag == cur[1] and (l["evidence"], l["id"]) < (cur[0]["evidence"], cur[0]["id"])):
            kept[k] = (l, mag, sign)
    kept_list = sorted(kept.values(), key=lambda t: t[0]["id"])
    if not kept_list or all(m == 0 for _, m, _ in kept_list):
        return dict(base, state="INSUFFICIENT_EVIDENCE", p=None, stability=None, sg=0, cg=0, reason=None)
    sg = sum(1 for (_, s), (_, m, _) in kept.items() if s > 0 and m > 0)
    cg = sum(1 for (_, s), (_, m, _) in kept.items() if s < 0 and m > 0)

    # Step 4
    p0 = Decimal(CFG["prior"][claim["type"]])
    prior_lo = q(math.log(p0 / (1 - p0)), 6)
    esum = q(sum(s * m for _, m, s in kept_list), 6)
    p = sigmoid4(prior_lo + esum)

    # Step 5 (v4: directional states require matching evidence)
    t = CFG["state_thresholds"]
    if p >= Decimal(t["SUPPORTED"]) and sg: state = "SUPPORTED"
    elif p >= Decimal(t["LEANS_SUPPORTED"]) and sg: state = "LEANS_SUPPORTED"
    elif p <= Decimal(t["LEANS_CONTRADICTED_ABOVE"]) and cg: state = "CONTRADICTED"
    elif p <= Decimal(t["UNRESOLVED_ABOVE"]) and cg: state = "LEANS_CONTRADICTED"
    else: state = "UNRESOLVED"

    # §9 stability
    st = CFG["stability"]
    ps = [p] + [sigmoid4(prior_lo + esum * Decimal(v)) for v in st["variants"].values()]
    spread = max(ps) - min(ps)
    stab = "HIGH" if spread <= Decimal(st["spread_high_max"]) else "MEDIUM" if spread <= Decimal(st["spread_medium_max"]) else "LOW"
    if sg + cg < st["min_groups_for_high"] and stab == "HIGH":
        stab = "MEDIUM"
    if claim["type"] in CFG["model_dependent_types"]:
        stab = st["model_dependent_cap"]
    return dict(base, state=state, p=str(p), stability=stab, sg=sg, cg=cg, reason=None)


def claim(t, reason=None):
    ev = t not in ("NORMATIVE",)
    return {"type": t, "truth_evaluable": ev, "reason": None if ev else (reason or "NORMATIVE_OR_VALUE")}

def run(title, cases, sources, evidence_at, links):
    bad = 0
    print(f"== {title}")
    for model in ("default", "strict"):
        for chk, name, c, lids, ev_state, checks, exp, strict_exp in cases:
            e = strict_exp if (model == "strict" and strict_exp) else exp
            r = score(c, [links[i] for i in lids], evidence_at(ev_state), sources, checks, model)
            got = (r["state"], r["p"], r["stability"], r["review_coverage"], r["sg"], r["cg"], r["independence_unreviewed"], r["reason"])
            ok = got == e
            bad += not ok
            print(f"{'PASS' if ok else 'FAIL'} {model:7} {chk} {name} {got}" + ("" if ok else f"\n     expected {e}"))
    return bad

# ---------------- Public demo (08): the statistic that traces to one survey ----------------
PUB_SOURCES = {"SR": "DATASET", "SP": "PRIMARY_TEXT", "SN1": "SECONDARY_TEXT", "SN2": "SECONDARY_TEXT",
               "SN3": "SECONDARY_TEXT", "SX": "WEBSITE"}
def pub_ev(state):
    g = "G1" if state >= 4 else None
    return {
        "E1": {"source": "SR", "obs": "DATASET_RESULT", "group": "G1"},
        "E2": {"source": "SP", "obs": "DIRECT_TEXT", "group": "G1"},
        "E3": {"source": "SN1", "obs": "DIRECT_TEXT", "group": g},
        "E4": {"source": "SN2", "obs": "DIRECT_TEXT", "group": g},
        "E5": {"source": "SN3", "obs": "DIRECT_TEXT", "group": g},
        "E6": {"source": "SR", "obs": "DATASET_RESULT", "group": "G1"},
        "E7": {"source": "SX", "obs": "DIRECT_TEXT", "group": "G2"},
    }
PL = {
    "L1":  {"id": 1,  "evidence": "E2", "dir": "SUPPORT", "rel": "DIRECT"},                 # C1
    "L2":  {"id": 2,  "evidence": "E1", "dir": "SUPPORT", "rel": "DIRECT"},                 # C3
    "L3":  {"id": 3,  "evidence": "E1", "dir": "SUPPORT", "rel": "STRONG",   "steps": 1},   # C2
    "L4":  {"id": 4,  "evidence": "E2", "dir": "SUPPORT", "rel": "MODERATE", "steps": 1},   # C2
    "L5":  {"id": 5,  "evidence": "E3", "dir": "SUPPORT", "rel": "MODERATE", "steps": 1},   # C2
    "L6":  {"id": 6,  "evidence": "E4", "dir": "SUPPORT", "rel": "MODERATE", "steps": 1},   # C2
    "L7":  {"id": 7,  "evidence": "E5", "dir": "SUPPORT", "rel": "MODERATE", "steps": 1},   # C2
    "L8":  {"id": 8,  "evidence": "E7", "dir": "CONTRADICT", "rel": "MODERATE"},            # C4
    "L9":  {"id": 9,  "evidence": "E1", "dir": "SUPPORT", "rel": "WEAK",     "steps": 2},   # C6
    "L10": {"id": 10, "evidence": "E2", "dir": "SUPPORT", "rel": "DIRECT"},                 # C4 (poisoned)
    # S5 supersessions of L3..L7 after the qualifier check
    "L11": {"id": 11, "evidence": "E1", "dir": "SUPPORT", "rel": "WEAK", "steps": 3},
    "L12": {"id": 12, "evidence": "E2", "dir": "SUPPORT", "rel": "WEAK", "steps": 3},
    "L13": {"id": 13, "evidence": "E3", "dir": "SUPPORT", "rel": "WEAK", "steps": 3},
    "L14": {"id": 14, "evidence": "E4", "dir": "SUPPORT", "rel": "WEAK", "steps": 3},
    "L15": {"id": 15, "evidence": "E5", "dir": "SUPPORT", "rel": "WEAK", "steps": 3},
    "L16": {"id": 16, "evidence": "E6", "dir": "QUALIFY", "rel": "DIRECT"},
}
C2_LINKS_EARLY = ["L3", "L4", "L5", "L6", "L7"]
C2_LINKS_LATE = ["L11", "L12", "L13", "L14", "L15", "L16"]
SEARCHED = {"opposing_search_done"}
PUB_CASES = [
    # chk, claim, type, links, evidence-state, checks, expected default, expected strict (None = same)
    ("S1", "C1", claim("TEXTUAL"), ["L1"], 1, set(),
     ("SUPPORTED", "0.8581", "MEDIUM", "0.50", 1, 0, 0, None), None),
    ("S1", "C2", claim("QUANTITATIVE"), C2_LINKS_EARLY, 1, set(),
     ("SUPPORTED", "0.9085", "MEDIUM", "0.25", 4, 0, 3, None), None),
    ("S1", "C3", claim("QUANTITATIVE"), ["L2"], 1, set(),
     ("SUPPORTED", "0.8581", "MEDIUM", "0.50", 1, 0, 0, None), None),
    ("S1", "C4", claim("TEXTUAL"), ["L8"], 1, SEARCHED,
     ("LEANS_CONTRADICTED", "0.3682", "MEDIUM", "0.50", 0, 1, 0, None), None),
    ("S1", "C5", claim("NORMATIVE"), [], 1, set(),
     ("NOT_APPLICABLE", None, None, "0.00", 0, 0, 0, "NORMATIVE_OR_VALUE"), None),
    ("S1", "C6", claim("CAUSAL"), ["L9"], 1, set(),
     ("UNRESOLVED", "0.3792", "LOW", "0.50", 1, 0, 0, None),
     ("NOT_APPLICABLE", None, None, "0.50", 0, 0, 0, "NOT_SCORED_BY_MODEL")),
    ("S2", "C4", claim("TEXTUAL"), ["L8", "L10"], 2, SEARCHED,
     ("LEANS_SUPPORTED", "0.7790", "MEDIUM", "0.75", 1, 1, 0, None), None),
    ("S3", "C4", claim("TEXTUAL"), ["L8"], 3, SEARCHED,
     ("LEANS_CONTRADICTED", "0.3682", "MEDIUM", "0.50", 0, 1, 0, None), None),
    ("S4", "C2", claim("QUANTITATIVE"), C2_LINKS_EARLY, 4, {"independence_check"},
     ("LEANS_SUPPORTED", "0.7146", "MEDIUM", "0.50", 1, 0, 0, None), None),
    ("S5", "C2", claim("QUANTITATIVE"), C2_LINKS_LATE, 5, {"independence_check", "qualifiers_reviewed"},
     ("UNRESOLVED", "0.5247", "MEDIUM", "0.75", 1, 0, 0, None), None),
    ("S5", "C3", claim("QUANTITATIVE"), ["L2"], 5, set(),
     ("SUPPORTED", "0.8581", "MEDIUM", "0.50", 1, 0, 0, None), None),
]

# ---------------- Stress test (examples/watchers) ----------------
W_SOURCES = {"SA": "PRIMARY_TEXT", "SB": "PRIMARY_TEXT", "SC": "SECONDARY_TEXT", "SD": "SECONDARY_TEXT"}
def w_ev(state):
    g = "G2" if state >= 5 else None
    return {"E1": {"source": "SA", "obs": "DIRECT_TEXT", "group": "G1"},
            "E2": {"source": "SD", "obs": "EXPERT_ANALYSIS", "group": None},
            "E3": {"source": "SA", "obs": "DIRECT_TEXT", "group": "G1"},
            "E4": {"source": "SB", "obs": "DIRECT_TEXT", "group": g},
            "E5": {"source": "SC", "obs": "DIRECT_TEXT", "group": g}}
WL = {
    "L1": {"id": 1, "evidence": "E1", "dir": "SUPPORT", "rel": "DIRECT"},
    "L2": {"id": 2, "evidence": "E1", "dir": "SUPPORT", "rel": "DIRECT"},
    "L3": {"id": 3, "evidence": "E2", "dir": "SUPPORT", "rel": "MODERATE", "steps": 1},
    "L4": {"id": 4, "evidence": "E3", "dir": "CONTRADICT", "rel": "MODERATE"},
    "L5": {"id": 5, "evidence": "E1", "dir": "SUPPORT", "rel": "DIRECT"},
    "L6": {"id": 6, "evidence": "E4", "dir": "SUPPORT", "rel": "STRONG"},
    "L7": {"id": 7, "evidence": "E5", "dir": "SUPPORT", "rel": "MODERATE"},
}
W_CASES = [
    ("S1", "C1", claim("TEXTUAL"), ["L1"], 1, set(), ("SUPPORTED", "0.8581", "MEDIUM", "0.50", 1, 0, 0, None), None),
    ("S1", "C2", claim("TEXTUAL"), ["L2"], 1, set(), ("SUPPORTED", "0.8581", "MEDIUM", "0.50", 1, 0, 0, None), None),
    ("S1", "C3", claim("INTERPRETIVE"), ["L3"], 1, set(), ("UNRESOLVED", "0.5382", "LOW", "0.00", 1, 0, 1, None),
     ("NOT_APPLICABLE", None, None, "0.00", 0, 0, 1, "NOT_SCORED_BY_MODEL")),
    ("S1", "C4", claim("TEXTUAL"), ["L4"], 1, SEARCHED, ("LEANS_CONTRADICTED", "0.3682", "MEDIUM", "0.75", 0, 1, 0, None), None),
    ("S1", "C6", claim("NORMATIVE"), [], 1, set(), ("NOT_APPLICABLE", None, None, "0.00", 0, 0, 0, "NORMATIVE_OR_VALUE"), None),
    ("S2", "C5", claim("TEXTUAL"), ["L5"], 2, set(), ("SUPPORTED", "0.8581", "MEDIUM", "0.50", 1, 0, 0, None), None),
    ("S3", "C5", claim("TEXTUAL"), [], 3, set(), ("INSUFFICIENT_EVIDENCE", None, None, "0.00", 0, 0, 0, None), None),
    ("S4", "C1", claim("TEXTUAL"), ["L1", "L6", "L7"], 4, set(), ("SUPPORTED", "0.9683", "HIGH", "0.25", 3, 0, 2, None), None),
    ("S5", "C1", claim("TEXTUAL"), ["L1", "L6", "L7"], 5, set(), ("SUPPORTED", "0.9468", "HIGH", "0.50", 2, 0, 0, None), None),
]

if __name__ == "__main__":
    bad = run("public demo (08)", PUB_CASES, PUB_SOURCES, pub_ev, PL)
    bad += run("watchers stress test", W_CASES, W_SOURCES, w_ev, WL)
    print("ALL PASS" if not bad else f"{bad} FAILURES")
    raise SystemExit(1 if bad else 0)
