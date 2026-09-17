"""Emits spec/fixtures/scoring_golden.json from the spec's reference scorer.

Every case is a scorer input in the spec 11 section 12 shape plus the expected
outputs for both P0 models, taken verbatim from the reference's case tables,
which reproduce 08 section 8 and examples/watchers section 7.
Regenerate with: python3 spec/fixtures/gen_scoring_golden.py spec/fixtures/scoring_golden.json
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "..", "..", "docs", "epistemic-ledger-poc-spec-v4", "epistemic-ledger-poc", "reference")
sys.path.insert(0, REF)
import reference_scorer as R  # noqa: E402

OUT = sys.argv[1]
MODELS = {"default": "ledger-default@0.1.0", "strict": "ledger-strict@0.1.0"}
# Links whose contribution had not yet been audited CONFIRMED at the checkpoint.
UNCONFIRMED = {"public-demo": {"S2": ["L10"]}, "watchers": {"S1": ["L2"], "S2": ["L5"]}}
CHECK_TASKS = {"opposing_search_done": ("opposing_search_done", "T-opposing"),
               "independence_check": ("independence_reviewed", "T-independence"),
               "qualifiers_reviewed": ("qualifiers_reviewed", "T-qualifier")}
CONTESTED = {("public-demo", "S2", "C4")}


def expected(tup, contested, provisional):
    state, p, stab, cov, sg, cg, unrev, reason = tup
    return {"assessment_state": state, "probability": p, "stability": stab, "review_coverage": cov,
            "support_groups": sg, "contradict_groups": cg, "independence_unreviewed": unrev,
            "not_applicable_reason": reason, "contested": contested, "provisional": provisional}


def build(suite, cases, sources, ev_at, links):
    out = []
    for chk, handle, claim, lids, ev_state, checks, exp, strict_exp in cases:
        evidence = ev_at(ev_state)
        unconfirmed = UNCONFIRMED.get(suite, {}).get(chk, [])
        in_links = []
        for lid in lids:
            L = links[lid]
            E = evidence[L["evidence"]]
            in_links.append({
                "id": "L%02d" % L["id"], "handle": lid, "evidence_id": L["evidence"], "direction": L["dir"],
                "relevance_strength": L["rel"], "interpretive_steps": L.get("steps", 0),
                "audit_confirmed": lid not in unconfirmed,
                "evidence": {"observation_type": E["obs"], "independence_group_id": E.get("group"),
                             "source_type": sources[E["source"]],
                             "assessment": {"authenticity": "UNVERIFIED", "extraction": "UNVERIFIED"}},
            })
        task_checks = [{"check": CHECK_TASKS[c][0], "by": CHECK_TASKS[c][1]} for c in sorted(checks)]
        contested = (suite, chk, handle) in CONTESTED
        provisional = any(not l["audit_confirmed"] for l in in_links)
        strict = strict_exp or exp
        out.append({
            "suite": suite, "checkpoint": chk, "claim_handle": handle,
            "input": {"claim": {"id": handle, "type": claim["type"], "truth_evaluable": claim["truth_evaluable"],
                                "not_evaluable_reason": claim["reason"]},
                      "snapshot_seq": 0, "links": in_links, "task_checks": task_checks},
            "expected": {MODELS["default"]: expected(exp, contested, provisional),
                         MODELS["strict"]: expected(strict, contested if strict[0] != "NOT_APPLICABLE" else False,
                                                    provisional)},
        })
    return out


cases = build("public-demo", R.PUB_CASES, R.PUB_SOURCES, R.pub_ev, R.PL) + build("watchers", R.W_CASES, R.W_SOURCES, R.w_ev, R.WL)
doc = {"_about": "Golden scoring cases for both P0 models, generated from the spec's reference scorer "
                 "(08 section 8 and examples/watchers section 7). Inputs follow spec 11 section 12.",
       "models": MODELS, "cases": cases}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
print("golden cases:", len(cases))
