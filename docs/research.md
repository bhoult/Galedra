# Research Notes — Adjacent Systems and Prior Art

## Purpose

This document captures adjacent projects, standards, and research directions discovered while evaluating whether the Epistemic Ledger / GalEd concept already exists elsewhere.

The conclusion at this stage is:

> No mature system was found that combines all of the core ideas into a general-purpose, agent-native, auditable epistemic substrate.

However, several existing systems solve important parts of the problem well. The project should avoid reinventing those layers and should instead aim to interoperate with them.

This file is intentionally deferred research. Revisit it after the initial POC is working.

---

# 1. Scite

Website: https://scite.ai/

## What it does

Scite analyzes scientific citation contexts and classifies citations as supporting, mentioning, or contradicting published research.

It has significant real-world adoption and a large indexed research corpus.

## Why it matters

Scite demonstrates that users value evidence-aware research tooling.

It also already solves part of the scientific evidence-discovery problem that this project should not reproduce from scratch.

## Overlap

- evidence retrieval;
- support/contradiction classification;
- scientific literature;
- AI-assisted research.

## Difference

Scite is primarily paper- and citation-centric.

The Epistemic Ledger is intended to represent:

- atomic claims;
- evidence;
- inference relationships;
- source independence;
- competing hypotheses;
- provenance;
- agent contributions;
- scoring models;
- audits;
- uncertainty;
- personal belief overlays.

## Potential integration

Treat Scite as an external evidence source.

Possible future flow:

```text
claim
  -> search Scite
  -> retrieve relevant citation contexts
  -> create candidate evidence records
  -> verify provenance and independence
  -> incorporate into evidence graph
```

Scite also supports MCP-based access, making agent integration potentially straightforward.

---

# 2. Wikidata

Website: https://www.wikidata.org/

## What it does

Wikidata is a massive structured knowledge graph containing entities, statements, qualifiers, and references.

## Why it matters

The project should not create its own global ontology of:

- people;
- organizations;
- places;
- scientific concepts;
- historical entities;
- countries;
- chemical compounds;
- and similar shared objects.

## Overlap

- structured assertions;
- references;
- qualifiers;
- entity identity.

## Difference

Wikidata primarily represents:

```text
entity
  -> statement
  -> qualifier
  -> reference
```

The Epistemic Ledger needs deeper reasoning structure:

```text
claim
  -> evidence
  -> support / contradiction
  -> inference
  -> hypothesis
  -> model-conditioned assessment
```

## Potential integration

Use Wikidata identifiers when practical.

Example:

```text
entity_type: PERSON
external_id:
  wikidata: Q12345
```

Do not attempt to replace Wikidata.

---

# 3. Kialo

Websites:

- https://www.kialo.com/
- https://www.kialo-edu.com/

## What it does

Kialo provides structured argument trees:

```text
thesis
  -> pro
  -> con
  -> sub-arguments
```

It has meaningful adoption, especially in education.

## Why it matters

Kialo is probably the strongest existing source of UX lessons for displaying structured reasoning to ordinary users.

## Overlap

- argument trees;
- pro/con relationships;
- sourced claims;
- nested reasoning.

## Difference

Kialo is primarily a debate and discussion platform.

It does not appear to provide the full epistemic substrate needed here:

- reusable global atomic claims;
- evidence independence;
- signed agent work;
- deterministic scoring;
- replayable state;
- task/domain reputation;
- evidence coverage;
- graph-wide provenance.

## Potential lessons

Study:

- how argument trees are rendered;
- how users expand/collapse reasoning;
- how complexity is hidden;
- how sources are displayed;
- how disagreements are represented.

Do not assume users want to interact directly with graphs merely because the internal representation is a graph.

---

# 4. Nanopublications

Website: https://nanopub.net/

## What they are

Nanopublications represent small, atomic assertions together with provenance and publication metadata.

Typical conceptual structure:

```text
assertion
provenance
publication information
```

## Current status

