# frozen_string_literal: true

module Skills
  # Renders skills/galedra.md into one file per host format (Stage 14). The
  # source is the only place the words live; a spec fails when the generated
  # files drift from it.
  module Build
    SOURCE = Rails.root.join("skills/galedra.md")
    PLACEHOLDER = "GALEDRA_URL"

    module_function

    def source = File.read(SOURCE)

    def outputs
      {
        "skills/claude/SKILL.md" => claude,
        "skills/chatgpt/instructions.md" => chatgpt,
        "skills/generic/system-prompt.md" => generic
      }
    end

    def write!
      outputs.each do |path, text|
        full = Rails.root.join(path)
        FileUtils.mkdir_p(full.dirname)
        File.write(full, text)
      end
      outputs.keys
    end

    def stale
      outputs.reject { |path, text| File.exist?(Rails.root.join(path)) && File.read(Rails.root.join(path)) == text }.keys
    end

    def claude
      <<~MD
        ---
        name: galedra
        description: Check a claim, statistic, or meme in Galedra before repeating it, and record what you found so the next person does not have to. Use when the user says "check this in Galedra" or asks whether something is true before posting it.
        ---

        # Galedra

        Connect: an MCP server at `#{PLACEHOLDER}/mcp`. Send the assistant token from `#{PLACEHOLDER}/assistants/new` as `Authorization: Bearer <token>`, or, where the client takes only a URL (Claude.ai connectors), use `#{PLACEHOLDER}/mcp/<token>`. Reads work without a token; recording needs one.

        #{source.strip}
      MD
    end

    def chatgpt
      <<~MD
        # Galedra: check before you post

        Set up as a custom GPT (Explore GPTs → Create), which works on Plus; custom MCP connectors do not. Under Actions, import the OpenAPI document at `#{PLACEHOLDER}/api/v1/openapi.json`. Authentication: API key, Auth type Custom, header name `Authorization`, value `Bearer <token>`, with the token from `#{PLACEHOLDER}/assistants/new`. The address must be public and reachable from OpenAI's servers. Without Actions, use the paste flow below.

        #{source.strip}
      MD
    end

    def generic
      <<~MD
        # System prompt: Galedra

        You can read Galedra at `#{PLACEHOLDER}/api/v1` (OpenAPI at `#{PLACEHOLDER}/api/v1/openapi.json`) and, with a connected assistant token sent as `Authorization: Bearer <token>`, record investigations at `POST #{PLACEHOLDER}/api/v1/investigations`. If your host speaks MCP, use `#{PLACEHOLDER}/mcp` instead.

        #{source.strip}
      MD
    end
  end
end
