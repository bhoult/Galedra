# Galedra Federation Goal

## Status

This document describes the **long-term architectural and governance direction** of Galedra.

It is **not a P0 implementation requirement**.

The initial proof of concept should remain a simple Rails/PostgreSQL application. Federation should be implemented only after the core claim, evidence, provenance, replay, and scoring models have proven useful on a single node.

---

# 1. Long-Term Goal

Galedra should eventually become a **confederated volunteer network of independently operated nodes** rather than a permanently centralized service.

The public evidence graph may eventually become too large, expensive, politically sensitive, or operationally important for one server or one institution to maintain.

The network should therefore be able to distribute responsibility for:

- storing evidence;
- maintaining portions of the graph;
- auditing contributions;
- serving queries;
- preserving historical snapshots;
- backing up other nodes;
- computing alternative assessments;
- and surviving node failure.

The end state should resemble an open knowledge protocol more than a conventional SaaS application.

---

# 2. Foundational Principle

No node is the truth authority.

A node is:

> a custodian, participant, verifier, and replica of part of the shared epistemic record.

The originating node of a contribution does not become authoritative merely because it created or first stored that contribution.

The graph must be able to survive the loss of its origin.

---

# 3. From Centralized POC to Federation

Expected evolution:

## P0 — Single node

```text
       Galedra
          |
      full local DB
```

Goals:

- prove the data model;
- prove deterministic replay;
- prove scoring;
- prove provenance;
- prove useful single-user/team workflows.

No distributed-systems complexity is justified yet.

---

## P1 — Independent mirrors

```text
        Node A
       /      \
 Mirror B   Mirror C
```

Capabilities:

- export signed snapshots;
- verify snapshots independently;
- replicate selected public records;
- restore the original node from replicas.

This stage is primarily about **durability**, not distributed write coordination.

---

## P2 — Specialized nodes

```text
            federation index
                  |
        +---------+---------+
        |         |         |
   Node History Node Bio  Node Econ
```

Nodes may specialize by:

- domain;
- institution;
- geography;
- language;
- corpus;
- research community;
- storage capacity.

A node does not need the entire global graph to participate.

---

## P3 — Cross-replication

```text
       primary responsibility
              |
      +-------+-------+
      |               |
    Node A          Node B
      |               |
 replica of B      replica of A
      \               /
        \           /
          Node C
       additional replica
```

Important public shards should exist on multiple administratively independent nodes.

The network should be resilient to:

- hardware failure;
- operator abandonment;
- censorship;
- funding loss;
- organizational collapse;
- malicious alteration.

---

## P4 — Confederated network

```text
             signed global manifests
                     |
        +------------+------------+
        |            |            |
      Node A       Node B       Node C
        |            |            |
      shard X      shard Y      shard Z
      backup Y     backup Z     backup X
        |            |            |
        +------ shared protocol ---+
```

No privileged data server is required.

The original Galedra server becomes one participant among many.

---

# 4. Graph, Not Strict Tree

The long-term network may be described informally as nodes maintaining a "subtree," but Galedra's epistemic structure is actually a graph.

The same atomic claim may support:

- multiple documents;
- multiple hypotheses;
- multiple domains;
- multiple arguments.

Therefore federation units should eventually be called **shards**, **subgraphs**, or **collections**, not assume strict tree ownership.

A shard may be defined by:

- claim namespace;
- topic/domain;
- entity set;
- source corpus;
- hash range;
- time interval;
- community-curated collection.

The final partitioning strategy should be learned from real graph usage.

---

# 5. Globally Durable Object Identity

Records must not be identified solely by:

```text
node A database row 123
```

because Node A may disappear.

Federated objects need globally durable identifiers.

Possible components:

```text
object_id
content_hash
origin_signature
creation_timestamp
schema_version
```

Where practical, content-addressable identity should allow any node to verify that two copies represent the same object.

Mutable concepts should be represented through immutable events or versioned records rather than silent in-place mutation.

---

# 6. Signed Contributions

Every accepted contribution should remain independently verifiable outside its originating node.

Contribution envelopes should eventually carry enough information to validate:

- who or what submitted it;
- delegated authority;
- canonical payload;
- signature;
- source references;
- prior event dependencies;
- schema version.

Example conceptually:

```json
{
  "contribution_id": "...",
  "contributor_id": "...",
  "payload_hash": "...",
  "parents": ["..."],
  "schema_version": "...",
  "signature": "..."
}
```

