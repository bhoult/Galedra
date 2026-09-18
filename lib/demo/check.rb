# frozen_string_literal: true

module Demo
  # "Check before you post" (IMPLEMENTATION.md Stage 14): an anonymous
  # assistant records the fixture investigation, the cards come back plain,
  # a share card renders, and the log replays. Prints PASS/FAIL lines like
  # the other demos and returns the failure count.
  module Check
    BUNDLE = Rails.root.join("examples/agent/investigation.json")

    module_function

    def run(out: $stdout, base_url: ENV.fetch("LEDGER_BASE_URL", "http://localhost:3000"))
      failures = 0
      check = lambda do |label, ok, detail = nil|
        out.puts "#{ok ? 'PASS' : 'FAIL'} #{label}#{detail && !ok ? " (#{detail})" : ''}"
        failures += 1 unless ok
      end

      token, = Assistants::Connect.call(name: "Demo assistant", provider: "other")
      check.call("anonymous assistant connected with a logged delegation", token.principal.anonymous? && token.delegation.persisted?)

      bundle = JSON.parse(File.read(BUNDLE)).except("_about")
      bundle["sources"].each { |s| s["retrieved_at"] ||= Time.now.utc.iso8601 }
      result = Investigations::Record.call(token, bundle, base_url: base_url)
      check.call("investigation recorded in one call", result[:recorded] == true)
      check.call("11 contributions appended, all or nothing", result[:contributions] == 11, result[:contributions])
      check.call("verification tasks opened at raised priority", result[:tasks_opened] == 6 && Task.where(status: "OPEN").any? { |t| t.priority > 0 })

      ban = result[:claims].find { |c| c[:handle] == "ban" }
      narrow = result[:claims].find { |c| c[:handle] == "narrow" }
      check.call("meme claim: plain headline says the evidence is against it", ban[:card][:plain][:headline].match?(/against/), ban[:card][:plain][:headline])
      check.call("meme claim: a sentence to say instead", ban[:card][:plain][:say_instead].present?)
      check.call("narrow claim: checks out so far", narrow[:card][:plain][:headline] == "Checks out so far.", narrow[:card][:plain][:headline])
      check.call("narrow claim: labelled provisional and anonymous", narrow[:card][:labels].any? { |l| l.include?("anonymous") })

      source = Source.find(result[:ids]["post"])
      check.call("social post stored by link and hash, no page text", source.by_reference? && source.source_type == "SOCIAL_POST")

      seq = Contribution.maximum(:seq)
      png = Cards::Image.render(Claim.find(ban[:id]), seq, Scoring::Registry.default_model)
      check.call("share card renders as PNG without a number", png.start_with?("\x89PNG".b) && png.bytesize > 5_000)

      before = Ledger::TableDigest.projections
      Ledger::Replay.call
      check.call("replay reproduces every projection digest", Ledger::TableDigest.projections == before)
      check.call("chain verifies", Ledger::Verify.call.status == "CHAIN_VERIFIED")

      out.puts "meme claim: #{ban[:url]}"
      out.puts "share card: #{ban[:url]}/card"
      out.puts(failures.zero? ? "ALL PASS" : "#{failures} FAILURES")
      failures
    end
  end
end
