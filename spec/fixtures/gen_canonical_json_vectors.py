"""Generates spec/fixtures/canonical_json_vectors.json independently of the Ruby code.

RFC 8785 expected strings are transcribed from the RFC. Project vectors contain no
floats and only ASCII keys, so Python's sorted compact dump equals JCS. Ed25519 vectors
are RFC 8032 section 7.1. Non-ASCII characters are built with chr() so this file is
pure ASCII.
"""
import json, hashlib, base64, sys

OUT = sys.argv[1]

def sha(s): return hashlib.sha256(s.encode("utf-8")).hexdigest()
def b64u(b): return base64.urlsafe_b64encode(b).decode().rstrip("=")
def jcs(o): return json.dumps(o, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

EURO, SI, DALET, GRIN, CTRL, ODIA = chr(0x20AC), chr(0x0F), chr(0xFB33), chr(0x1F600), chr(0x80), chr(0xF6)
BS, DQ, LF, CR = chr(0x5C), chr(0x22), chr(0x0A), chr(0x0D)

rfc = []
# RFC 8785 section 3.2.3 example. The input string is: euro $ U+000F LF A ' B " \ \ " /
inp = {"numbers": [333333333.33333329, 1E30, 4.50, 2e-3, 0.000000000000000000000000001],
       "string": EURO + "$" + SI + LF + "A'B" + DQ + BS + BS + DQ + "/",
       "literals": [None, True, False]}
exp = ('{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"'
       + EURO + "$" + BS + "u000f" + BS + "nA'B" + BS + DQ + BS + BS + BS + BS + BS + DQ + '/"}')
assert json.loads(exp) == inp, "RFC 8785 3.2.3 transcription"
rfc.append({"name": "RFC 8785 section 3.2.3: literals, numbers, string escapes",
            "input": inp, "expected": exp, "sha256": sha(exp)})

# RFC 8785 section 3.2.3 sorting example: keys ordered by UTF-16 code units.
inp = {EURO: "Euro Sign", CR: "Carriage Return", DALET: "Hebrew Letter Dalet With Dagesh", "1": "One",
       GRIN: "Emoji: Grinning Face", CTRL: "Control", ODIA: "Latin Small Letter O With Diaeresis"}
exp = ('{"' + BS + 'r":"Carriage Return","1":"One","' + CTRL + '":"Control","' + ODIA
       + '":"Latin Small Letter O With Diaeresis","' + EURO + '":"Euro Sign","' + GRIN
       + '":"Emoji: Grinning Face","' + DALET + '":"Hebrew Letter Dalet With Dagesh"}')
assert json.loads(exp) == inp, "RFC 8785 sorting transcription"
rfc.append({"name": "RFC 8785 section 3.2.3: property sorting by UTF-16 code units",
            "input": inp, "expected": exp, "sha256": sha(exp)})

U = "0192a3b4-c5d6-7e8f-9a0b-1c2d3e4f5a"
envelope = {
    "protocol": "eir-result-v1", "action_type": "TASK_RESULT", "task_id": U + "6b",
    "task_packet_hash": "sha256:" + "ab" * 32, "contributor_key_id": "ed25519:" + "cd" * 32,
    "delegation_id": U + "6c", "client_created_at": "2026-09-16T21:04:10Z",
    "software": {"agent_name": "example-agent", "version": "0.1.0", "model_provider": "stub",
                 "model_id": "none", "prompt_version": "verify-v1"},
    "payload": {"outcome": "CONFIRMED", "ops": [{
        "op": "LINK_EVIDENCE", "evidence_item_id": U + "6d", "claim_id": U + "6e", "direction": "SUPPORT",
        "relevance_strength": "DIRECT", "interpretive_steps": 0, "note": "Release states the same figure."}]},
    "payload_hash": "sha256:" + "ef" * 32,
}
packet = {
    "protocol": "eir-task-v1", "task_id": U + "6b", "task_type": "EVIDENCE_VERIFICATION", "domain": "general",
    "issued_at": "2026-09-16T21:00:00Z", "lease_expires_at": "2026-09-16T23:00:00Z", "snapshot_seq": 9,
    "target": {"claim_id": U + "6e", "claim_type": "TEXTUAL",
               "claim_text": "The Journal of Distributed Work Research (2025) reports that 62% of remote workers report higher productivity."},
    "objective": "Decide whether the excerpt directly supports the claim. Do not infer beyond the excerpt.",
    "context": {"source_id": U + "6f", "source_location_id": U + "70",
                "locator": {"type": "CHAR_RANGE", "start": 0, "end": 102},
                "untrusted_excerpt": "Acme press release: 62% of remote workers report higher productivity, according to Acme's 2026 survey.",
                "excerpt_hash": "sha256:" + "12" * 32, "known_qualifiers": {}},
    "constraints": {"allowed_ops": ["LINK_EVIDENCE", "CREATE_EVIDENCE"], "max_ops": 3, "require_exact_location": True},
    "return_schema": "eir-result-v1", "server_key_id": "ed25519:" + "34" * 32,
}
trace = {
    "claim": "C2", "snapshot_seq": 31, "model": "ledger-default@0.1.0", "config_hash": "sha256:" + "56" * 32,
    "claim_type": "QUANTITATIVE", "prior": "0.50", "prior_log_odds": "0.000000",
    "links": [
        {"link": "L3", "evidence": "E1", "direction": "SUPPORT", "group": "G1", "relevance": "STRONG",
         "observation": "DATASET_RESULT", "interpretive_steps": 1, "magnitude": "0.918000", "effective_weight": "0.918000"},
        {"link": "L4", "evidence": "E2", "direction": "SUPPORT", "group": "G1", "relevance": "MODERATE",
         "observation": "DIRECT_TEXT", "interpretive_steps": 1, "magnitude": "0.459000", "effective_weight": "0.000000",
         "reason": "dependent_strongest_only", "kept": "L3"}],
    "evidence_sum": "0.918000", "posterior_log_odds": "0.918000", "probability": "0.7146", "rounding_boundary": False,
    "variants": {"conservative": "0.6553", "permissive": "0.7673", "spread": "0.1120"}, "stability": "MEDIUM",
    "assessment_state": "LEANS_SUPPORTED", "support_groups": 1, "contradict_groups": 0, "independence_unreviewed": 0,
    "contested": False, "provisional": False, "model_dependent": False, "not_applicable_reason": None,
    "review_checklist": {"primary_source_reviewed": {"ok": True, "by": ["L3"]},
                         "opposing_search_done": {"ok": False, "by": []},
                         "independence_reviewed": {"ok": True, "by": ["T3"]},
                         "qualifiers_reviewed": {"ok": False, "by": []}},
    "review_coverage": "0.50",
}
project = []
for name, o in [("eir-result-v1 envelope without signature", envelope),
                ("eir-task-v1 packet without server_signature", packet),
                ("score trace (spec 03 section 10)", trace)]:
    e = jcs(o)
    project.append({"name": name, "input": o, "expected": e, "sha256": sha(e)})

vec = [
    ("RFC 8032 test 1 (empty message)",
     "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
     "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
     "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
    ("RFC 8032 test 2 (one byte)",
     "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
     "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
     "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
]
ed = []
for name, sk, pk, msg, sig in vec:
    ed.append({"name": name, "private_key_hex": sk, "public_key_hex": pk, "message_hex": msg, "signature_hex": sig,
               "private_key": b64u(bytes.fromhex(sk)), "public_key": b64u(bytes.fromhex(pk)),
               "signature": b64u(bytes.fromhex(sig)),
               "key_id": "ed25519:" + hashlib.sha256(bytes.fromhex(pk)).hexdigest()})

out = {"_about": ("Canonicalization (RFC 8785), hashing, and Ed25519 (RFC 8032) vectors. Expected values were "
                  "produced independently of the Ruby implementation; third-party clients should reproduce them "
                  "byte for byte. Regenerate with: python3 spec/fixtures/gen_canonical_json_vectors.py spec/fixtures/canonical_json_vectors.json."),
       "rfc8785": rfc, "project": project, "ed25519": ed}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("fixture written:", len(rfc), "rfc,", len(project), "project,", len(ed), "ed25519")