Nanopublications are not merely historical prior art. The ecosystem is active and still evolving.

Published literature reports **more than 10 million nanopublications publicly accessible worldwide**. The current Nanopub Registry is a **second-generation publication and lookup service** that supersedes the older nanopub-server architecture and is still under active development. The current ecosystem also includes Nanodash, Nanopub Query, signing tools, and decentralized registry infrastructure.

This materially increases the importance of interoperability.

## Why they matter

This is probably the strongest existing standard adjacent to the lowest layer of the Epistemic Ledger.

The conceptual overlap is substantial:

- atomic claims;
- provenance;
- attribution;
- reusable assertions;
- decentralized publishing;
- queryable structured knowledge;
- signed and content-addressable publication.

The project should regard nanopublications as a neighboring ecosystem rather than just an academic format.

## Knowledge provenance extension

A particularly important 2025 extension proposes adding **knowledge provenance** for assertions derived from multiple sources rather than a single publication.

That work explicitly models situations where a claim emerges from a body of knowledge containing:

- supporting evidence;
- conflicting evidence;
- aggregation or truth-discovery processes;
- agent-to-proposition trust relationships.

The authors published **197,511 assertions** using the extended model.

This is close enough to the Epistemic Ledger's support/contradiction and multi-source reasoning problem that the paper should be read before finalizing the post-POC evidence schema.

Important difference:

The nanopublication work does not appear to provide the complete system proposed here:

- deterministic, versioned scoring;
- independence groups;
- adversarial audit workflow;
- task-specific contributor reputation;
- agent work packets;
- replayable assessment state;
- personal belief overlays.

It is still primarily a publishing/provenance format rather than a complete assessment system.

## Recommendation

Do not redesign the POC around RDF or nanopublication tooling.

However, **nanopublication compatibility should be a P1 commitment, not a vague future possibility**.

After the internal Rails model stabilizes:

1. define a documented internal-object-to-nanopublication mapping;
2. support nanopublication export;
3. investigate importing nanopublications as candidate evidence/assertions;
4. evaluate whether the knowledge-provenance extension overlaps with or improves the internal evidence-lineage model;
5. contact the nanopublication community before inventing incompatible equivalents.

Target architecture:

```text
internal Rails model
      |
      +-- REST / JSON
      +-- W3C PROV export
      +-- nanopublication export/import
```

This gives the project:

- an existing scientific interoperability story;
- access to a community already working on atomic claims and provenance;
- a fallback publication format even if the project's own public network never becomes large.

## Sources to revisit

- https://nanopub.net/
- https://nanopub.net/docs/architecture/
- https://github.com/knowledgepixels/nanopub-registry
- https://doi.org/10.5281/zenodo.15647977
- "Provenance-driven nanopublications: representing source lineage and trust networks for multi-source assertions"

---

# 5. W3C PROV

Website: https://www.w3.org/TR/prov-overview/

## What it does

W3C PROV is a standard model for representing provenance:

- entities;
- activities;
- agents;
- derivation;
- attribution;
- generation;
- usage.

## Why it matters

The project should avoid inventing incompatible provenance semantics when a mature standard already exists.

## Potential use

Map internal contribution and source records to PROV concepts.

Example:

```text
Contribution
  -> prov:Activity

Contributor / Agent
  -> prov:Agent

Evidence object
  -> prov:Entity
```

Internal implementation can remain simpler than full PROV.

Compatibility should be an export concern first.

---

# 6. ClaimReview

Reference:

https://schema.org/ClaimReview

## What it does

ClaimReview is structured markup used for fact-checking claims and assessments.

## Why it matters

If the system eventually exposes public claim assessments, ClaimReview-compatible output could make those assessments interoperable with existing fact-check infrastructure.

## Potential use

Export selected public claim evaluations into ClaimReview-compatible metadata.

Do not use ClaimReview as the internal reasoning model.

---

# 6A. Open Research Knowledge Graph (ORKG)

Website: https://orkg.org/

## What it does

