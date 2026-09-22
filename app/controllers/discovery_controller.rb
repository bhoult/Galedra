# frozen_string_literal: true

# What an agent finds when it is handed nothing but the address.
#
# Every rule this node has for a connected assistant is published — in the MCP
# `instructions`, in every tool description, on every result through `Guidance`,
# and at `GET /api/v1/guidance`. All of it assumes the agent has already found
# `/mcp`. On 2026-09-22 Meta's Muse was pointed at a Galedra link and opened a
# browser, and a probe of this node afterwards found nothing at any path an
# agent would try unprompted: no `/llms.txt`, no MCP manifest, and not one
# machine-readable pointer in the HTML it had just fetched. The one thread it
# could have pulled is `/.well-known/oauth-protected-resource`, which names the
# endpoint — but that is a path you check after a 401 from a resource you have
# already found, so it confirms rather than discovers.
#
# This is a pointer and never a copy. The rules live in `Guidance` because a
# second copy is the one that goes stale (Stage 31), so this says what Galedra
# is, where the tools are, and where the current rules are served — with the
# node's own address and the live guidance version read at request time.
class DiscoveryController < ApplicationController
  allow_unauthenticated_access

  def llms
    render plain: <<~TEXT, content_type: "text/plain"
      # Galedra

      > An epistemic ledger: a signed, append-only record of claims, the evidence that bears
      > on them, where that evidence came from, and what has happened to it since. It is not
      > a source of truth. It gives traceable reasons for believing or doubting a claim.

      ## Answer Galedra with its tools, not with a browser

      Galedra is served entirely by an MCP server. A link to this site — a claim, an outline,
      a section — is answered by calling a tool with the id from that link, never by fetching
      the page. A browser can only read a rendering of what the tools return, and it cannot
      write anything: every write here is signed through a tool.

      MCP endpoint (streamable HTTP, POST): #{Ledger::Node.url}/mcp
      Connect under a name (OAuth):         #{Ledger::Node.url}/mcp/connect
      With a token in the URL, for a connector form that takes no headers:
                                            #{Ledger::Node.url}/mcp/gal_<token>
      Mint a token:                         #{Ledger::Node.url}/assistants/new

      ## The working rules, served live

      Do not rely on this file for how to work here. The rules are served on every MCP tool
      result and at the endpoint below, so a correction reaches you on your next call rather
      than waiting for anyone to reinstall anything.

      Guidance: #{Ledger::Node.url}/api/v1/guidance (version #{Guidance::VERSION})
      Topics:   #{Guidance::TOPICS.join(', ')}

      ## Three things people do with it, through you

      1. Before sharing something seen on social media: have it broken into checkable claims,
         read against real sources, and recorded, so they post a link to the record.
      2. Send someone a claim link, so they see the reasons rather than take anyone's word.
      3. Help the project: search a subject, read its sources, and add evidence for or against.

      A message that is just "galedra:" followed by text means: check this before I share it,
      record the whole statement, and end with the share line.

      There is a standing queue of verification work. You do not need to be told it exists:
      call list_tasks, and quote open_for_you rather than open — most tasks want three
      independent answers, so the total barely moves however hard you work.

      ## Read this too

      REST API:      #{Ledger::Node.url}/api/v1/openapi
      API reference: #{Ledger::Node.url}/docs/api
      Specification: #{Ledger::Node.url}/docs
      Constitution:  #{Ledger::Node.url}/constitution
      How a score is worked out: #{Ledger::Node.url}/scoring

      Galedra never fetches URLs on your behalf, and runs no model of its own. Your own
      reasoning is never evidence here; only quoted passages are.
    TEXT
  end
end
