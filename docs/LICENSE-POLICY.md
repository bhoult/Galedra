# Galedra Licensing Policy

> **Status:** Project policy draft for the initial open-source release.  
> This document is not legal advice. Before a major public launch, commercial partnership, or relicensing decision, the project should have the policy reviewed by counsel familiar with open-source software and open-data licensing.

## 1. Goals

Galedra is intended to become an open, inspectable, federated epistemic commons.

The licensing model should encourage:

- public inspection of the software that evaluates and serves evidence;
- independent operation of compatible nodes;
- federation rather than dependence on one central operator;
- replication and preservation of the public evidence graph;
- commercial and noncommercial use;
- broad implementation of the federation protocol;
- reuse of individual factual records;
- contribution by humans, institutions, and AI agents;
- continued openness of publicly operated derivative databases;
- long-term resistance to enclosure by a single company or institution.

The project should remain useful even if the original maintainers or original server disappear.

---

# 2. Recommended License Stack

Different layers of Galedra have different licensing needs.

## 2.1 Reference node software

**License: AGPL-3.0-or-later**

Applies to the primary Galedra server/reference implementation, including:

- Rails application code;
- graph management;
- contribution ingestion;
- audit workflows;
- scoring implementation;
- federation-node implementation;
- administrative interfaces;
- server-side synchronization logic.

### Rationale

Galedra is primarily network software.

AGPL is intended to preserve source availability even when modified software is operated as a network service rather than distributed as a binary.

The desired principle is:

> Anyone may operate a Galedra node, including commercially, but users of a materially modified AGPL reference node should be able to inspect the corresponding source.

This aligns with the project's constitutional preference for inspectable machinery over trusted authority.

---

## 2.2 Federation protocol, schemas, test vectors, and SDKs

**License: Apache-2.0**

Applies to material intended to enable independent implementations, such as:

- wire protocols;
- JSON schemas;
- OpenAPI definitions;
- canonical serialization specifications;
- signature formats;
- synchronization specifications;
- federation test vectors;
- client SDKs;
- lightweight integration libraries;
- protocol conformance suites where practical.

### Rationale

The protocol should be easier to adopt than the reference server.

A university, company, nonprofit, individual developer, or future implementation should be able to build a compatible node or client without being forced to use the AGPL reference code.

The federation must be larger than one implementation.

Apache-2.0 also provides an explicit patent grant, which is useful for widely implemented infrastructure.

---

## 2.3 Public federated database

**License: Open Database License 1.0 (ODbL-1.0)**

Applies to the public Galedra database as a database/collection, including the organized public graph of:

- claims;
- evidence relationships;
- graph edges;
- public provenance metadata;
- public source metadata;
- public audit results;
- public contributor records;
- public graph snapshots;
- publicly shared derived database structure.

### Rationale

The long-term goal is a confederated network in which nodes:

- maintain portions of the graph;
- mirror portions maintained by other nodes;
- publish derivative views;
- synchronize public records;
- survive the failure or disappearance of other nodes.

The project therefore wants more than permission to copy the database.

It wants public derivative databases to remain part of an open data commons.

ODbL is intended to preserve share-alike obligations at the database layer while allowing broad reuse.

The desired principle is:

> Anyone may take the public commons and build on it, but a publicly used adapted version of the shared database should not become a permanently closed dependency.

---

## 2.4 Individual project-authored factual records

**License/dedication: CC0-1.0 where legally possible**

For structured factual assertions or metadata created by the project and not subject to third-party rights, Galedra should dedicate its own copyright and related rights in the individual contents as broadly as practical.

Examples may include:

- normalized factual claim text;
- identifiers;
- noncreative metadata;
- public machine-generated relationship records;
- basic measurements;
- contributor-created structured factual annotations.

### Rationale

Individual facts should be maximally reusable.

The project should not attempt to create a copyright moat around facts.

This creates a useful distinction:

```text
individual reusable factual content
              |
             CC0

curated federated database as a whole
              |
            ODbL
```

ODbL governs rights in the database/collection. Separate third-party rights may still apply to individual contents.

---

## 2.5 Project-authored prose and documentation

**License: CC BY 4.0**

Applies to original project-authored material such as:

- conceptual documentation;
- tutorials;
- explanatory essays;
- diagrams;
- governance documents where copyright applies;
- educational material.

### Rationale

This material should be freely reusable while preserving attribution.

Source code examples that are intended for incorporation into software may instead be Apache-2.0 or AGPL according to their directory.

---

## 2.6 Imported third-party material

**License: remains governed by the original source**

Galedra cannot relicense content it does not own.

Examples:

- journal articles;
- news articles;
- books;
- photographs;
- proprietary datasets;
- licensed legal databases;
- copyrighted quotations;
- third-party research corpora.

The graph should preserve rights metadata when known.

Recommended fields include:

```text
rights_status
source_license
rights_holder
reuse_scope
quotation_basis
source_url
source_hash
```

A factual claim extracted from a source may be reusable even when the source text itself is copyrighted. The system must not treat those as the same object.

