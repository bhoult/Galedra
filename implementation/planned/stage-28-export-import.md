# Stage 28 — Export and import a claim, a topic, or an outline

**Status:** planned · tag will be `stage-28-export-import`

**Tag:** `stage-28-export-import` · **Spec:** 02 §1.1–§1.3 (envelope, chain, validity
windows), 02 §6 (canonical JSON), 06 §2 (API), 14 §P1 (independent mirrors) and §P2
(a node does not need the whole graph), Articles XII (resist capture), XIII (corrections
do not erase history), XV (shared and personal are separate layers), XIX (transparency),
XXI (research should be cumulative), Invariants 1 (one write path), 2 (projections are
derived), 3 (append-only), 4 (deterministic scores), 15 (no text-uniqueness for claims)

Goal: let a person take a claim, a topic, or an outline out of a node as one versioned
JSON file, and let a node take such a file in. Two profiles: **Full**, which carries every
signed contribution and so can be verified and replayed by anyone; and **Compact**, which
carries only the current state of each object and is for reading, citing and diffing.

Why now. Federation is not built and is not being built here, but 14 §P1 asks for
independent mirrors and §P2 says a node need not hold the whole graph. A file is the
smallest thing that delivers both: a mirror is a node that imported one, and a specialised
node is a node that imported only its own subject. It is also the answer to a question the
project cannot currently answer for a contributor: *can I have my work back, in a form that
outlives this server?* Article XXI asks for cumulative research; work no one can carry out
of the building is not cumulative.

## The line this stage must not cross

A foreign contribution cannot join this node's chain. Our sequence numbers are ours, the
hash chain is over our entries, and splicing someone else's entries into it would break
`ledger:verify` for everyone and Invariant 3 with it. So import never appends foreign
entries to the local chain. What it does instead differs by profile, and the difference is
the whole design:

- **Full is mirrored.** The original envelopes arrive with their original signatures, which
  verify against the origin node's published keys and not against ours. They are recorded
  as mirrored entries, kept verbatim and re-verifiable, and the local chain notes that the
  import happened. History survives, attribution survives, and nothing is forged.
- **Compact is re-asserted.** It carries no signatures, so the importing node has no way to
  show that the named authors wrote any of it. Attributing it to them anyway would be a
  forgery this system would then publish as fact. So a Compact import creates new local
  contributions **signed by the importer**, each recording where it was copied from: origin
  node, subject, bundle hash, and the export seq. The record says plainly that this is a
  copy made by this person, and that the original signatures did not come with it.

Getting this wrong is the most dangerous thing in the stage, because the failure is silent
and permanent: a graph full of claims that appear to be signed by people who never saw
them. Acceptance test 5 exists to catch it.

## The file

`eir-export-v1`, a JSON object, with its schema at `schemas/eir-export-v1.json` and served
at `/api/v1/schemas/eir-export-v1` like the others. Every file, both profiles, opens with
the same header:

```json
{
  "protocol": "eir-export-v1",
  "profile": "FULL",
  "origin": { "url": "...", "key_id": "ed25519:...", "schema_version": "eir-schema-v1" },
  "subject": { "type": "CLAIM", "id": "...", "handle": "C2" },
  "snapshot_seq": 5120,
  "scoring_model": "ledger-default@0.1.0",
  "data_license": "ODbL-1.0",
  "counts": { "claims": 14, "evidence": 31, "contributions": 212, "withheld": 2 },
  "bundle_hash": "sha256:...",
  "signature": "..."
}
```

`bundle_hash` is over the body in RFC 8785 canonical form (02 §6), and `signature` is the
node's system key over the header minus itself, following `eir-checkpoint-v1`. A mirror can
therefore tell that a file came from the node it names, intact, without asking that node
anything.

**Full** then carries, in seq order: every contribution in the closure as its verbatim
signed envelope, with `seq`, `entry_hash` and `previous_entry_hash`; every audit, every
acceptance and invalidation, and the status history. It is enough to rebuild the subject
and to check it: the chain links within the export are contiguous or the gaps are named.

**Compact** carries the projections as they stand at `snapshot_seq`: each claim with its
canonical text, type, state and probability under the named model; each evidence item with
its excerpt, source and observation type; each link with its direction and strength; the
section tree for an outline; topics. No envelopes, no signatures, no superseded versions,
no invalidated rows. It states `"verifiable": false` in its own header, because a reader
who cannot check something should be told so by the file rather than by a footnote.

### The closure

What "a claim" means as a file has to be decided before anything is written, because the
graph has no natural edge. The proposal:

| Subject | Includes |
|---|---|
| Claim | the claim, its evidence items and links, the sources and locations those cite, its independence groups, its topics, its inferences and their premises **as references**, the audits on all of the above |
| Topic | every claim tagged with it or a path under it, each as above |
| Outline | the section tree, the claims placed in it, each as above |

Premises of an inference are referenced by id and not followed, or a single claim drags in
the graph. A reference that the file does not resolve is marked `"external": true` with its
origin, so a reader can tell a boundary from an omission.

## Deliverables

- **`Exports::Bundle`**: builds either profile for a subject at a seq. Deterministic: the
  same subject, seq and profile produce a byte-identical file, so two nodes can be compared
  by hash and a citation can name one. Canonical JSON, seq order, and the export's own
  timestamp outside the hashed body.
