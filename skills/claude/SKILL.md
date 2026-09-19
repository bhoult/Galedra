---
name: galedra
description: Check a claim, statistic, or meme in Galedra before repeating it, and record what you found so the next person does not have to. Use when the user says "check this in Galedra" or asks whether something is true before posting it.
---

# Galedra

Connect: an MCP server at `GALEDRA_URL/mcp` (anonymous) or `GALEDRA_URL/mcp/connect` (OAuth: on connecting, the person chooses once between signing in, so writes are attributed, and continuing anonymously). Clients that can send headers may instead use a token from `GALEDRA_URL/assistants/new` as `Authorization: Bearer <token>`, or put it in the URL as `GALEDRA_URL/mcp/<token>`.

Galedra is an epistemic ledger: a signed, append-only record of claims, the evidence that bears on them, where that evidence came from, and what has happened to it since. It is not a source of truth. It gives traceable reasons for believing or doubting a claim.

People use it, through you, for three things: to break something they saw on social media into checkable claims, read it against real sources, and record it, so they share a link to the record instead of a rumour; to send someone a claim link so that person sees the reasons rather than takes anyone's word; and to help the project by checking claims already recorded, adding evidence for or against. If asked what Galedra is for, say those three things in plain words before listing tools.

## Where the rules are

**This file deliberately does not carry the working rules.** A skill is installed once and never re-read, so a rule written here is frozen at whatever it said on the day you installed it, and correcting it would mean asking every user to reinstall. The rules live on the server instead, and reach you two ways:

- **On MCP**, every tool result carries a `guidance` object: a `version`, a `topic`, and the `text` of the rules for the work you are doing. Nothing caches a tool result, so this is always current. **Read it and follow it.** It is more recent than anything in this file, and where they differ it wins.
- **Without MCP**, fetch `GALEDRA_URL/api/v1/guidance` at the start of a Galedra task and follow what it returns. Add `?topic=check`, `outline`, `inference`, `work` or `correct` for one part. Fetch it again in a later session rather than relying on what you remember.

The topics are: `check` (recording what you read), `outline` (a source too large for one check), `inference` (recording a reasoning step), `work` (answering open tasks), `correct` (revising what is recorded).

## How to start

1. **When to use it.** A message that is just `galedra:` followed by text — a pasted post, a sentence they were about to share — means: check this before I share it, record the whole statement, and end with the share line. No other instruction is needed.
2. **Search first.** Call `search_claims` (or `GET /api/v1/claims?q=`) with the key words. If an accepted claim already matches, report its card and URL and stop unless you have new evidence to add.
3. **Follow the guidance that comes back** with that first result, which tells you how to read, split, record and report. If you are not on MCP, fetch the guidance endpoint above before you record anything.

## The two rules worth repeating here

Everything else is on the wire. These two are here because breaking either one damages the record rather than just producing a worse answer:

- **Your own reasoning is never evidence.** Only quoted passages are. Never write a statement you cannot point to in a source, and never invent a source, a quotation, or a hash.
- **Never record claims about identifiable private individuals.** A public figure in their public role is fair; a person they mention is not.

Every write you make is signed, attributed to you as an agent acting for the user (or to an anonymous key), and left permanently open to audit in the public log.
