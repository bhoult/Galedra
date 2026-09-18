# Galedra: check before you post

Set up as a ChatGPT plugin: Settings → Plugins → add, server URL `GALEDRA_URL/mcp/connect` with OAuth: when it connects, Galedra asks the person once whether to sign in (attributed) or continue anonymously. Clients without OAuth use `GALEDRA_URL/mcp` with no authentication. Developer mode must be on. Custom GPTs are retired; a GPT that still exists can instead import `GALEDRA_URL/api/v1/openapi.json` as an Action.

Galedra is an epistemic ledger: a signed, append-only record of claims, the evidence that bears on them, where that evidence came from, and what has happened to it since. It is not a source of truth. It gives traceable reasons for believing or doubting a claim. When the user asks you to check something in Galedra, follow this procedure.

## The procedure

1. **Search first.** Call `search_claims` (or `GET /api/v1/claims?q=`) with the key words. If an accepted claim already matches, report its card and URL and stop unless you have new evidence to add.
2. **Do your own reading.** Galedra never fetches URLs. Open the sources yourself. For each passage you rely on, keep the exact text, the link, the time you read it, and a sha256 of the bytes you read.
3. **Split the statement into atomic claims.** One assertion per claim. Type each one: `QUANTITATIVE` for numbers, `CAUSAL` for "X causes Y", `TEXTUAL` for "the source says", `NORMATIVE` for "should", and so on. A recommendation is not a fact and will not be scored. File each claim under one or two topics from the vocabulary (`list_topics`, or `GET /api/v1/topics`), such as `health/vaccines` or `politics/elections`; never invent a topic.
4. **Record it in one call.** Use `record_investigation` (or `POST /api/v1/investigations`) with sources, excerpts, claims, evidence statements, and links. Direction is `SUPPORT`, `CONTRADICT`, `QUALIFY`, or `NEUTRAL`. Interpretive steps count how far the passage is from the claim: a direct quotation is 0, a reading or inference is 1 or more. Text read off an image is a `TRANSCRIPTION`.
5. **If Galedra answers with existing similar claims**, attach your evidence to them with `attach_to` instead of creating twins. Only use `on_duplicate: create` when the claims really differ.
6. **Report.** Give the user Galedra's plain headline and its "say instead" sentence word for word when there is one, then the URL. Do not rewrite them in your own words: they are computed from the evidence and are what the user should post. Say that the result is provisional until someone audits it. If the result carries `attribution.adopt_url`, the work was recorded anonymously: tell the user that opening that link while signed in to Galedra puts it under their name, and that this is optional.

## The rules

- Your own reasoning is never evidence. Only quoted passages are. Do not write a statement you cannot point to in a source.
- Look for what would count against the claim before recording it, and record that too. A documented null search is information.
- Never record claims about identifiable private individuals.
- Never say "true", "false", or "debunked". Use Galedra's headline. Never present a probability as a percentage true; if the user asks for the number, state it with its model and snapshot, exactly as Galedra does.
- Repetition is not corroboration. If several sources trace to one origin, group them or say so.
- Every write you make is signed for you, attributed to you as an agent acting for the user (or an anonymous key), and left permanently open to audit in the public log.

## If you cannot call tools

Some hosts give you no tool to call and a browser that refuses long URLs. Then do not improvise and do not send the user to fill in a form on Galedra; they will not. Say one thing: *"Open GALEDRA_URL/assistants/new and give me what it shows for your assistant."* That page hands them a link or a line to paste back to you (a GPT to open, a connector URL, or a system prompt), and after that you can record directly. Until then, you may still read Galedra's public pages and report existing cards, and you must never describe what Galedra "would probably" conclude.

## If you can open links but not call tools

Where your host lets you fetch any URL you compose, Galedra offers a write link: build the bundle as JSON, base64url-encode it, and open `GALEDRA_URL/api/v1/investigations/record/<base64url JSON>`. No token is needed; add `?token=<assistant token>` for attribution. The same bundle twice records once. ChatGPT's browser refuses URLs longer than a few hundred characters, so this works from Claude and similar hosts, not from a plain ChatGPT chat.

## What to tell the user

"Checks out so far" means the counted evidence supports it and nothing counted contradicts it. "The evidence is mixed" means do not repeat it as settled. "Nobody has checked this yet" means exactly that. "This is not a checkable fact" means it is an opinion, a prediction, or a belief. When a narrower version holds up, offer it as what to say instead.
