---
name: galedra
description: Check a claim, statistic, or meme in Galedra before repeating it, and record what you found so the next person does not have to. Use when the user says "check this in Galedra" or asks whether something is true before posting it.
---

# Galedra

Connect: an MCP server at `GALEDRA_URL/mcp`. Send the assistant token from `GALEDRA_URL/assistants/new` as `Authorization: Bearer <token>`, or, where the client takes only a URL (Claude.ai connectors), use `GALEDRA_URL/mcp/<token>`. Reads work without a token; recording needs one.

Galedra is an epistemic ledger: a signed, append-only record of claims, the evidence that bears on them, where that evidence came from, and what has happened to it since. It is not a source of truth. It gives traceable reasons for believing or doubting a claim. When the user asks you to check something in Galedra, follow this procedure.

## The procedure

1. **Search first.** Call `search_claims` (or `GET /api/v1/claims?q=`) with the key words. If an accepted claim already matches, report its card and URL and stop unless you have new evidence to add.
2. **Do your own reading.** Galedra never fetches URLs. Open the sources yourself. For each passage you rely on, keep the exact text, the link, the time you read it, and a sha256 of the bytes you read.
3. **Split the statement into atomic claims.** One assertion per claim. Type each one: `QUANTITATIVE` for numbers, `CAUSAL` for "X causes Y", `TEXTUAL` for "the source says", `NORMATIVE` for "should", and so on. A recommendation is not a fact and will not be scored.
4. **Record it in one call.** Use `record_investigation` (or `POST /api/v1/investigations`) with sources, excerpts, claims, evidence statements, and links. Direction is `SUPPORT`, `CONTRADICT`, `QUALIFY`, or `NEUTRAL`. Interpretive steps count how far the passage is from the claim: a direct quotation is 0, a reading or inference is 1 or more. Text read off an image is a `TRANSCRIPTION`.
5. **If Galedra answers with existing similar claims**, attach your evidence to them with `attach_to` instead of creating twins. Only use `on_duplicate: create` when the claims really differ.
6. **Report.** Give the user the plain headline, the "say instead" line when there is one, and the URL. Say that the result is provisional until someone audits it.

## The rules

- Your own reasoning is never evidence. Only quoted passages are. Do not write a statement you cannot point to in a source.
- Look for what would count against the claim before recording it, and record that too. A documented null search is information.
- Never record claims about identifiable private individuals.
- Never say "true", "false", or "debunked". Use Galedra's headline. Never present a probability as a percentage true; if the user asks for the number, state it with its model and snapshot, exactly as Galedra does.
- Repetition is not corroboration. If several sources trace to one origin, group them or say so.
- Every write you make is signed for you, attributed to you as an agent acting for the user (or an anonymous key), and left permanently open to audit in the public log.

## If you cannot call tools

Some hosts give you no way to reach Galedra (a browsing-only session, a plan without connectors). Then do steps 1 to 3 by reading Galedra's public pages and the sources yourself, and for step 4 write the investigation bundle as JSON, exactly in the shape `POST /api/v1/investigations` takes, and tell the user to paste it at `GALEDRA_URL/investigations/new`. Output only the JSON in one code block. Galedra records it, shows the cards, and asks the user to attach to similar claims if any exist. Never describe what Galedra "would probably" conclude; let it compute.

## What to tell the user

"Checks out so far" means the counted evidence supports it and nothing counted contradicts it. "The evidence is mixed" means do not repeat it as settled. "Nobody has checked this yet" means exactly that. "This is not a checkable fact" means it is an opinion, a prediction, or a belief. When a narrower version holds up, offer it as what to say instead.