- **Moderation is honoured and visible.** Quarantined and taken-down material is not
  exported, and `counts.withheld` says how many entries were held back, with the moderation
  log entry that did it. A silent gap would be worse than a visible one (Article XIII).
- **The personal layer never leaves.** Personal assessments, affiliations, users, sessions
  and tokens appear in neither profile (Article XV). This is a test, not a convention.
- **Asynchronous, because an outline can be large.** `POST /api/v1/exports` with a subject
  and profile returns an id; a job builds the file; `GET /api/v1/exports/:id` returns its
  status and then the file. A byte cap, an expiry, and a per-principal rate limit. Small
  subjects may answer inline.
- **`Exports::Verify`**: checks a file without importing it. The node signature, the bundle
  hash, every envelope signature against the origin's published keys, and the chain links
  between the entries present. Available as a command and as an endpoint, because a mirror
  should be able to check a file it did not fetch from us.
- **`Imports::Mirror` (Full)**: verifies, then records one `IMPORT_BUNDLE` control
  contribution naming origin, subject, seq range, bundle hash and the verification result,
  and writes the foreign entries as mirrored rows through `Ledger::Apply` like any other
  projection. Mirrored objects keep their origin ids **under an origin namespace**: they are
  never the same row as a local object that happens to share a UUID. Whether a mirrored
  claim and a local one are the same claim is a `MERGE_CLAIMS` decision, made here,
  reversibly (Invariant 15).
- **`Imports::Restate` (Compact)**: creates local contributions signed by the importer, each
  carrying `derived_from` with origin, subject, bundle hash and export seq. Every claim it
  creates goes through the ordinary write path with the ordinary checks, including
  near-duplicate detection, so a restated claim proposes a merge rather than silently
  doubling the graph.
- **A button, not an API call.** Claim, topic and outline pages get an export control with
  the two profiles and one sentence saying what each is for. Import is under Admin for
  Full, because mirroring is a node-level act, and available to any signed-in contributor
  for Compact, because restating is an ordinary contribution.
- **The format documented under Help.** A new page at `/docs/export`, linked in the Help
  menu beside the API reference, generated from `schemas/eir-export-v1.json` and from the
  same constants the builder uses, so it cannot drift the way the OpenAPI document did
  before Stage 26. It shows both profiles, a worked example of each for the same small
  claim, the closure table above, what is withheld and why, and the verification steps in
  an order a reader can actually follow.
- **A round-trip command**: `bin/rails 'export:subject[claim,ID,full]'` and
  `bin/rails 'import:bundle[path]'`, so the whole thing is usable without a browser and can
  be exercised by `bin/demo`.

## Acceptance

1. Exporting the same subject twice at the same seq produces byte-identical files, and the
   `bundle_hash` matches an independent RFC 8785 hash of the body.
2. A Full export of the demo claim, imported into an empty node, reproduces that claim's
   assessment, probability and trace **byte for byte** under the same model (Invariant 4).
3. A file with one byte changed anywhere in the body is refused by `Exports::Verify`, and
   refused again at import, naming the entry that failed.
4. A Full export whose origin keys are unknown to the importing node is refused, not
   imported unverified.
5. A Compact import creates contributions signed by the importer and by nobody else: no row
   it creates is attributed to a contributor who did not sign on this node, and the origin
   appears as `derived_from`. A Compact file claiming signatures is refused as malformed.
6. Neither profile contains any personal assessment, affiliation, user, session or token,
   asserted over a fixture that has all of them.
7. A quarantined claim and a taken-down contribution are absent from both profiles, and
   `counts.withheld` accounts for them.
8. `/docs/export` names every field the schema defines, and a test fails when the schema
   gains a field the page does not mention.

## Constitutional Test

1. **More traceable?** Yes. A Full export is the most traceable form the record takes: the
   envelopes, their signatures and their chain, portable.
2. **Disagreement more inspectable?** Yes. Two nodes holding the same subject can be
   compared by bundle hash, and where they differ the entries say why.
3. **Hidden authority?** No, and it removes some: today the only way to check this node's
   record is to ask this node.
4. **Reputation substituting for evidence?** No. Nothing here touches reputation.
5. **Uncertainty preserved?** Yes, and deliberately: Compact declares itself unverifiable
   rather than looking like Full with fewer fields.
6. **Reproducible?** Yes; acceptance tests 1 and 2 are the stage in one line.
7. **Challengeable by an opponent?** Yes, and this is the point. An opponent who mirrors the
   graph can audit it without our cooperation, and can restore it if we fall over.
8. **History reconstructable?** Full, yes. Compact, no, and it says so.
9. **Shared and personal separate?** Enforced by test 6.
10. **Used by people we disagree with?** Yes. A record that can be taken away and checked
    elsewhere is worth more to someone who distrusts us than to someone who does not.

## Owner decisions

- The closure table. Following inference premises one hop would make a claim's file far more
  useful and unboundedly larger; not following them makes some files hard to read alone.
- Whether a mirrored claim may ever be merged with a local one, or whether cross-node
  identity waits for federation proper. Merging is reversible, so the conservative reading
  allows it; the cautious one does not.
- Who may import a Full bundle: admin only, or any moderator.
- Whether an export should pin to the latest pinned `graph_snapshot` rather than the head
  seq, which would make exports citable and cacheable and shares a decision with the
  `/weaknesses` question in Stage 26.
- Whether Compact should carry the probability at all. It is model-conditional and the file
  may be read long after the model is superseded, which is Article XX's warning; naming the
  model in the header may not be enough.
