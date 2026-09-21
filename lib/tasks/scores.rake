# frozen_string_literal: true

namespace :scores do
  desc "Trim the score cache: bin/rails scores:prune (KEEP_DAYS=7, DRY_RUN=1 to count only)"
  task prune: :environment do
    Scoring::Prune.call(keep_days: Integer(ENV.fetch("KEEP_DAYS", Scoring::Prune::DEFAULT_KEEP_DAYS)),
                        dry_run: ENV["DRY_RUN"] == "1", out: $stdout)
  end

  desc "Check or rebuild the score watermarks: bin/rails scores:watermarks (VERIFY=1 rescores both ways, REBUILD=1 resets to the head)"
  task watermarks: :environment do
    head = Contribution.maximum(:seq).to_i
    if ENV["REBUILD"] == "1"
      # The safe direction: the head means "assume everything moved", which is
      # what the key meant before Stage 38. It costs one recomputation a claim
      # and cannot serve a stale score.
      Ledger::DatabaseRole.as_owner { Scoring::Watermark.all!(head) }
      puts "every claim marked at the head, #{head}"
    end

    marks = Claim.group(:scored_inputs_seq).count
    puts "#{Claim.count} claims, #{marks.size} distinct watermarks, #{marks[nil].to_i} unmarked, head #{head}"
    puts "#{ClaimScore.count} cached scores; #{Scoring::Prune.send(:current_rows).count} of them are what reads ask for"

    next unless ENV["VERIFY"] == "1"

    # The differential check the keying rests on: score every claim through the
    # watermark and again at the head with the cache emptied, and compare the
    # traces. A disagreement means the mark of that claim missed an input, which
    # is the one failure that would serve a stale score as current.
    wrong = []
    # Every released model, not only the default: a mark that is right for one
    # config and wrong for another would be a mark that is wrong.
    Scoring::Registry.released.each do |model|
      print "#{model.full_name} "
      Claim.order(:created_seq).find_in_batches(batch_size: 200) do |batch|
        keyed = Scoring::Score.call_many(batch, head, model)
        ClaimScore.where(claim_id: batch.map(&:id), scoring_model_id: model.id).delete_all
        Ledger::DatabaseRole.as_owner { Claim.where(id: batch.map(&:id)).update_all(scored_inputs_seq: head) }
        fresh = Scoring::Score.call_many(Claim.where(id: batch.map(&:id)).to_a, head, model)
        batch.each do |claim|
          a = keyed[claim.id]
          b = fresh[claim.id]
          wrong << [ model.full_name, claim.id ] unless a && b && a.assessment_state == b.assessment_state &&
                                                       a.probability == b.probability &&
                                                       a.trace.except("snapshot_seq") == b.trace.except("snapshot_seq")
        end
        print "."
      end
      puts ""
    end
    puts wrong.empty? ? "every claim scores the same through its watermark as it does at the head, under every released model" : "#{wrong.size} DISAGREE: #{wrong.first(10).inspect}"
    abort "watermark verification failed" if wrong.any?
  end
end
