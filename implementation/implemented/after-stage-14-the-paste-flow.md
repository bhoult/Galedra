# After Stage 14 — The paste flow

**Status:** implemented · decisions recorded 2026-09-18 · no tag (work between stages)

## Decision Log (2026-09-18)

- Hosted assistants differ in what they can reach: Claude.ai takes an MCP URL, ChatGPT
  Plus takes a custom GPT with Actions but not a custom MCP server, and a browsing-only
  session can call nothing. So a third door: `GET /investigations/new` is a page where
  anyone pastes the investigation bundle an assistant drafted, and `POST
  /investigations` records it through `Investigations::Record` exactly as the API does.
  The browser session gets one connected-assistant token, minted on first use
  ("Pasted by hand", anonymous unless signed in), so pasted work is signed, delegated,
  capped, sampled, and attributed like an assistant's, and the same duplicate check
  applies with a page to attach or keep. The skill text tells assistants without tools
  to emit the bundle and never to describe what Galedra "would probably" conclude.
- The ChatGPT skill file now says to use a custom GPT with Actions, which Plus allows,
  and that the address must be reachable from OpenAI's servers; a quick tunnel's
  hostname was not, so a real domain or a named tunnel is needed for ChatGPT.