The Open Research Knowledge Graph is an institutionally supported scientific knowledge infrastructure associated with TIB and L3S.

Its ORKG Ask service, launched in 2024, was described as answering natural-language research questions across roughly **80 million scientific publications** using semantic search, language models, and the ORKG knowledge graph.

ORKG also supports structured scientific contributions, templates, comparison of research contributions, and identifier integration.

## Why it matters

ORKG is evidence that serious institutional investment exists around converting scientific literature into structured, machine-actionable knowledge.

## Difference

Its primary task is closer to:

> What does the scientific literature contain?

than:

> Given conflicting evidence, provenance, dependencies, and assumptions, how strongly should a particular claim currently be supported?

It does not replace the Epistemic Ledger's intended:

- independence-aware evidence aggregation;
- adversarial audit process;
- contributor task reputation;
- deterministic versioned scoring;
- signed distributed agent work;
- personal belief overlays.

## Recommendation

Do not pivot into ORKG or attempt to replicate its literature corpus.

After POC, investigate:

- ORKG API access;
- entity and paper identifiers;
- contribution templates;
- possible import/export mappings;
- whether ORKG assertions can be treated as candidate evidence nodes.

ORKG is more likely to be an upstream/downstream integration than a replacement.

Source to revisit:

- https://www.l3s.de/new-orkg-ask-service-launched/

---

# 6B. Legal citation verification market

## Finding

The original P0 idea of "verify AI-generated citations" is **already a crowded product category**, especially in legal technology.

As of September 17, 2026, Reuters reported AI-generated errors or fabricated citations appearing in at least **1,395 U.S. state and federal cases**.

Multiple tools now verify legal citations against authoritative or public case databases, and some go further by checking whether:

- quoted language actually appears in the opinion;
- the cited case supports the stated proposition;
- authority has been weakened or overruled;
- the cited pinpoint is correct.

Examples found during the scan include commercial tools and open-source projects such as CiteCheck, CiteDiver, cite.review, LegalVerify, Hallucination Shield, and others.

Academic work published in 2026 also shows that proposition-level citation verification remains difficult: models often detect completely wrong cases but struggle with subtler cases where a real source is cited for a proposition it does not actually support.

## Strategic implication

"Verify your citations" is no longer a differentiated product pitch.

The project's stronger differentiation is:

> **Verified once, reusable forever.**

The valuable object is not the one-time check.

It is the durable, attributable, reusable verification record that can later support:

- another document;
- another agent;
- another analysis;
- an audit;
- a changed scoring model.

## Recommendation

Do not choose legal citation checking as the first vertical.

Reasons:

- incumbent legal databases have strong proprietary advantages;
- many new products are already targeting the problem;
- proposition-level legal verification can require expensive licensed data;
- legal liability raises the cost of errors.

Legal remains an excellent **later test domain**, because its requirements for provenance and auditability are stringent.

Better first P0/P1 users may be:

- academic research;
- internal corporate research;
- investigative analysis;
- technical literature review;
- AI-assisted general research.

Sources to revisit:

- Reuters, September 17, 2026: AI error-ridden court filings
- https://legalai.com/citecheck
- https://github.com/sboghossian/hallucination-shield
- arXiv: "Who Checks the Citations? Benchmarking Legal Hallucination Detection"
- arXiv: "Is this Citation on Point?"

---

# 7. Rootclaim

Website: https://www.rootclaim.com/

## What it does

Rootclaim performs structured probabilistic analysis of competing hypotheses.

Its process includes:

- enumerating hypotheses;
- gathering evidence;
- assigning priors;
- evaluating likelihoods;
- handling evidence dependencies;
- calculating posterior probabilities.

## Why it matters

Rootclaim is one of the closest conceptual precedents for the probabilistic reasoning layer.

Its motivations are also closely aligned:

- avoiding cherry-picking;
- handling uncertain evidence;
- comparing competing explanations;
- preventing double-counting of dependent evidence.

## Important difference

