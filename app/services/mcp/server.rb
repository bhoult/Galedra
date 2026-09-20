# frozen_string_literal: true

module Mcp
  # A small Model Context Protocol server (Stage 14): JSON-RPC 2.0 over
  # streamable HTTP at POST /mcp. Reads are open, like the rest of the public
  # API; the two writing tools need a connected assistant's bearer token.
  # Tool descriptions carry the working rules, not just the schemas.
  class Server
    # The revision the legacy handshake announces. Era holds the full list
    # this server will serve, and which of them are modern (Stage 32).
    PROTOCOL_VERSION = Era::LEGACY
    VERSION = "0.2.0"
    SERVER_INFO = { name: "galedra", version: VERSION }.freeze
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    TOKEN_REQUIRED = -32001

    CARD_SCHEMA = { type: "object", description: "The answer card; no probability here.",
                    properties: { headline: { type: "string" }, plain: { type: "object", properties: { headline: { type: "string" }, say_instead: { type: [ "string", "null" ] } } },
                                  review_checks: { type: "string" }, labels: { type: "array", items: { type: "string" } }, model: { type: "string" }, snapshot_seq: { type: "integer" } } }.freeze
    RECORD_OUTPUT_SCHEMA = { type: "object", properties: {
      recorded: { type: "boolean" }, contributions: { type: "integer" }, tasks_opened: { type: "integer" }, snapshot_seq: { type: "integer" },
      claims: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, id: { type: "string" }, created: { type: "boolean" }, url: { type: "string" }, card: CARD_SCHEMA } } },
      existing: { type: "object", description: "Similar accepted claims per handle, when nothing was recorded" }, hint: { type: "string" }
    } }.freeze

    TOOLS = [
      { name: "search_claims", annotations: { readOnlyHint: true, openWorldHint: false }, description: "Start here. Galedra is a public, signed record of claims and the evidence behind them: check something before sharing it and post the link, send someone a claim link so they see the reasons, or contribute (record, add evidence, correct, or \"work N open tasks in Galedra\"). Every result carries Galedra's current guidance under guidance; follow it, it is fresher than this description.",
        inputSchema: { type: "object", properties: { source_id: { type: "string", description: "Instead of words: every claim with counted evidence from this source (ids from get_claim evidence)" }, query: { type: "string", description: "Words from the claim" }, limit: { type: "integer", minimum: 1, maximum: 50, default: 10 } }, required: [] },
        outputSchema: { type: "object", properties: { query: { type: "string" }, snapshot_seq: { type: "integer" }, claims: { type: "array", items: { type: "object", properties: { id: { type: "string" }, text: { type: "string" }, type: { type: "string" }, headline: { type: "string" }, plain_headline: { type: "string" }, url: { type: "string" } } } } } } },
      { name: "get_claim", annotations: { readOnlyHint: true, openWorldHint: false }, description: "The answer card for one claim: a plain headline, what to say instead when the evidence supports it, review checks, labels, counted evidence for and against, and the URL. No probability here; use explain with calculation: true for the number.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" } }, required: [ "claim_id" ] },
        outputSchema: { type: "object", properties: { id: { type: "string" }, text: { type: "string" }, type: { type: "string" }, url: { type: "string" }, card: CARD_SCHEMA, provisional_note: { type: "string" } } } },
      { name: "record_investigation", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }, description: "Record what you found, all at once: sources by link, quoted excerpts, atomic typed claims, evidence statements, and links (SUPPORT, CONTRADICT, QUALIFY, NEUTRAL) with interpretive steps. For one statement, or a source under about 3,000 words. A longer source (a transcript, a speech, a long article) goes through create_outline first, whatever number of claims you think it makes: measure the input, not your answer, because a handful of claims off two hours of talk summarises it instead of checking it. No token is needed: without one the work is recorded under an anonymous key; a connected assistant token attributes it to the user. If similar accepted claims exist the call returns them under existing and records nothing; resubmit with attach_to on those claims, or on_duplicate: create. ",
        inputSchema: { type: "object", properties: {
          statement: { type: "string", description: "The exact text the person wanted checked, as they would post it (the meme's words, the sentence they were about to share). Shown at the top of the shareable page." },
          sources: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, type: { type: "string", enum: Source::TYPES }, title: { type: "string" }, url: { type: "string" }, content_hash: { type: "string", description: "Optional: sha256:<hex> of the page bytes, only if you had the bytes. If your host gave you rendered text, omit it; never invent one." }, retrieved_at: { type: "string", description: "RFC 3339" }, publisher: { type: "string" }, publication_date: { type: "string" } }, required: %w[handle type title url retrieved_at] } },
          excerpts: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, source: { type: "string" }, kind: { type: "string", enum: %w[QUOTE TRANSCRIPTION] }, text: { type: "string" } }, required: %w[handle source text] } },
          claims: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, text: { type: "string" }, type: { type: "string", enum: Claim::TYPES }, topics: { type: "array", description: "One or two subjects from the vocabulary, e.g. science/neuroscience", items: { type: "string", enum: Topics.all } }, attach_to: { type: "string", description: "An existing claim id instead of text and type. Every claim the statement makes goes in this one call: ones Galedra already holds (from search_claims) go in by attach_to, with or without new evidence, so the check page and share line cover the whole statement" }, section: { type: "string", description: "A section id from create_outline: the claim is filed there. Use it when recording one leaf of a large source; the share line then covers the whole outline" } }, required: [ "handle" ] } },
          evidence: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, excerpt: { type: "string" }, statement: { type: "string", description: "One plain sentence, at most 25 words, that a stranger could read aloud; it may become the card's say-instead line" }, observation_type: { type: "string", enum: EvidenceItem::OBSERVATION_TYPES } }, required: %w[handle excerpt statement] } },
          links: { type: "array", items: { type: "object", properties: { evidence: { type: "string" }, claim: { type: "string" }, direction: { type: "string", enum: EvidenceClaimLink::DIRECTIONS }, strength: { type: "string", enum: EvidenceClaimLink::STRENGTHS }, steps: { type: "integer", minimum: 0, maximum: EvidenceClaimLink::MAX_STEPS }, note: { type: "string" } }, required: %w[evidence claim direction] } },
          groups: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, type: { type: "string", enum: IndependenceGroup::TYPES }, members: { type: "array", items: { type: "string" } } }, required: %w[handle members] } },
          on_duplicate: { type: "string", enum: %w[ask create], default: "ask" }
        }, required: [ "claims" ] },
        outputSchema: RECORD_OUTPUT_SCHEMA },
      { name: "create_outline", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        description: "For any source over about 3,000 words (a podcast transcript, a speech, a sermon, a long article), however few claims you think it makes, and whether or not you already hold its whole text. Record the structure first: the source by link, an outline of sections nested like a table of contents (leaves of two to eight minutes or 300 to 800 words). Every leaf carries a locator and two pieces of text over that same span: an anchor, its first words quoted exactly, at most 300 characters, which is hashed and checked against the source; and a reading, the leaf's whole text as you read it, cleaned into paragraphs with plain transcription errors corrected, which is what a person reads here. A reading is your transcription, not a quotation, and Galedra shows it as yours. One extraction task opens per leaf so other volunteers can take the work in pieces. Then ask the person whether you should start on the research yourself; if yes, do the first pass: record leaf by leaf with record_investigation, giving each claim its section and the evidence for it, so the claims are scored at once and the person can post the link without waiting. A speech or an episode never gets a verdict, only counts by state.",
        inputSchema: { type: "object", properties: {
          statement: { type: "string", description: "The title and link of what is being checked, as the person gave it (not the text)" },
          source: { type: "object", properties: { type: { type: "string", enum: Source::TYPES }, title: { type: "string" }, url: { type: "string" }, retrieved_at: { type: "string", description: "RFC 3339" }, publisher: { type: "string" }, creator: { type: "string" }, publication_date: { type: "string" }, content_hash: { type: "string" } }, required: %w[type title url retrieved_at] },
          parent_section_id: { type: "string", description: "Instead of source: extend an existing outline under this section" },
          sections: { type: "array", description: "One root for a new outline, with nested sections: {handle, heading, locator?, anchor?, reading?, sections?}", items: { type: "object", properties: { handle: { type: "string" }, heading: { type: "string" }, locator: { type: "object", description: "{type: TIME_RANGE|CHAR_RANGE|PAGE|LINE_RANGE|SECTION, ...} e.g. {type: TIME_RANGE, start: \"00:41:10\", end: \"00:47:30\"}" }, anchor: { type: "string", description: "The first words of the leaf, quoted EXACTLY as the source has them, at most 300 characters. This is hashed and checked against the source, so never clean it" }, reading: { type: "string", description: "The leaf's whole text as you read it. Break it into paragraphs where the subject changes or another speaker begins, correct plain transcription errors (misheard words, mangled names, punctuation), write [unclear] for a word you cannot make out, and change nothing else: no tidying grammar, no cutting repetition, no summarising. A speaker who misspeaks stays misspoken. Leave it out rather than reconstruct it from memory" }, sections: { type: "array" } }, required: %w[handle heading] } },
          open_tasks: { type: "boolean", default: true } }, required: %w[sections] },
        outputSchema: { type: "object", properties: { recorded: { type: "boolean" }, root_id: { type: "string" }, root_url: { type: "string" }, sections: { type: "object" }, tasks_opened: { type: "integer" }, share_line: { type: "string" }, next: { type: "string" } } } },
      { name: "record_inference", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        description: "Record a step of reasoning: because these claims hold (and those fail), this conclusion follows. Every premise and the conclusion must be recorded claims with their own evidence. An inference is interpretation, never evidence: it changes no assessment. It is shown on the claims, and a different principal reviews whether the step is valid. Give the rule in a sentence.",
        inputSchema: { type: "object", properties: { conclusion_claim_id: { type: "string" }, premises: { type: "array", minItems: Inference::MIN_PREMISES, maxItems: Inference::MAX_PREMISES, items: { type: "object", properties: { claim: { type: "string", description: "a claim id" }, polarity: { type: "string", enum: InferencePremise::POLARITIES, default: "HOLDS" } }, required: %w[claim] } },
                                                    type: { type: "string", enum: Inference::TYPES }, rule: { type: "string", description: "the warrant, at most 500 characters" }, strength: { type: "string", enum: Inference::STRENGTHS, default: "SUPPORTS" } }, required: %w[conclusion_claim_id premises type] },
        outputSchema: { type: "object", properties: { inference_id: { type: "string" }, url: { type: "string" }, note: { type: "string" } } } },
      { name: "get_outline", annotations: { readOnlyHint: true, openWorldHint: false },
        description: "An outline (or one section of it) as a tree with the claims filed under each section and counts by assessment state. Counts only; a section never has a probability.",
        inputSchema: { type: "object", properties: { section_id: { type: "string" }, depth: { type: "integer", default: 2 } }, required: %w[section_id] } },
      { name: "add_evidence", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }, description: "Attach one quoted passage to an existing claim as evidence for, against, or qualifying it. No token needed; anonymous without one. ",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" }, source: { type: "object", properties: { type: { type: "string", enum: Source::TYPES }, title: { type: "string" }, url: { type: "string" }, content_hash: { type: "string", description: "Optional: sha256:<hex> of the page bytes, only if you had them" }, retrieved_at: { type: "string" }, publisher: { type: "string" } }, required: %w[type title url retrieved_at] }, excerpt: { type: "string" }, excerpt_kind: { type: "string", enum: %w[QUOTE TRANSCRIPTION], default: "QUOTE" }, statement: { type: "string" }, direction: { type: "string", enum: EvidenceClaimLink::DIRECTIONS }, strength: { type: "string", enum: EvidenceClaimLink::STRENGTHS, default: "DIRECT" }, steps: { type: "integer", default: 0 }, note: { type: "string" } }, required: %w[claim_id source excerpt statement direction] },
        outputSchema: RECORD_OUTPUT_SCHEMA },
      { name: "explain", annotations: { readOnlyHint: true, openWorldHint: false }, description: "Why a claim stands where it does: strongest counted support and contradiction, suppressed dependents, review gaps, and what would most change it. With calculation: true, also the probability, always stated with its model and snapshot; never present it as a percentage true.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" }, calculation: { type: "boolean", default: false } }, required: [ "claim_id" ] },
        outputSchema: { type: "object", properties: { url: { type: "string" }, why: { type: "object" }, calculation: { type: "object", properties: { assessment_state: { type: "string" }, probability: { type: [ "string", "null" ] }, model: { type: "string" }, snapshot_seq: { type: "integer" }, stated_as: { type: [ "string", "null" ] } } } } } },
      { name: "share_card", annotations: { readOnlyHint: true, openWorldHint: false }, description: "A link and image for pasting into a social post: the plain headline, what to say instead, and the claim URL. The card never shows a number.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" } }, required: [ "claim_id" ] },
        outputSchema: { type: "object", properties: { url: { type: "string" }, card_url: { type: "string" }, image_url: { type: "string" }, headline: { type: "string" }, say_instead: { type: [ "string", "null" ] }, text: { type: "string" } } } },
      { name: "tag_claim", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }, description: "File an existing claim under one to five topics from the vocabulary (e.g. health/vaccines). A tag is a signed, challengeable judgment; on someone else's claim it waits for acceptance. Never invent a topic; list_topics shows the vocabulary.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" }, topics: { type: "array", items: { type: "string", enum: Topics.all }, minItems: 1, maxItems: Topics::MAX_PER_CLAIM }, note: { type: "string" } }, required: %w[claim_id topics] },
        outputSchema: { type: "object", properties: { claim_id: { type: "string" }, topics: { type: "array", items: { type: "string" } }, status: { type: "string" }, url: { type: "string" } } } },
      { name: "list_topics", annotations: { readOnlyHint: true, openWorldHint: false }, description: "The topic vocabulary: two levels of subjects with the paths to use in record_investigation and tag_claim.",
        inputSchema: { type: "object", properties: {} },
        outputSchema: { type: "object", properties: { topics: { type: "array", items: { type: "object", properties: { path: { type: "string" }, label: { type: "string" }, children: { type: "array", items: { type: "object" } } } } } } } },
      # Stage 18: working open tasks from a connector.
      { name: "list_tasks", annotations: { readOnlyHint: true, openWorldHint: false },
        description: "What needs doing in Galedra: open verification tasks by type and domain, and the top few by priority with the claim they check. No token needed. To do them, the person says \"work N open tasks in Galedra\" and you call next_task then submit_task N times.",
        inputSchema: { type: "object", properties: { types: { type: "array", items: { type: "string", enum: Tasks::Types::ALL } }, domains: { type: "array", items: { type: "string" } }, section_id: { type: "string", description: "Only work under this outline or section" }, limit: { type: "integer", default: 5 } } },
        outputSchema: { type: "object", properties: { open: { type: "integer" }, by_type: { type: "object" }, by_domain: { type: "object" }, next: { type: "array" }, how: { type: "string" } } } },
      { name: "next_task", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
        description: "Lease the next open task for this assistant: highest priority first, never one on a claim your own principal recorded. Returns the task in plain form with answer_with saying exactly what to send to submit_task, and the lease expiry. Do the reading yourself. Optional filters: types, domains, claim_id. Needs a connected (non-anonymous) assistant.",
        inputSchema: { type: "object", properties: { types: { type: "array", items: { type: "string", enum: Tasks::Types::ALL } }, domains: { type: "array", items: { type: "string" } }, claim_id: { type: "string" }, section_id: { type: "string", description: "Only work under this outline or section (from an outline URL the person gave)" } } },
        outputSchema: { type: "object", properties: { available: { type: "boolean" }, reason: { type: "string" }, task_id: { type: "string" }, task_type: { type: "string" }, domain: { type: "string" }, objective: { type: "string" }, target: { type: "object" }, context: { type: "object" }, outcomes: { type: "array", items: { type: "string" } }, lease_expires_at: { type: "string" }, task_url: { type: "string" }, answer_with: { type: "string" }, rules: { type: "string" } } } },
      { name: "submit_task", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        description: "Answer a task you leased with next_task: task_id, outcome (one of the task's outcomes), and answer in the record_investigation vocabulary with handles: sources, excerpts, claims, edges, evidence, links, groups, supersede. Use claim: \"target\" for the task's claim and excerpt: \"packet\" for the task's passage. An empty answer with NONE_FOUND, NONE_MATERIAL, INDEPENDENT, NO_CLAIMS, or CANNOT_DETERMINE is a valid result. ",
        inputSchema: { type: "object", properties: { task_id: { type: "string" }, outcome: { type: "string" },
                                                     answer: { type: "object", properties: {
                                                       sources: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, type: { type: "string", enum: Source::TYPES }, title: { type: "string" }, url: { type: "string" }, retrieved_at: { type: "string" }, publisher: { type: "string" }, publication_date: { type: "string" } }, required: %w[handle type title url retrieved_at] } },
                                                       excerpts: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, source: { type: "string" }, text: { type: "string" }, kind: { type: "string", enum: %w[QUOTE TRANSCRIPTION], default: "QUOTE" } }, required: %w[handle source text] } },
                                                       claims: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, text: { type: "string" }, type: { type: "string", enum: Claim::TYPES } }, required: %w[handle text type] } },
                                                       edges: { type: "array", items: { type: "object", properties: { from: { type: "string" }, to: { type: "string" }, type: { type: "string", enum: ClaimEdge::TYPES, default: "NARROWS" } }, required: %w[from to] } },
                                                       evidence: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, excerpt: { type: "string", description: "an excerpt handle, or \"packet\"" }, statement: { type: "string", description: "one plain sentence, at most 25 words" }, observation_type: { type: "string", enum: EvidenceItem::OBSERVATION_TYPES } }, required: %w[handle excerpt statement] } },
                                                       links: { type: "array", items: { type: "object", properties: { evidence: { type: "string" }, claim: { type: "string", description: "a claim handle, a claim id, or \"target\"" }, direction: { type: "string", enum: EvidenceClaimLink::DIRECTIONS }, strength: { type: "string", enum: EvidenceClaimLink::STRENGTHS, default: "DIRECT" }, steps: { type: "integer", default: 0 }, note: { type: "string" } }, required: %w[evidence claim direction] } },
                                                       groups: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, type: { type: "string", enum: IndependenceGroup::TYPES }, description: { type: "string" }, members: { type: "array", items: { type: "string" }, description: "evidence_item_id values from the packet" } }, required: %w[handle type members] } },
                                                       inferences: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, conclusion: { type: "string", description: "a claim handle, id, or \"target\" for an inference review" }, premises: { type: "array", items: { type: "object", properties: { claim: { type: "string" }, polarity: { type: "string", enum: InferencePremise::POLARITIES } }, required: %w[claim] } }, type: { type: "string", enum: Inference::TYPES }, rule: { type: "string" }, strength: { type: "string", enum: Inference::STRENGTHS } }, required: %w[handle conclusion premises] } },
                                                       supersede: { type: "array", items: { type: "object", properties: { link_id: { type: "string" }, direction: { type: "string", enum: EvidenceClaimLink::DIRECTIONS }, strength: { type: "string", enum: EvidenceClaimLink::STRENGTHS }, steps: { type: "integer" }, reason: { type: "string" } }, required: %w[link_id direction] } } } } },
                       required: %w[task_id outcome] },
        outputSchema: { type: "object", properties: { task_id: { type: "string" }, contribution_id: { type: "string" }, accepted: { type: "boolean" }, status: { type: "string" }, note: { type: "string" }, items: { type: "integer" }, task_url: { type: "string" }, claim: { type: "object" } } } },
      { name: "release_task", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        description: "Give back a task you leased and will not finish, so someone else can take it.",
        inputSchema: { type: "object", properties: { task_id: { type: "string" } }, required: [ "task_id" ] },
        outputSchema: { type: "object", properties: { task_id: { type: "string" }, status: { type: "string" } } } },
      # Stage 19: corrections. Own work is accepted at once; someone else's is a proposal.
      { name: "revise_claim", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
        description: "Correct a claim: a revised claim replaces it and the old one is marked superseded, pointing forward (nothing is deleted). On your own person's claim it takes effect now and the counted evidence links are carried onto the revision. On someone else's it is recorded as a proposal that waits for that person's acceptance; say so, never say it was fixed. Give a reason.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" }, text: { type: "string", description: "the corrected claim, one atomic assertion" }, type: { type: "string", enum: Claim::TYPES }, reason: { type: "string" }, topics: { type: "array", items: { type: "string" } }, carry_links: { type: "boolean", default: true } }, required: %w[claim_id text reason] },
        outputSchema: { type: "object", properties: { accepted: { type: "boolean" }, status: { type: "string" }, note: { type: "string" }, contribution_id: { type: "string" }, old_claim_id: { type: "string" }, new_claim_id: { type: "string" }, url: { type: "string" }, carried_links: { type: "integer" }, card: CARD_SCHEMA } } },
      { name: "merge_claims", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        description: "Fold a duplicate claim into another: from_claim_id is marked merged into into_claim_id once accepted. Accepted now when both are your own person's; otherwise a proposal for their principal. Reversible by a later invalidation. Give a reason.",
        inputSchema: { type: "object", properties: { from_claim_id: { type: "string" }, into_claim_id: { type: "string" }, reason: { type: "string" } }, required: %w[from_claim_id into_claim_id reason] },
        outputSchema: { type: "object", properties: { accepted: { type: "boolean" }, status: { type: "string" }, note: { type: "string" }, contribution_id: { type: "string" } } } },
      { name: "revise_link", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
        description: "Revise an evidence link (its direction, strength, or interpretive steps) by id from get_claim's evidence. Your own link is revised now; someone else's is a proposal. Give a reason.",
        inputSchema: { type: "object", properties: { link_id: { type: "string" }, direction: { type: "string", enum: EvidenceClaimLink::DIRECTIONS }, strength: { type: "string", enum: EvidenceClaimLink::STRENGTHS }, steps: { type: "integer" }, reason: { type: "string" } }, required: %w[link_id direction reason] },
        outputSchema: { type: "object", properties: { accepted: { type: "boolean" }, status: { type: "string" }, note: { type: "string" }, contribution_id: { type: "string" }, new_link_id: { type: "string" } } } },
      { name: "open_task", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        description: "Hand a doubt to a different principal as a blind task: OPPOSING_EVIDENCE_SEARCH, QUALIFIER_CHECK, SOURCE_INDEPENDENCE_CHECK (sources that share an origin), or EVIDENCE_VERIFICATION with the location_id of the passage (from get_claim's evidence) when a quoted passage looks wrong. An open task of the same kind is returned rather than duplicated. You cannot work a task you opened.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" }, type: { type: "string", enum: Corrections::TASK_TYPES }, location_id: { type: "string" } }, required: %w[claim_id type] },
        outputSchema: { type: "object", properties: { task_id: { type: "string" }, created: { type: "boolean" }, task_type: { type: "string" }, status: { type: "string" }, url: { type: "string" } } } },
      { name: "list_proposals", annotations: { readOnlyHint: true, openWorldHint: false },
        description: "Pending corrections: on one claim (claim_id), or on every claim of your own person when no claim is given. Each says what it would change, who proposed it, and whether you may accept it. Use when the person asks to review corrections proposed on their claims.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" } } },
        outputSchema: { type: "object", properties: { proposals: { type: "array", items: { type: "object" } }, how: { type: "string" } } } },
      { name: "accept_proposal", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        description: "Accept a pending correction by contribution_id (from list_proposals), on behalf of your person. Allowed for the principal of the claims it touches, for anyone named when that principal is anonymous, and for moderators; never for the proposer's own principal. For a revised claim, the counted links are carried onto the revision. Leaving a proposal pending is how it is declined.",
        inputSchema: { type: "object", properties: { contribution_id: { type: "string" }, carry_links: { type: "boolean", default: true } }, required: [ "contribution_id" ] },
        outputSchema: { type: "object", properties: { accepted: { type: "boolean" }, contribution_id: { type: "string" }, acceptance_id: { type: "string" }, carried_links: { type: "integer" } } } },
      # What an assistant could not do (owner request): a way to say so, and to know it can.
      { name: "request_feature", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        description: "Tell Galedra's maintainers what you could not do: use it whenever these tools cannot do what the person asked, or a refusal seems wrong, before you tell the person. Say what they asked, what you needed, and the tool or field you expected. Read by maintainers only; never shown to other assistants or the public.",
        inputSchema: { type: "object", properties: { asked: { type: "string", description: "what the person asked for, in a sentence" }, needed: { type: "string", description: "what you needed and could not do" }, expected: { type: "string", description: "the tool or field you expected, if any" }, context_tool: { type: "string", description: "the tool you were using" }, last_error: { type: "string", description: "the error code you got, if any" } }, required: %w[asked needed] },
        outputSchema: { type: "object", properties: { recorded: { type: "boolean" }, request_id: { type: "string" }, repeat: { type: "boolean" }, note: { type: "string" } } } },
      { name: "report_bug", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        description: "Tell Galedra's maintainers that something went wrong: a tool answered with an error that makes no sense, a result contradicted itself, a page or link was broken, or the person reports a problem with Galedra. Say what happened, what you expected, and how to make it happen again. Read by maintainers only; never shown to other assistants or the public. For something the tools simply cannot do, use request_feature instead.",
        inputSchema: { type: "object", properties: { happened: { type: "string", description: "what went wrong, in a sentence or two" }, expected: { type: "string", description: "what should have happened" }, steps: { type: "string", description: "the calls or clicks that make it happen again" }, url: { type: "string", description: "the page or claim URL involved, if any" }, context_tool: { type: "string", description: "the tool you were using" }, last_error: { type: "string", description: "the error code or message you got, if any" } }, required: %w[happened] },
        outputSchema: { type: "object", properties: { recorded: { type: "boolean" }, report_id: { type: "string" }, repeat: { type: "boolean" }, note: { type: "string" } } } },
      # Content review (owner request, 2026-09-19): free text people and assistants added, checked for offensive content.
      { name: "next_content_review", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
        description: "Lease the next piece of free text awaiting review for offensive content (a bug report, a feature request, an affiliation request, or the reason on someone's personal view). Returns the untrusted text and the rules. Part of \"work N open tasks in Galedra\": take these when next_task has nothing, or when asked. Needs a connected, non-anonymous assistant.",
        inputSchema: { type: "object", properties: {} },
        outputSchema: { type: "object", properties: { available: { type: "boolean" }, review_id: { type: "string" }, kind: { type: "string" }, field: { type: "string" }, untrusted_text: { type: "string" }, rules: { type: "string" }, answer_with: { type: "string" } } } },
      { name: "submit_content_review", annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
        description: "Answer a content review you leased: outcome CLEAN or OFFENSIVE with a short reason. OFFENSIVE redacts the text everywhere it is shown; the original stays with the admins, who can restore it. Judge only by the rules you were given; disagreement is never offensive.",
        inputSchema: { type: "object", properties: { review_id: { type: "string" }, outcome: { type: "string", enum: %w[CLEAN OFFENSIVE] }, reason: { type: "string" } }, required: %w[review_id outcome] },
        outputSchema: { type: "object", properties: { review_id: { type: "string" }, status: { type: "string" }, note: { type: "string" } } } },
      { name: "next_affiliation_review", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
        description: "The next affiliation someone asked to add to the vocabulary (a group a person counts themselves in: Democrat, Atheist, Millennial …) that your principal has not judged and did not ask for. Returns what was asked, the deduplicator's proposal, the vocabulary, and the rules. Part of \"work N open tasks in Galedra\". Needs a connected, non-anonymous assistant.",
        inputSchema: { type: "object", properties: {} },
        outputSchema: { type: "object", properties: { available: { type: "boolean" }, normalized: { type: "string" }, asked_for: { type: "string" }, people: { type: "integer" }, proposal: { type: "object" }, vocabulary: { type: "array" }, rules: { type: "string" }, consensus: { type: "object" }, answer_with: { type: "string" } } } },
      { name: "submit_affiliation_review", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        description: "Your verdict on an affiliation request: MERGE with slug (it is an existing affiliation under another name), ADD with label and group_slug (a real affiliation the vocabulary lacks), or DECLINE (not an affiliation, a slur, a joke, or a private individual). Verdicts from different principals settle it; the requester's own never counts.",
        inputSchema: { type: "object", properties: { normalized: { type: "string" }, verdict: { type: "string", enum: %w[MERGE ADD DECLINE] }, slug: { type: "string" }, label: { type: "string" }, group_slug: { type: "string" }, reason: { type: "string" } }, required: %w[normalized verdict] },
        outputSchema: { type: "object", properties: { normalized: { type: "string" }, settled: { type: "boolean" }, status: { type: "string" }, became: { type: "string" }, consensus: { type: "object" }, note: { type: "string" } } } },
      # OpenAI's read-and-fetch connector shape (ChatGPT search and deep research): a
      # `search` returning ids, titles, and URLs, and a `fetch` returning one document.
      { name: "search", annotations: { readOnlyHint: true, openWorldHint: false }, description: "Search Galedra's accepted claims. Returns ids, titles (the claim text with its plain headline), and URLs. Use fetch on an id for the full card, evidence, and why.",
        inputSchema: { type: "object", properties: { query: { type: "string" } }, required: [ "query" ] },
        outputSchema: { type: "object", properties: { results: { type: "array", items: { type: "object", properties: { id: { type: "string" }, title: { type: "string" }, url: { type: "string" } } } } } } },
      { name: "fetch", annotations: { readOnlyHint: true, openWorldHint: false }, description: "Fetch one Galedra claim by id: the answer card in plain words, what to say instead, review checks, the strongest evidence for and against, and the URL. Provisional until audited; never a percentage true.",
        inputSchema: { type: "object", properties: { id: { type: "string" } }, required: [ "id" ] },
        outputSchema: { type: "object", properties: { id: { type: "string" }, title: { type: "string" }, text: { type: "string" }, url: { type: "string" }, metadata: { type: "object" } } } }
    ].freeze

    def initialize(token:, base_url:, read_only: false)
      @token = token
      @base_url = base_url
      @read_only = read_only
    end

    # Returns [http_status, body_or_nil]. `era` says which revision this one
    # request speaks; it defaults to legacy so every existing caller, and every
    # spec written before Stage 32, behaves exactly as it did.
    def handle(message, era: Era.legacy)
      return [ 400, error(nil, INVALID_REQUEST, "expected a JSON-RPC 2.0 request object") ] unless message.is_a?(Hash) && message["jsonrpc"] == "2.0"

      id = message["id"]
      method = message["method"].to_s
      params = message["params"].is_a?(Hash) ? message["params"] : {}
      return [ era.error_status, { jsonrpc: "2.0", id: id, error: era.error } ] if era.error
      return [ 202, nil ] if method.start_with?("notifications/")

      result = case method
      when "initialize" then initialize_result
      when "server/discover" then discover_result
      when "ping" then {}
      # ttlMs and cacheScope are caching hints from protocol 2026-07-28. A
      # 2025-06-18 client ignores fields it does not know; a later one honours
      # them. Zero is the honest value here and pairs with listChanged: false
      # above: this server has no stream to push notifications/tools/list_changed
      # on (GET /mcp is 405), so a client that cached a tool description would
      # never be told it had changed. Telling it not to cache is the only way a
      # corrected description reaches an assistant without a reconnect. The rules
      # themselves do not depend on this: they ride on every result (Stage 31).
      when "tools/list" then { tools: TOOLS, ttlMs: 0, cacheScope: "public" }
      when "tools/call" then call_tool(params)
      else
        # A modern server answers an unknown method with 404, so a client can
        # tell "this server does not speak MCP here" from "it does, but not
        # that method". Legacy keeps 200, which is what its clients expect.
        return [ era.modern? ? 404 : 200, error(id, METHOD_NOT_FOUND, "unknown method #{method}") ]
      end
      [ 200, { jsonrpc: "2.0", id: id, result: decorate(result, era) } ]
    rescue Ledger::Rejected => e
      [ 200, tool_error(id, e.errors) ]
    rescue Assistants::CapReached => e
      [ 200, tool_error(id, [ { code: "DAILY_CAP", path: "$", detail: e.message } ]) ]
    rescue ArgumentError => e
      [ 200, error(id, INVALID_PARAMS, e.message) ]
    end

    # Modern results carry resultType and identify the server per response,
    # because there is no handshake in which either could have been said. Legacy
    # results are returned untouched: an existing connector must see no change.
    def decorate(result, era)
      return result unless era.modern?

      meta = { Era::SERVER_INFO_KEY => SERVER_INFO }.merge(result[:_meta] || {})
      { resultType: "complete" }.merge(result).merge(_meta: meta)
    end

    # server/discover is what a modern client may call before anything else to
    # learn the versions, capabilities and identity a legacy client would have
    # got from the initialize handshake. Servers MUST implement it, so it is
    # answered on both paths. ttlMs is 0 for the same reason tools/list sets it:
    # nothing here can push a notification when the answer changes.
    def discover_result
      { supportedVersions: Era::SUPPORTED,
        capabilities: { tools: { listChanged: false } },
        instructions: instructions,
        ttlMs: 0, cacheScope: "public",
        _meta: { Era::SERVER_INFO_KEY => SERVER_INFO } }
    end

    def instructions = Guidance.join(Guidance::PURPOSE, *Guidance::TOPICS.map { |t| Guidance.for(t) })

    def initialize_result
      { protocolVersion: PROTOCOL_VERSION, capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER_INFO, instructions: instructions }
    end

    # Guidance travels in results, which no host caches, rather than in tool
    # descriptions and the initialize instructions, which are read once per
    # connection and frozen until the next one. The words live in Guidance,
    # which GET /api/v1/guidance serves too, so a rule is fixed in one place and
    # reaches every connected assistant on its next call (Stage 31).
    GUIDANCE_FOR = { "search_claims" => :check, "search" => :check, "get_claim" => :check, "fetch" => :check, "record_investigation" => :check, "add_evidence" => :check,
                     "create_outline" => :outline, "get_outline" => :outline,
                     "record_inference" => :inference,
                     "list_tasks" => :work, "next_task" => :work, "submit_task" => :work, "next_content_review" => :work, "submit_content_review" => :work, "next_affiliation_review" => :work, "submit_affiliation_review" => :work,
                     "list_proposals" => :correct, "revise_claim" => :correct, "merge_claims" => :correct, "revise_link" => :correct, "open_task" => :correct, "accept_proposal" => :correct }.freeze

    def guidance(name)
      topic = GUIDANCE_FOR[name]
      topic && { version: Guidance::VERSION, topic: topic, text: Guidance.for(topic) }
    end

    def call_tool(params)
      name = params["name"].to_s
      args = params["arguments"].is_a?(Hash) ? params["arguments"] : {}
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      unless TOOLS.any? { |t| t[:name] == name }
        log_call(name, args, started, outcome: "unknown_tool")
        raise ArgumentError, "unknown tool #{name}"
      end

      begin
        data = send(:"tool_#{name}", args)
      rescue Ledger::Rejected => e
        log_call(name, args, started, outcome: "refused", codes: e.errors.map { |x| x[:code] || x["code"] })
        raise
      rescue ArgumentError => e
        log_call(name, args, started, outcome: "bad_arguments", detail: e.message)
        raise
      end
      log_call(name, args, started, outcome: outcome_of(name, data))
      data = data.merge(guidance: guidance(name)) if data.is_a?(Hash) && guidance(name)
      { content: [ { type: "text", text: JSON.pretty_generate(data) } ], structuredContent: data, isError: false }
    end

    def tool_search_claims(args)
      query = args["query"].to_s.strip
      raise ArgumentError, "query or source_id is required" if query.empty? && args["source_id"].blank?

      seq = Contribution.maximum(:seq) || 0
      model = Scoring::Registry.default_model
      scope = Claim.counted_at(seq).where.not(id: Governance::Quarantines.quarantined_claim_ids)
                   .where("to_tsvector('english', canonical_text) @@ plainto_tsquery('english', ?)", query)
                   .order(created_seq: :desc).limit(args.fetch("limit", 10).to_i.clamp(1, 50))
      if args["source_id"].present?
        scope = Claim.counted_at(seq).where.not(id: Governance::Quarantines.quarantined_claim_ids)
                     .where(id: EvidenceClaimLink.joins(evidence_item: :source_location).where(source_locations: { source_id: args["source_id"].to_s }).select(:claim_id))
                     .order(created_seq: :desc).limit(50)
      end
      claims = scope.to_a
      claims = Claims::Duplicates.candidates(query, limit: 10).to_a if claims.empty? && args["source_id"].blank?
      total = Claim.counted_at(seq).count
      result = { query: query, snapshot_seq: seq, total_accepted_claims: total, claims: claims.map { |c| brief(c, seq, model) }, caller: caller_note }
      result[:note] = "No recorded claim matches. Galedra holds #{total} accepted #{'claim'.pluralize(total)} in total, so this is more likely unrecorded than mis-searched. Offer to investigate and record it." if claims.empty?
      result
    end

    def tool_get_claim(args)
      claim = find_claim(args)
      ClaimReference.count!(claim.id, "LOOKED_UP")
      seq = Contribution.maximum(:seq)
      model = Scoring::Registry.default_model
      card = Cards::ClaimCard.call(claim, seq, model)
      evidence = Graph::Presenter.claim_evidence(claim, seq) if Graph::Presenter.respond_to?(:claim_evidence)
      revision = Corrections.status(claim, seq)
      { id: claim.id, text: claim.canonical_text, type: claim.claim_type, url: url_for(claim), card: card, topics: Topics.for_claim(claim, seq), caller: caller_note,
        share_url: "#{url_for(claim)}/card", share_line: share_line_for(claim, card),
        evidence: evidence, revision: revision.merge(superseded_by: revision[:superseded_by]&.merge(url: "#{@base_url}/claims/#{revision[:superseded_by][:claim_id]}")),
        references: ClaimReference.totals(claim.id),
        sections: Sections::Tree.placements_for(claim, seq).map { |s| { id: s.id, path: s.path(seq), url: "#{@base_url}/sections/#{s.id}" } },
        inferences: Inferences::View.for_claim(claim, seq, model),
        provisional_note: "Everything here stays open to audit; treat it as provisional." }
    end

    def tool_create_outline(args)
      require_token!
      Investigations::Outline.call(@token, args, base_url: @base_url)
    end

    def tool_record_inference(args)
      require_token!
      inference = Inferences::Record.call(@token, conclusion_claim_id: args["conclusion_claim_id"], premises: args["premises"], inference_type: args["type"], rule: args["rule"], strength: args["strength"])
      { inference_id: inference.id, url: "#{@base_url}/claims/#{inference.conclusion_claim_id}#inferences", note: "#{Inference::NOTE} A review task is open for a different principal." }
    end

    def tool_get_outline(args)
      section = Section.find_by(id: args["section_id"].to_s) or raise Ledger::Rejected.new([ { code: "NOT_FOUND", path: "$.section_id", detail: "no such section" } ])
      seq = Contribution.maximum(:seq)
      tree = Sections::Tree.call(section, seq, depth: args.fetch("depth", 2).to_i.clamp(0, Section::MAX_DEPTH))
      { section: { id: section.id, heading: section.heading, path: section.path(seq), url: "#{@base_url}/sections/#{section.id}" }, counts: tree[:counts], counts_line: Sections::Tree.counts_line(tree[:counts]),
        pending_claims: tree[:pending], tree: outline_node(tree), open_tasks: Task.where(section_id: Tasks::Lease.subtree_ids(section.id), status: %w[OPEN LEASED]).count, note: Sections::Tree::NOTE }
    end

    def outline_node(node)
      { id: node[:section].id, heading: node[:section].heading, counts_line: Sections::Tree.counts_line(node[:counts]),
        claims: node[:claims].map { |c| { id: c.id, text: c.canonical_text, state: node[:states][c.id], url: url_for(c) } },
        children: node[:children].map { |ch| outline_node(ch) } }
    end

    def tool_record_investigation(args)
      require_token!
      Investigations::Record.call(@token, args, base_url: @base_url)
    end

    def tool_add_evidence(args)
      require_token!
      claim = find_claim(args)
      source = args.fetch("source", {})
      bundle = {
        "sources" => [ source.merge("handle" => "s") ],
        "excerpts" => [ { "handle" => "x", "source" => "s", "kind" => args.fetch("excerpt_kind", "QUOTE"), "text" => args["excerpt"] } ],
        "claims" => [ { "handle" => "c", "attach_to" => claim.id } ],
        "evidence" => [ { "handle" => "e", "excerpt" => "x", "statement" => args["statement"], "observation_type" => args.fetch("observation_type", "DIRECT_TEXT") } ],
        "links" => [ { "evidence" => "e", "claim" => "c", "direction" => args["direction"], "strength" => args.fetch("strength", "DIRECT"), "steps" => args.fetch("steps", 0), "note" => args["note"] }.compact ]
      }
      Investigations::Record.call(@token, bundle, base_url: @base_url)
    end

    def tool_tag_claim(args)
      require_token!
      claim = find_claim(args)
      result = Assistants::Write.call(@token, "TAG_CLAIM", { "claim_id" => claim.id, "topics" => Array(args["topics"]), "note" => args["note"] }.compact)
      { claim_id: claim.id, topics: Array(args["topics"]), status: result.contribution.current_status, url: url_for(claim) }
    end

    def tool_list_topics(_args)
      { topics: Topics.tree.map { |t| { path: t.path, label: t.label, scope: t.scope, children: t.children.map { |c| { path: c.path, label: c.label } } } } }
    end

    def tool_explain(args)
      claim = find_claim(args)
      ClaimReference.count!(claim.id, "LOOKED_UP")
      seq = Contribution.maximum(:seq)
      model = Scoring::Registry.default_model
      why = Cards::Why.call(claim, seq, model)
      out = { url: url_for(claim), why: why }
      if args["calculation"]
        result = Scoring::Score.call(claim, seq, model)
        out[:calculation] = { assessment_state: result.assessment_state, probability: result.probability, model: model.full_name, snapshot_seq: seq,
                              stated_as: Cards::DisplayRules.stated(result.probability, model.full_name, seq),
                              review_checklist: result.review_checklist, stability: result.stability, note: "Model-conditional and reproducible, not objective; never a percentage true." }
      end
      out
    end

    def tool_search(args)
      found = tool_search_claims("query" => args["query"], "limit" => 10)
      { results: found[:claims].map { |c| { id: c[:id], title: "#{c[:plain_headline]} — #{c[:text]}", url: c[:url] } } }
    end

    def tool_fetch(args)
      claim = find_claim("claim_id" => args["id"])
      ClaimReference.count!(claim.id, "LOOKED_UP")
      seq = Contribution.maximum(:seq)
      model = Scoring::Registry.default_model
      card = Cards::ClaimCard.call(claim, seq, model)
      why = Cards::Why.call(claim, seq, model)
      revision = Corrections.status(claim, seq)
      lines = [ "Claim: #{claim.canonical_text}", "Galedra says: #{card[:plain][:headline]}" ]
      lines << "Superseded at seq #{revision[:superseded_by][:seq]} by: #{revision[:superseded_by][:text]} (#{@base_url}/claims/#{revision[:superseded_by][:claim_id]})" if revision[:superseded_by]
      lines << "Merged into #{@base_url}/claims/#{revision[:merged_into][:claim_id]}" if revision[:merged_into]
      lines << "Revises: #{revision[:revises][:text]}" if revision[:revises]
      lines << "Say instead: #{card[:plain][:say_instead]}" if card[:plain][:say_instead]
      lines << "Assessment: #{card[:headline]} under #{card[:model]} at snapshot #{seq}; review checks #{card[:review_checks]}"
      lines.concat(card[:labels])
      lines << "Strongest support: #{why[:strongest_support][:statement]}" if why[:strongest_support]
      lines << "Strongest contradiction: #{why[:strongest_contradiction][:statement]}" if why[:strongest_contradiction]
      lines << "What would most change this: #{why.dig(:what_would_most_change_this, :text)}" if why[:what_would_most_change_this]
      lines << "Provisional until audited. Model-conditional, not objective."
      lines << "Share: #{share_line_for(claim, card)}"
      { id: claim.id, title: claim.canonical_text, text: lines.join("\n"), url: url_for(claim),
        metadata: { type: claim.claim_type, assessment_state: why[:assessment_state], snapshot_seq: seq, model: model.full_name, status: revision[:status] } }
    end

    def tool_share_card(args)
      claim = find_claim(args)
      seq = Contribution.maximum(:seq)
      card = Cards::ClaimCard.call(claim, seq, Scoring::Registry.default_model)
      { url: url_for(claim), card_url: "#{url_for(claim)}/card", image_url: "#{url_for(claim)}/card.png",
        headline: card[:plain][:headline], say_instead: card[:plain][:say_instead], text: claim.canonical_text }
    end

    def tool_request_feature(args)
      raise ArgumentError, "asked and needed are required" if args["asked"].to_s.strip.empty? || args["needed"].to_s.strip.empty?
      raise Ledger::Rejected.new([ { code: "TOKEN_INVALID", path: "$", detail: "no assistant identity for this call" } ]) if @token.nil?

      request, created = FeatureRequest.record!(token: @token, asked: args["asked"], needed: args["needed"], expected: args["expected"], context_tool: args["context_tool"], last_error: args["last_error"])
      { recorded: true, request_id: request.id, repeat: !created,
        note: created ? "Recorded for the maintainers. Now tell the person plainly what you could not do; do not improvise around it." : "The same need was already on file; counted again. Tell the person plainly what you could not do." }
    end

    def tool_next_content_review(_args)
      item = ContentReview.next_for(@token)
      return { available: false, note: "Nothing awaits your review." } if item.nil?

      item.to_h.merge(available: true)
    end

    def tool_submit_content_review(args)
      raise Ledger::Rejected.new([ { code: "TOKEN_INVALID", path: "$", detail: "no assistant identity for this call" } ]) if @token.nil?

      item = ContentReview.find(args["review_id"].to_s)
      item.vote!(@token, args["outcome"].to_s, reason: args["reason"])
      note = case item.status
      when "REDACTED" then "Consensus reached: redacted. The original is kept for the admins."
      when "CLEAN" then "Consensus reached: clean."
      else "Your verdict is recorded; it waits for another principal to agree, or stands alone after #{Reviews::Consensus::ALONE_AFTER.inspect}."
      end
      { review_id: item.id, status: item.status, consensus: item.consensus, note: note }
    end

    def tool_next_affiliation_review(_args)
      request = AffiliationRequest.next_review_for(@token)
      return { available: false, note: "No affiliation request awaits your review." } if request.nil?

      AffiliationRequest.review_packet(request).merge(available: true)
    end

    def tool_submit_affiliation_review(args)
      raise Ledger::Rejected.new([ { code: "TOKEN_INVALID", path: "$", detail: "no assistant identity for this call" } ]) if @token.nil?

      normalized = args["normalized"].to_s
      winner = AffiliationRequest.vote!(@token, normalized: normalized, verdict: args["verdict"].to_s, slug: args["slug"], label: args["label"], group_slug: args["group_slug"], reason: args["reason"])
      settled = AffiliationRequest.where(normalized: normalized).where.not(status: "PENDING").first
      { normalized: normalized, settled: winner.present?, status: settled&.status || "PENDING", became: settled&.resolved_slug && Affiliations.label(settled.resolved_slug),
        consensus: Reviews::Consensus.status("AffiliationRequest", normalized),
        note: winner ? "Consensus reached and applied to every requester." : "Your verdict is recorded; it waits for another principal to agree, or stands alone after #{Reviews::Consensus::ALONE_AFTER.inspect}." }
    end

    def tool_report_bug(args)
      raise ArgumentError, "happened is required" if args["happened"].to_s.strip.empty?
      raise Ledger::Rejected.new([ { code: "TOKEN_INVALID", path: "$", detail: "no assistant identity for this call" } ]) if @token.nil?

      report, created = BugReport.record!(token: @token, happened: args["happened"], expected: args["expected"], steps: args["steps"], url: args["url"],
                                          context_tool: args["context_tool"], last_error: args["last_error"])
      { recorded: true, report_id: report.id, repeat: !created,
        note: created ? "Recorded for the maintainers. Tell the person what went wrong and that it has been reported." : "The same report was already on file; counted again. Tell the person what went wrong and that it has been reported." }
    end

    # One structured line per tool call: shapes and outcomes, never claim text or excerpts.
    def log_call(name, args, started, outcome:, codes: [], detail: nil)
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      keys = args.is_a?(Hash) ? args.keys.map(&:to_s).sort.join(",") : "-"
      who = @token.nil? ? "none" : (@token.anonymous? ? "anonymous" : "named")
      Rails.logger.info("mcp_call tool=#{name} outcome=#{outcome}#{" codes=#{codes.join('|')}" if codes.any?}#{" detail=#{detail.to_s[0, 80].inspect}" if detail} ms=#{ms} token=#{who} read_only=#{@read_only} args=#{keys}")
    end

    def outcome_of(name, data)
      return "ok" unless data.is_a?(Hash)
      return "existing" if name == "record_investigation" && data[:recorded] == false
      return "nothing_available" if name == "next_task" && data[:available] == false
      return "pending" if data.key?(:accepted) && data[:accepted] == false
      "ok"
    end

    def tool_list_tasks(args)
      Tasks::Lease.expire_stale!
      scope = Task.where(status: %w[OPEN LEASED])
      scope = scope.where(task_type: Array(args["types"]).map(&:to_s)) if args["types"].present?
      scope = scope.where(domain: Array(args["domains"]).map(&:to_s)) if args["domains"].present?
      scope = scope.where(section_id: Tasks::Lease.subtree_ids(args["section_id"].to_s)) if args["section_id"].present?
      open = scope.order(priority: :desc, created_at: :asc).to_a.select { |t| t.open_slots.positive? }
      top = open.first(args.fetch("limit", 5).to_i.clamp(1, 20)).map do |t|
        { task_id: t.id, task_type: t.task_type, domain: t.domain, priority: t.priority.to_s("F"),
          target: t.packet["target"].slice("claim_id", "claim_text", "claim_type", "source_id", "title"), url: "#{@base_url}/tasks/#{t.id}" }
      end
      { open: open.size, by_type: open.group_by(&:task_type).transform_values(&:size), by_domain: open.group_by(&:domain).transform_values(&:size), next: top,
        content_reviews_pending: ContentReview.pending.count, affiliation_reviews_pending: AffiliationRequest.pending.distinct.count(:normalized),
        by_outline: open.filter_map { |t| t.section_id && Section.find_by(id: t.section_id)&.root_id }.tally.map { |root_id, n| { root_id: root_id, heading: Section.find(root_id).heading, open: n, url: "#{@base_url}/sections/#{root_id}" } }.sort_by { |o| -o[:open] }.first(3),
        how: "Say \"work N open tasks in Galedra\": the assistant then calls next_task and submit_task N times. Leasing needs a connected, non-anonymous assistant." }
    end

    def tool_next_task(args)
      require_delegation!
      types = Array(args["types"]).map(&:to_s)
      domains = Array(args["domains"]).map(&:to_s)
      target_id = args["claim_id"].presence && find_claim("claim_id" => args["claim_id"]).id
      assignment = Tasks::Lease.next(contributor: @token.agent, delegation: @token.delegation, types: types, domains: domains, target_id: target_id, section_id: args["section_id"].presence)
      return { available: false, reason: nothing_available(types, domains, target_id) } if assignment.nil?

      { available: true }.merge(Tasks::Answer.present(assignment.task, assignment, base_url: @base_url))
    end

    def tool_submit_task(args)
      require_delegation!
      task = find_task(args)
      result = Tasks::Answer.submit(@token, task, outcome: args["outcome"], answer: args["answer"])
      accepted = result.acceptance.present?
      out = { task_id: task.id, contribution_id: result.contribution.id, accepted: accepted, status: accepted ? "ACCEPTED" : result.contribution.current_status,
              items: result.contribution.payload["ops"].size, task_url: "#{@base_url}/tasks/#{task.id}",
              note: accepted ? "Counted now, and open to audit." : "Recorded as a proposal; it counts once a different principal accepts it." }
      out[:claim] = brief(Claim.find(task.target_id), Contribution.maximum(:seq), Scoring::Registry.default_model) if task.target_type == "CLAIM"
      out
    end

    def tool_release_task(args)
      require_delegation!
      task = find_task(args)
      assignment = TaskAssignment.latest_for(task.id, @token.agent_contributor_id)
      raise Ledger::Rejected.new([ { code: "LEASE_MISSING", path: "$.task_id", detail: "this task is not leased to this assistant" } ]) if assignment.nil?

      { task_id: task.id, status: Tasks::Lease.release(assignment).status }
    end

    def tool_revise_claim(args)
      require_token!
      claim = find_claim(args)
      raise ArgumentError, "text and reason are required" if args["text"].to_s.strip.empty? || args["reason"].to_s.strip.empty?

      out = Corrections.revise_claim(@token, claim, text: args["text"], type: args["type"], reason: args["reason"], topics: Array(args["topics"]), carry_links: args.fetch("carry_links", true))
      seq = Contribution.maximum(:seq)
      { accepted: out[:accepted], status: out[:accepted] ? "ACCEPTED" : "PENDING", contribution_id: out[:contribution].id, old_claim_id: claim.id, new_claim_id: out[:claim].id,
        url: url_for(out[:claim]), carried_links: out[:carried].size, card: (Cards::ClaimCard.call(out[:claim], seq, Scoring::Registry.default_model) if out[:accepted]),
        note: out[:accepted] ? "Revised now: the old claim reads SUPERSEDED and points here." : "Recorded as a proposal; it takes effect once #{Corrections.describe_principal(claim.contribution)} (or a moderator) accepts it. Tell the person it is proposed, not fixed." }.compact
    end

    def tool_merge_claims(args)
      require_token!
      from = find_claim("claim_id" => args["from_claim_id"])
      into = find_claim("claim_id" => args["into_claim_id"])
      raise ArgumentError, "reason is required" if args["reason"].to_s.strip.empty?

      out = Corrections.merge_claims(@token, from, into, reason: args["reason"])
      { accepted: out[:accepted], status: out[:accepted] ? "ACCEPTED" : "PENDING", contribution_id: out[:contribution].id,
        note: out[:accepted] ? "Merged now." : "Recorded as a proposal awaiting the claims' principal (or a moderator). Say it is proposed, not done." }
    end

    def tool_revise_link(args)
      require_token!
      link = EvidenceClaimLink.find_by(id: args["link_id"].to_s) || raise(Ledger::Rejected.new([ { code: "NOT_FOUND", path: "$.link_id", detail: "no such link" } ]))
      raise ArgumentError, "reason is required" if args["reason"].to_s.strip.empty?

      out = Corrections.revise_link(@token, link, direction: args["direction"], strength: args["strength"], steps: args["steps"], reason: args["reason"])
      { accepted: out[:accepted], status: out[:accepted] ? "ACCEPTED" : "PENDING", contribution_id: out[:contribution].id, new_link_id: out[:link]&.id,
        note: out[:accepted] ? "Revised now; the old link no longer counts." : "Recorded as a proposal; the old link still counts until the link's principal (or a moderator) accepts this." }
    end

    def tool_open_task(args)
      require_delegation!
      claim = find_claim(args)
      out = Corrections.open_task(@token, claim, type: args["type"].to_s, location_id: args["location_id"])
      { task_id: out[:task].id, created: out[:created], task_type: out[:task].task_type, status: out[:task].status, url: "#{@base_url}/tasks/#{out[:task].id}",
        note: out[:created] ? "Opened for a different principal to work blind; you cannot lease it yourself." : "An open task of this kind already exists; returned instead of a duplicate." }
    end

    def tool_list_proposals(args)
      claim = args["claim_id"].present? ? find_claim(args) : nil
      principal = @token&.principal
      raise ArgumentError, "claim_id is required when no named assistant is connected" if claim.nil? && (principal.nil? || principal.anonymous?)

      list = claim ? Corrections.proposals(claim: claim) : Corrections.proposals(principal: principal)
      list = list.map { |x| x.merge(you_may_accept: principal.present? && Corrections.may_accept?(principal, Contribution.find(x[:contribution_id])), urls: x[:claim_ids].map { |id| "#{@base_url}/claims/#{id}" }) }
      { proposals: list, how: "accept_proposal with a contribution_id accepts one; leaving it pending declines it." }
    end

    def tool_accept_proposal(args)
      require_delegation!
      contribution = Contribution.find_by(id: args["contribution_id"].to_s) || raise(Ledger::Rejected.new([ { code: "NOT_FOUND", path: "$.contribution_id", detail: "no such contribution" } ]))
      unless Array(@token.delegation.permissions["allowed_actions"]).include?("ACCEPT")
        raise Ledger::Rejected.new([ { code: "DELEGATION_INVALID", path: "$", detail: "this connection predates acceptance rights; disconnect and reconnect at #{@base_url}/assistants/new, then try again" } ])
      end
      out = Corrections.accept!(contribution, principal: @token.principal, carry_links: args.fetch("carry_links", true)) { |action, payload| Assistants::Write.call(@token, action, payload) }
      { accepted: true, contribution_id: contribution.id, acceptance_id: out[:contribution].id, carried_links: out[:carried].size }
    end

    private

    # Who this call is attributed to, so an assistant reports it right.
    def caller_note
      return { attribution: "none", note: "No assistant identity; writes would be anonymous." } if @token.nil?
      return { attribution: "anonymous", note: "Connected anonymously; writes are recorded under an anonymous key with an adopt link." } if @token.anonymous?

      { attribution: "named", note: "Connected under the person's name#{"; read-only" if @read_only}." }
    end

    def share_line_for(claim, card)
      Investigation.share_line(headline: card[:plain][:headline], url: "#{url_for(claim)}/card", stated: card[:stated])
    end

    def find_task(args)
      id = args["task_id"].to_s
      raise ArgumentError, "task_id is required" if id.empty?

      Task.find_by(id: id) || raise(Ledger::Rejected.new([ { code: "NOT_FOUND", path: "$.task_id", detail: "no such task" } ]))
    end

    # Leasing needs a delegation with a principal someone can hold to account (Stage 18 owner decision).
    def require_delegation!
      require_token!
      return unless @token.anonymous?

      raise Ledger::Rejected.new([ { code: "TOKEN_INVALID", path: "$", detail: "working tasks needs a connected assistant with a person behind it; connect under a name at #{@base_url}/assistants/new (OAuth or a token), then try again" } ])
    end

    def nothing_available(types, domains, target_id)
      perms = @token.delegation.permissions
      allowed_types = Array(perms["allowed_task_types"])
      allowed_domains = Array(perms["domains"])
      scope = Task.where(status: %w[OPEN LEASED], task_type: (types.presence || allowed_types) & allowed_types, domain: (domains.presence || allowed_domains) & allowed_domains)
      scope = scope.where(target_id: target_id) if target_id
      open = scope.to_a.select { |t| t.open_slots.positive? }
      if open.empty?
        "no open tasks in the types (#{(types.presence || allowed_types).join(', ')}) and domains this assistant may work; nothing to do right now"
      elsif open.all? { |t| Tasks::Lease.own_target?(t, @token.principal) }
        "the only open tasks are on claims your own principal recorded; a different person's assistant must check those"
      else
        "every open task is already leased or submitted by this principal, or the daily lease limit is reached"
      end
    end

    def brief(claim, seq, model)
      card = Cards::ClaimCard.call(claim, seq, model)
      { id: claim.id, text: claim.canonical_text, type: claim.claim_type, headline: card[:headline], plain_headline: card[:plain][:headline],
        similarity: claim.try(:similarity)&.to_f&.round(2), url: url_for(claim), share_line: share_line_for(claim, card) }.compact
    end

    def find_claim(args)
      id = args["claim_id"].to_s
      raise ArgumentError, "claim_id is required" if id.empty?

      Claim.find_by(id: id) || raise(Ledger::Rejected.new([ { code: "NOT_FOUND", path: "$.claim_id", detail: "no such claim" } ]))
    end

    def url_for(claim) = "#{@base_url}/claims/#{claim.id}"

    def require_token!
      raise Ledger::Rejected.new([ { code: "INSUFFICIENT_SCOPE", path: "$", detail: "this connection was granted read-only access (galedra:read); reconnect with the galedra scope to record" } ]) if @read_only
      return if @token&.usable?

      raise Ledger::Rejected.new([ { code: "TOKEN_INVALID", path: "$", detail: "this tool writes to the log; connect an assistant at #{@base_url}/assistants/new and send its token as Authorization: Bearer" } ])
    end

    def error(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end

    def tool_error(id, errors)
      hint = "If this stopped you doing what the person asked, call request_feature with what you needed."
      { jsonrpc: "2.0", id: id, result: { content: [ { type: "text", text: (errors.map { |e| "#{e[:code] || e['code']}: #{e[:detail] || e['detail']}" } + [ hint ]).join("\n") } ],
                                          structuredContent: { errors: errors, hint: hint }, isError: true } }
    end
  end
end