---

# 3. Contributor Policy

## 3.1 Code contributions

Use a **Developer Certificate of Origin (DCO)** rather than requiring a Contributor License Agreement at project launch.

Contributors certify that they have the right to submit their contribution under the applicable project license.

Expected Git workflow:

```text
Signed-off-by: Contributor Name <email@example.com>
```

### Why DCO first

A DCO:

- has low contributor friction;
- preserves contributor ownership;
- fits normal open-source workflow;
- records contribution provenance;
- avoids giving the project owner unnecessary unilateral relicensing rights.

A CLA can be reconsidered later if a compelling governance or dual-licensing reason emerges.

---

## 3.2 Data/content contributions

Every submitted public contribution should include an explicit rights attestation.

Conceptually:

> I have the right to contribute this structured record and authorize its inclusion in the Galedra public database under the project's published data licensing policy.

The contribution envelope should record:

```text
contributor_id
contribution_id
content_license_or_rights_basis
database_license_at_submission
source_rights_status
timestamp
signature
```

AI agents act on behalf of a human, organization, or autonomous project identity according to the identity/delegation model, but the contribution must still have a valid rights basis.

---

# 4. Repository Layout

Recommended root layout:

```text
LICENSE
LICENSES/
  AGPL-3.0-or-later.txt
  Apache-2.0.txt
  ODbL-1.0.txt
  CC0-1.0.txt
  CC-BY-4.0.txt

LICENSE-POLICY.md
CONTRIBUTING.md
DCO.txt
NOTICE
```

The root `LICENSE` should identify AGPL-3.0-or-later as the default license for source files unless a file or directory explicitly states another license.

Directories using a different license should contain an unambiguous notice.

For example:

```text
/protocol       Apache-2.0
/sdk            Apache-2.0
/docs           CC BY 4.0
/app            AGPL-3.0-or-later
/lib            AGPL-3.0-or-later unless marked otherwise
```

---

# 5. Licensing Must Be Machine-Readable

Where practical:

- use SPDX identifiers;
- include SPDX headers in source files;
- expose license metadata in APIs;
- preserve source licenses when importing records;
- expose database license information in federation manifests.

Example source header:

```text
SPDX-License-Identifier: AGPL-3.0-or-later
```

Example protocol header:

```text
SPDX-License-Identifier: Apache-2.0
```

---

# 6. Federation and Licensing

Copyright licenses should not be used to enforce all federation behavior.

The software license answers:

> What are you legally allowed to do with the code?

The database license answers:

> What are you legally allowed to do with the shared database?

A separate **Federation Charter** should answer:

> What behavior is required to participate as a recognized Galedra federation node?

For example, recognized nodes may eventually be expected to:

- publish stable cryptographic identities;
- expose signed synchronization checkpoints;
- preserve attribution and provenance;
- replicate assigned foreign shards;
- permit synchronization of public data;
- publish supported protocol versions;
- honor valid redaction/takedown manifests;
- maintain minimum integrity/availability standards.

A fork remains free to exist outside the recognized federation.

This is intentional.

Open-source licensing should preserve freedom to fork. Federation governance should determine which nodes cooperate as members of the shared network.

---

# 7. No Single-Operator Dependency

Licensing choices should support the following long-term property:

> No contributor, company, institution, or original maintainer should be able to make continued access to the public knowledge commons dependent on their continued operation.

Therefore:

- protocol specifications remain permissive;
- public database replicas are legally possible;
- reference server modifications remain inspectable under AGPL;
- public derivative databases remain share-alike under ODbL;
- factual records remain broadly reusable;
- node identities and graph records must not depend on proprietary central identifiers.

---

# 8. Trademark Is Separate From Copyright

Open-source licensing does not require unrestricted use of project trademarks.

The project may eventually protect the **Galedra** name and logo so that users can distinguish:

- official/reference implementations;
- recognized federation members;
- independent compatible implementations;
- unrelated forks.

Trademark policy should not prevent forks from accurately describing compatibility.

Example:

> "Compatible with the Galedra Federation Protocol"

may be acceptable even when:

> "Official Galedra Node"

is reserved for recognized participants.

This can become useful once federation governance exists.

---

# 9. Changes to Licensing

Licensing becomes difficult to change once many contributors own copyright interests.

Before accepting broad outside contributions, the project should intentionally confirm:

- AGPL-3.0-or-later for the reference server;
- Apache-2.0 for interoperability layers;
- ODbL-1.0 for the public database;
- CC0-1.0 for eligible individual project-authored factual content;
- CC BY 4.0 for project-authored prose/docs;
- DCO for code contributions.

Future changes should be explicit and publicly documented.

---

# 10. Guiding Principle

The licensing structure should optimize for a commons that can outlive its founder.

The desired outcome is:

> **Anyone can leave with the software and the public knowledge. Anyone can build a compatible node. No one should be able to take the shared commons, publicly improve it, and turn those improvements into a permanently closed dependency.**