Rootclaim is primarily oriented toward producing an analysis.

The Epistemic Ledger is intended to preserve the reusable substrate from which many analyses can later be generated.

That distinction is important:

```text
Rootclaim-like approach:
question
  -> analysis
  -> conclusion

Epistemic Ledger:
atomic evidence
  -> reusable graph
  -> many possible models
  -> many possible analyses
```

## Research questions

After POC:

- How does Rootclaim formally handle dependency?
- How are likelihood ratios assigned?
- How does it expose sensitivity to priors?
- How much of its process is public/reproducible?
- Does it have an API or collaboration model?
- Would collaboration or interoperability make sense?

Possible future outreach is warranted.

---

# 8. Reason Commons

Website: https://reasoncommons.com/

## What it does

Reason Commons aims to make reasoning cumulative rather than ephemeral.

It uses structured reasoning trees and AI-assisted transformation of discussions or documents into maintained reasoning structures.

## Why it matters

This is philosophically one of the closest projects found.

It independently recognizes the same core problem:

> useful reasoning currently disappears inside conversations and documents.

## Difference

Its emphasis appears closer to:

- systems thinking;
- issue trees;
- action trees;
- collaborative reasoning.

The Epistemic Ledger places more weight on:

- evidence provenance;
- atomic claims;
- independent verification;
- scoring;
- audits;
- cryptographic attribution;
- source independence.

## Current maturity

At the time of research, it was still early-stage and did not appear to have a mature production system.

## Recommendation

Monitor closely.

Potential future collaborator rather than a project to replace this one.

---

# 9. Proofweave

Repository:

https://github.com/alexyyyander/proofweave

## What it does

Proofweave uses AI agents, signed work, verification, and append-only records in the domain of formal mathematical proof.

Conceptual flow:

```text
human principal
  -> delegated AI agent
  -> signed work product
  -> independent verification
  -> reproducible result
  -> append-only receipt
```

## Why it matters

Technically, this is one of the closest examples of the proposed agent contribution model.

Useful concepts include:

- delegated identity;
- signed contribution envelopes;
- verification gates;
- owner separation;
- append-only correction history.

## Difference

Its domain is formal mathematics, especially Lean.

Formal proofs can ultimately be machine-verified in a way that most empirical or historical claims cannot.

## Recommendation

Study protocol design and attribution mechanics.

Borrow ideas where appropriate.

Do not assume its verification guarantees generalize to empirical reasoning.

---

# 9A. Portable Agent Memory and adjacent agent-memory systems

Reference:

- arXiv: "Portable Agent Memory: A Protocol for Cryptographically-Verified Memory Transfer Across Heterogeneous AI Agents" (2026)

## What it does

Portable Agent Memory proposes persistent memory transfer across heterogeneous AI agents using:

- content-addressable memory entries;
- a Merkle-DAG provenance graph;
- capability-based access control;
- injection-resistant rehydration;
- a portable JSON-first representation.

The published protocol includes an open-source implementation and demonstrates memory transfer between multiple model families.

## Why it matters

This work independently converges on several technical mechanisms that also appear in the Epistemic Ledger:

- content addressing;
- cryptographic provenance;
- durable state outside any one model;
- cross-model portability;
- tamper evidence.

## Difference

Agent-memory systems primarily preserve:

> what an agent knows or remembers.

The Epistemic Ledger asks:

> why is this proposition warranted?

That requires additional machinery:

- evidence support/contradiction;
- evidence independence;
- audit and challenge;
- provenance to external sources;
- inference structure;
- model-conditioned scoring;
- epistemic completeness.

## Recommendation

Treat agent-memory systems as adjacent infrastructure, not competitors.

After POC, investigate whether epistemic records can be exposed as a special high-trust memory type that agents can import without treating them as unquestioned facts.

Source:

- https://arxiv.org/abs/2605.11032

---

# 10. GALED

Website:

https://galed.ai/

## What it does

GALED is an AI trust/provenance system centered around verified records tied to:

- sources;
- verification methods;
- timestamps;
- signed data;
- durable history.

## Why it matters

The naming collision was important because its conceptual metaphor is very close to this project.

It independently uses the same "witness / durable record" idea.

## Difference

Its visible scope appears much narrower, oriented around verified commercial or business records rather than a general epistemic reasoning graph.

## Recommendation

Do not use plain "GalEd" as the public brand because of the strong category overlap.

Continue monitoring the technical model.

---

# 11. Evidence Graph / Claim Graph Projects

Several research and software projects use terms such as:

- Evidence Graph;
- Claim Graph;
- Argument Graph;
- Knowledge Graph;
- Reasoning Graph.

## Lesson

These names are crowded and too generic to function well as distinctive public brands.

However, "evidence graph" remains a useful internal architectural term.

---

# 12. Lessons From Prior Argument-Mapping Projects

Examples mentioned during research include:

- Debategraph;
- Arguman;
- Canonical Debate Lab;
- TruthMapping;
- Kialo.

Many structured argument systems struggled to achieve broad adoption.

## Common adoption problems

### High contribution cost

Structured claims require:

- decomposition;
- source verification;
- relationship typing;
- deduplication;
- context analysis.

AI dramatically lowers this cost but does not eliminate verification needs.

### Benefits accrue to later users

The person doing the work often gets less benefit than future users.

This creates weak contribution incentives.

### Readers want conclusions

Most users do not want to navigate a graph.

They want:

> What should I know, and why?

Therefore:

> The graph should power the answer, not necessarily be the default interface.

### Moderation and capture

Public reasoning systems attract:

- ideological conflict;
- coordinated manipulation;
- low-quality contributions;
- endless relitigation.

The current constitutional and audit model is partly designed to address these problems.

---

# 13. Claim Identity Is a Major Open Problem

Atomic claims do not have trivial identity.

Example:

```text
C1: Unemployment fell in 2025.
C2: U.S. unemployment fell in 2025.
C3: U.S. unemployment fell from January to December 2025.
C4: U.S. unemployment fell because of policy X.
```

These are related but not interchangeable.

## Risks

Aggressive semantic deduplication can destroy important distinctions.

Loose deduplication fragments evidence across duplicate claims.

## Recommended approach

Semantic search should propose candidate relationships:

```text
SAME_AS
NARROWS
BROADENS
QUALIFIES
```

Do not silently merge claims.

Claim merging should be:

- explicit;
- attributable;
- auditable;
- reversible.

---

# 14. Determinism Does Not Eliminate Judgment

The system can make reasoning reproducible without making all inputs objective.

Judgment remains in:

- claim wording;
- relevance;
- support strength;
- interpretive distance;
- independence grouping;
- context completeness;
- priors.

The correct design response is not to hide this subjectivity.

It is to make the judgment:

- explicit;
- signed;
- challengeable;
- versioned;
- auditable.

---

# 15. Audit Economics

Volunteer AI compute is not automatically valuable.

A low-quality agent may create more audit work than useful knowledge.

A future scheduler should therefore consider something like:

```text
expected epistemic value
- expected audit cost
- expected correction cost
```

rather than only:

```text
expected information gain / inference cost
```

Metrics worth preserving:

- agent/model identity;
- task type;
- acceptance rate;
- audit failure rate;
- average audit cost;
- correction cost;
- historical reliability.

---

# 16. Correlated AI Error

Two AI agents are not necessarily independent.

Agents can share:

- model family;
- training biases;
- retrieval sources;
- prompts;
- infrastructure;
- common hallucinations.

Future high-impact verification should seek diversity across:

- model families;
- retrieval paths;
- evidence sources;
- organizational principals;
- human reviewers where appropriate.

Verification independence should eventually be modeled separately from source independence.

---

# 17. Probabilities and Public UX

Exact probabilities are useful internally because they make models reproducible.

However, users may interpret:

```text
0.73
```

as:

> "The system says this is 73% true."