A replica should not need to trust the transport node.

---

# 7. Signed Checkpoints

Nodes should periodically publish cryptographically signed checkpoints.

Conceptually:

```text
node_id
checkpoint_sequence
timestamp
included_shards
merkle_root
protocol_version
previous_checkpoint
signature
```

Other nodes can then attest:

> I possess a verified replica corresponding to checkpoint X.

This makes replication measurable rather than assumed.

---

# 8. Replication

A healthy federation should make important public records exist on multiple independent nodes.

Possible future federation policies:

```text
minimum replicas: 3
minimum administrative domains: 2
minimum geographic regions: 2
```

These numbers are examples, not current requirements.

Replica assignment may eventually consider:

- available storage;
- bandwidth;
- node reliability;
- jurisdiction;
- domain interest;
- correlated failure risk.

---

# 9. Storage Participation Can Be Asymmetric

Nodes should not need equal resources.

Possible node classes:

## Full archival node

Stores most or all public graph data.

## Domain node

Maintains a domain such as:

```text
medicine/*
climate/*
ancient-history/*
```

## Replica node

Primarily backs up shards maintained elsewhere.

## Index node

Stores lightweight manifests/indexes while retrieving deep data from peers.

## Personal node

Maintains a user's private overlays and a selected public subset.

## Institutional node

Maintains public federation data plus separate private research data.

The federation should benefit from heterogeneous participation rather than requiring identical servers.

---

# 10. Public and Private Data Must Remain Distinguishable

A participating institution may have:

```text
public federation graph
+
private internal evidence
+
licensed datasets
```

Only the public federation layer is automatically subject to federation synchronization.

The architecture must never require publication of private material merely because it is processed by a federation-compatible node.

Every record should have an explicit visibility/rights state.

---

# 11. Evidence Can Be Shared Without Sharing Conclusions

This is a central federation principle.

Nodes may agree about:

```text
source
quotation
measurement
provenance
claim relationship
```

while disagreeing about:

```text
prior
scoring model
inference weight
interpretation
final assessment
```

The federation should not require one global truth score.

Different nodes may run different versioned scoring models over the same shared evidence.

This is a feature, not fragmentation.

The network should make the source of disagreement inspectable.

---

# 12. Personal Belief Remains an Overlay

A person's or institution's belief profile should remain separate from the public evidence graph.

A node may expose:

```text
shared evidence assessment
organization model assessment
user personal assessment
```

without confusing them.

Federation should synchronize shared epistemic objects, not force synchronization of private beliefs.

---

# 13. Conflicts Are Preserved

Federation does not mean selecting one authoritative version of every claim.

Nodes should preserve competing:

- claims;
- evidence;
- audits;
- interpretations;
- scoring models.

Consensus may emerge, but disagreement remains representable.

A merge conflict in epistemic content is often **information**, not merely a technical problem to overwrite.

---

# 14. Eventual Consistency Over Global Locking

The federation should prefer append-only/event-sourced synchronization over requiring a globally serialized write transaction.

A volunteer global network cannot depend on:

- one global database lock;
- one central leader;
- constant connectivity;
- one trusted timestamp server.

Conflicts should be reconciled through signed event histories and deterministic rules where possible.

The exact synchronization protocol is a post-POC research problem.

---

# 15. Federation Membership

Running compatible software does not automatically make a node a recognized federation member.

Anyone should be able to:

- fork the software;
- run a private node;
- build a compatible implementation.

Recognized federation participation should eventually be governed by a **Federation Charter**.

Possible charter requirements:

- persistent cryptographic node identity;
- supported federation protocol version;
- signed checkpoint publication;
- provenance preservation;
- public sync endpoints;
- honest capacity advertisement;
- minimum replica obligations;
- takedown/redaction protocol compliance;
- no silent rewriting of signed records;
- availability reporting;
- clear separation of public and private records.

Membership does not grant epistemic authority.

---

# 16. Node Reputation Is Operational, Not Truth Authority

Federation may need to assess node behavior.

Useful operational reputation dimensions might include:

```text
uptime
successful replication
checkpoint consistency
protocol compliance
audit responsiveness
historical data preservation
```

These metrics must not become:

> This node's claims are more true because the node is prestigious.

Operational reliability and epistemic evidence remain distinct.

---

# 17. Failure and Recovery

The network should eventually tolerate the permanent disappearance of a node.

A node should be reconstructible from:

```text
software
+
federated public event history
+
replicated shard data
+
signed checkpoints
```

No critical public claim or evidence item should depend indefinitely on a single origin server.

This should become a measurable network property.

---

# 18. Redaction and Legal Takedown

Immutable history and real-world legal obligations can conflict.

Federation will eventually need a protocol that can distinguish:

- logical invalidation;
- cryptographic tombstoning;
- removal of copyrighted payload bytes;
- removal of illegal/private content;
- preservation of non-sensitive hashes and audit history where lawful.

Nodes in different jurisdictions may have different legal obligations.

A redaction manifest should be attributable and signed.

The federation should never falsely claim byte-perfect replay where lawful deletion has made that impossible.

---

# 19. Anti-Capture Goal

Federation exists partly to resist institutional capture.

The desired network should make it difficult for any single:

- company;
- government;
- political organization;
- university;
- nonprofit;
- original project maintainer

to silently redefine the shared evidence record.

This does not mean governance disappears.

It means governance becomes inspectable, plural, and technically difficult to monopolize.

---

# 20. Volunteer Economics

A volunteer network succeeds only if participation produces more value than operational burden.

Nodes may contribute:

- storage;
- bandwidth;
- agent inference;
- audits;
- specialized expertise;
- mirrors;
- indexes.

The scheduler should eventually distinguish valuable contribution from harmful low-quality volume.

Possible future metric:

```text
net contribution value
=
epistemic value produced
- audit burden
- correction burden
- storage/bandwidth externalities
```

Federation should not equate raw volume with contribution quality.

---

# 21. Discovery

Eventually, nodes need to discover:

- peers;
- shard locations;
- replica counts;
- supported protocol versions;
- scoring models;
- index endpoints.

Possible future mechanisms include:

- signed federation manifests;
- DNS-based discovery;
- well-known URLs;
- gossip;
- distributed indexes;
- ActivityPub-style discovery;
- content-addressed lookup.

Do not choose a mechanism before real federation requirements are known.

---

# 22. Protocol Is More Important Than the Reference Implementation

The long-term success condition is not:

> everyone runs the Rails application.

It is:

> independent implementations can participate in the same epistemic commons.

Therefore the protocol must eventually be:

- documented;
- versioned;
- testable;
- implementation-neutral;
- permissively licensed;
- accompanied by conformance vectors.

Possible future implementations:

```text
Rails
Go
Rust
Python
university research system
browser-local personal node
```

The reference Rails application should prove the protocol, not own it.

---

# 23. Relationship to Licensing

Recommended separation:

```text
reference node software
  -> AGPL-3.0-or-later

federation protocol / schemas / SDKs
  -> Apache-2.0

public shared database
  -> ODbL-1.0

eligible individual project-authored factual records
  -> CC0-1.0
```

Licenses protect openness.

They should not attempt to encode all federation behavior.

Operational cooperation belongs in the Federation Charter.

---

# 24. POC Non-Goal

Do **not** implement the federation now.

The POC should not add:

- peer discovery;
- distributed consensus;
- sharding infrastructure;
- DHTs;
- federation gossip;
- multi-primary writes;
- custom replication engines.

Doing so before validating the epistemic data model would spend effort on the wrong uncertainty.

The POC should merely avoid architectural decisions that make federation unnecessarily difficult later.

---

# 25. Near-Term Federation Readiness

The single-node POC should preserve a few properties that make later federation possible:

- globally durable UUIDs or content-addressed IDs;
- append-only signed contribution records;
- explicit schema versions;
- canonical serialization;
- source hashes;
- no assumption that one database row ID is globally meaningful;
- replayable projections;
- model/version identifiers;
- explicit rights/visibility metadata;
- clean REST/JSON interfaces.

These are useful even if federation never occurs.

---

# 26. Long-Term Success Condition

Galedra should eventually be able to survive the disappearance of:

- its founder;
- its original GitHub organization;
- its first hosting provider;
- its original database;
- its original scoring model.

If the public evidence commons can be reconstructed and continued by independent participants, the architecture has succeeded.

---

# 27. Guiding Vision

The federation should behave like a distributed cairn:

> No stone is the monument by itself.  
> No single keeper owns the witness.  
> Each participant preserves part of the record, and overlapping custody makes the record harder to erase or silently rewrite.

The long-term goal is:

> **a volunteer-operated, cryptographically verifiable, independently replicable commons of evidence and reasons that no single institution must be trusted to preserve.**
