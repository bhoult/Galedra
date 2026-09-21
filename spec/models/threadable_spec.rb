require "rails_helper"

# Two implementations of a conversation drift, and the drift is not
# hypothetical: on 2026-09-20 a guidance line and a refusal hint said different
# things about when to file a report, and the narrower one won because it was the
# one being read. So the mechanics exist once, and a second copy fails here
# rather than being caught in review, or not caught.
RSpec.describe Threadable do
  CONSUMERS = [ BugReport, FeatureRequest, DeterminationThread ].freeze

  # `add_turn!` is the whole of turn-taking: creating the row, clipping it, and
  # saying that it clipped. `respond!` is deliberately not here — a reporter
  # saying an answer satisfied them and a principal naming an outcome are
  # different operations, and forcing them together would be worse than having
  # two. That difference is what the settlement object is for.
  it "owns turn-taking and display on every model that has a conversation" do
    %i[add_turn! state_badge state_line held? settles_at].each do |method|
      CONSUMERS.each do |model|
        expect(model.instance_method(method).owner).to eq(described_class),
                                                       "#{model}##{method} is not the shared one"
      end
    end
  end

  it "keeps settlement as the only seam, and a different rule on each side of it" do
    expect(BugReport.settlement).to eq(Settlements::Opener)
    expect(FeatureRequest.settlement).to eq(Settlements::Opener)
    expect(DeterminationThread.settlement).to eq(Settlements::Consensus)

    %i[held? settles_at badge].each do |method|
      [ Settlements::Opener, Settlements::Consensus ].each { |s| expect(s).to respond_to(method) }
    end
  end

  it "stores every turn in one table" do
    expect(CONSUMERS.map { |m| m.reflect_on_association(:turns).klass }.uniq).to eq([ ThreadTurn ])
    expect(ThreadTurn.table_name).to eq("thread_turns")
    others = ApplicationRecord.descendants.reject { |m| m == ThreadTurn }
    expect(others.select { |m| m.column_names.include?("author_kind") }).to be_empty,
                                                                           "a second turn table is a second implementation"
  end

  it "renders a turn in one partial and nowhere else" do
    views = Dir[Rails.root.join("app/views/**/*.erb")].reject { |f| f.end_with?("shared/_report_thread.html.erb") }
    offenders = views.select { |f| File.read(f).match?(/\.turns\b|\.messages\b/) }
    expect(offenders.map { |f| f.sub("#{Rails.root}/", "") }).to be_empty,
                                                                "a turn is rendered by shared/_report_thread and nothing else"
  end
end