That is too strong.

Default public presentation should likely emphasize:

```text
leans supported
coverage: medium
stability: low
independent evidence families: 3
main unresolved issue: ...
```

Exact calculations should remain available in an advanced view.

---

# 18. Recommended Public Demo

The Watchers / ancient-text example is useful as an internal stress test.

It should not be the project's first public demonstration.

Better first demos:

## A. Citation laundering

Several articles repeat the same statistic.

The system discovers that all trace back to one press release.

The apparent independent evidence collapses into one source family.

## B. Missing qualifier

A widely quoted statistic omits a denominator, time window, or population qualifier.

The graph exposes the missing context.

## C. AI citation hallucination

An AI-generated document contains a plausible but incorrect citation.

The system verifies the citation and records the failure.

These examples demonstrate value without making the project appear fringe-adjacent.

---

# 19. Strategic Conclusion

The project should not initially attempt to become:

> a universal public truth network.

The first product hypothesis should be smaller:

> AI systems increasingly perform research whose intermediate reasoning disappears. Durable, signed, reusable evidence records can make that work cumulative and auditable.

A stronger product formulation is:

> **Verified once, reusable forever.**

The initial value proposition should not be merely that the system can check a citation, quotation, or claim. Many tools can already perform one-time checks.

The differentiator is that a successful verification becomes a durable epistemic object that another person, document, or agent can reuse and independently audit.

A single researcher or team should receive value before network effects exist.

Possible initial use cases:

1. citation verification;
2. quotation verification;
3. private investigative evidence ledgers;
4. literature tracking;
5. internal research teams;
6. public evidence graphs later.

---

# 20. Long-Term Architecture Position

The project should become an integration layer rather than attempting to replace existing infrastructure.

Possible ecosystem:

```text
             Epistemic Ledger
                    |
        +-----------+-----------+
        |           |           |
      Scite      Wikidata    OpenAlex
        |           |           |
        +------ evidence --------+
                    |
              internal graph
                    |
          scoring / audits
                    |
       +------------+------------+
       |                         |
 nanopublications             W3C PROV
 import/export               import/export
```

The likely unique contribution is the combination of:

- durable atomic evidence;
- explicit independence;
- signed agent work;
- reusable claim structure;
- auditable contributor reputation;
- deterministic replay;
- versioned scoring;
- explicit uncertainty;
- adversarial review.

---

# 21. Questions To Revisit After POC

After the initial POC works, investigate:

- Read the multi-source "knowledge provenance" nanopublication work before finalizing the P1 evidence schema.
- How closely can internal objects map to nanopublications?
- What would be required to make nanopublication export a supported P1 feature?
- Should nanopublication import create accepted records or only candidate contributions pending verification?
- Should W3C PROV be export-only or also importable?
- Can Wikidata entity IDs reduce ontology work?
- Can Scite or OpenAlex supply candidate evidence automatically?
- Can ORKG supply structured candidate claims/evidence or identifiers?
- Which lessons from legal citation-verification tools generalize outside legal research?
- Can epistemic records interoperate safely with Portable Agent Memory or similar agent-memory protocols?
- How does Rootclaim actually handle dependence and priors?
- Does Reason Commons expose an API or common schema?
- Which Proofweave protocol ideas should be adopted?
- Can ClaimReview provide public interoperability?
- What are real-world claim-deduplication failure rates?
- How expensive are audits relative to agent contributions?
- How correlated are errors across model families?
- What user-facing summary format best communicates uncertainty?
- Which narrow use case produces day-one value without a network?
- Which existing project maintainers would be worth contacting?

---

# Working Conclusion

Do not abandon the project in favor of an existing system.

Instead:

> **Build the missing integration layer, while reusing existing standards and evidence infrastructure wherever possible.**

The strongest opportunity is not another argument graph.

It is:

> **turning disposable AI research into durable, independently auditable epistemic infrastructure.**

A concise product principle to test after POC:

> **Do not sell the check. Preserve the check.**
