# Stage 23 — Federation readiness

**Status:** implemented · tag `stage-23-federation-ready` · decisions recorded 2026-09-19

## Plan

**Tag:** `stage-23-federation-ready` · **Spec:** 14 §5 (durable identity), §6 (signed
contributions), §7 (signed checkpoints), §10 (explicit visibility and rights), §24
(POC non-goal: do not build federation), §25 (near-term readiness list), 02 §1.2
(hash chain), 05 §2 (system key), Article XII (resist capture), Article XX (evidence
must endure)

Goal: not federation. The single node keeps the properties 14 §25 lists so that a
later federation stage finds nothing to undo: every key says which node it lives on,
every log entry carries an explicit visibility, every pinned snapshot is a checkpoint
signed by the node, and the node can say who it is. Spec 14 §24 forbids peer
discovery, consensus, sharding, and replication here; none is built.

Why these four and nothing more: the readiness list is mostly already true (UUIDv7
ids, content hashes, canonical JSON, replayable projections, versioned models, a
versioned envelope protocol, REST/JSON). What was missing was identity of the node
itself, the home of a key, a rights state on records, and a checkpoint another party
could verify. Each is one column or one small service; none changes what a client
signs, so every existing signature, hash, and golden still verifies.

Deliverables:

- `Ledger::Node`: this node's address (`LEDGER_NODE_URL`, else the first host in
  `LEDGER_ALLOWED_HOSTS` over https, else localhost outside production), its key id
  (the system key), the envelope protocol and a schema version string
  (`eir-schema-v1`), the checkpoint protocol, the data licence (`LEDGER_DATA_LICENSE`,
  unset until the owner decides), the visibilities in use (`PUBLIC` only), and the
  software build. Published as `node` in `GET /api/v1/meta`.
- `contributors.home_url` (nullable): `REGISTER_KEY` accepts an optional `home_url`,
  a plain http(s) origin of at most 200 characters, validated in the applier and
  projected. Null means this node; `Contributor#home_node_url` resolves it. Shown on
  the contributor page and in the contributor JSON. Existing keys need no backfill.
- `contributions.visibility`, `PUBLIC` by default and the only value today, in the
  contribution JSON. It is a column on the log table, not part of the signed
  envelope: what a node may show is the node's statement, not the signer's.
- `graph_snapshots.checkpoint` (jsonb): `Snapshots::Create` signs
  `{protocol, node_url, node_key_id, seq, entry_hash, previous_checkpoint_seq,
  created_at}` with the system key over canonical JSON; `Snapshots::Checkpoint.verify`
  checks it against any public key. Returned by the snapshots API and shown on the
  snapshot page with its verification result.
- `Governance::Software`: the running revision (a `REVISION` file written at image
  build from `GALEDRA_REVISION`, else `git describe` in development, else the env
  var), the repository URL, and Ruby and Rails versions. In `meta` under
  `node.software` and on `/about` (Stage 24).

Acceptance:

1. `REGISTER_KEY` with `home_url: https://other.example.net` projects it and the API
   reports it; without it the API reports this node's URL; a URL with a query,
   userinfo, another scheme, or over 200 characters is `SCHEMA_INVALID`.
2. Every appended entry reads `visibility: PUBLIC` in the API.
3. Pinning seq 0 then seq N yields two checkpoints, the second naming the first as
   previous; both verify under the system key; a changed field or another key fails.
4. `meta.node` carries the key id, protocol, schema version, visibilities, and the
   software build; `LEDGER_ALLOWED_HOSTS` with a leading wildcard entry is skipped
   when deriving the URL.
5. Demo goldens, `ledger:replay`, and `ledger:verify` are unchanged.

## Decision Log (2026-09-19)

- Built together with Stage 24 on the owner's instruction of 2026-09-19: "make sure
  the data structures are appropriate for that future expansion", explicitly not the
  federation itself.
- Readiness checklist (14 §25) against the code, for the record:
  - globally durable ids: UUIDv7 primary keys, entry hashes, content hashes (P0);
  - append-only signed records: `Ledger::Append`, server signature, chain (P0);
  - explicit schema versions: `eir-contribution-v1`, `eir-task-v1`, `eir-result-v1`
    envelopes (P0) and `eir-schema-v1` for the projection schema (this stage);
  - canonical serialization: RFC 8785 (P0);
  - source hashes: `content_hash`, `excerpt_hash` (P0);
  - no row id assumed globally meaningful: ids are derived from contribution ids
    (`Ledger::Ids.derive`) and keys have a home node (this stage);
  - replayable projections: `ledger:replay` (P0);
  - model/version identifiers: `ledger-default@0.1.0` (P0);
  - explicit rights and visibility: `visibility` on entries, `license` on sources
    (P0), `data_license` on the node (this stage; value awaits the owner);
  - clean REST/JSON: `/api/v1` with OpenAPI (P0).
- Node identity is the system key. No separate node key: the key at seq 0 already
  signs every entry, so a mirror learns the node's key from the log itself.
- The checkpoint's `created_at` makes checkpoints non-deterministic across nodes,
  which is right: a checkpoint is a node's statement at a time, not a projection.
  `graph_snapshots` is not a projection table and is not in the replay digest.
- `visibility` is on `contributions`, whose app role cannot `UPDATE` it: a change of
  visibility would be a signed control entry (`QUARANTINE`, `TAKEDOWN`) as today. No
  `PRIVATE` value exists yet; spec 14 §10 needs it only for institutional nodes.
- Licences: spec 14 §23 and `docs/LICENSE-POLICY.md` recommend AGPL for the reference
  node, Apache-2.0 for the protocol, ODbL for the database, CC0 for records, and CC BY
  for docs. The owner adopted that stack on 2026-09-19: `LICENSE` is now the AGPL text,
  `NOTICE` maps directories to licences, and `Ledger::Node.data_license` defaults to
  `ODbL-1.0`.
- Constitutional Test: this stage touches identity and visibility only by adding
  descriptive fields. Answers: 1 yes (no scoring change); 2 n/a; 3 no; 4 no; 5 yes
  (nothing hidden; home node and visibility are shown); 6 yes; 7 yes (replay
  unchanged); 8 yes; 9 yes; 10 yes. No blocker.
