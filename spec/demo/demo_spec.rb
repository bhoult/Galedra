require "rails_helper"

RSpec.describe "bin/demo (07 Phase 7; success standard)" do
  it "seeds the public demo through the write path and passes every golden and replay check" do
    release_models
    out = StringIO.new
    failures = Demo::Report.new("public-demo", Demo::PublicDemo.run(Demo::Helpers.new), out: out).run
    expect(failures).to eq(0), out.string
    expect(out.string).to include("ALL PASS")
    expect(out.string.scan(/^PASS /).size).to be >= 30
    expect(GraphSnapshot.pluck(:label)).to include("S1 as drafted", "S5 qualified")
    expect(Contribution.where(action_type: "TASK_RESULT").count).to eq(5)
    expect(Contribution.where(custody: "SERVER").count).to be > 20
  end

  it "seeds the Watchers stress test and passes every check" do
    release_models
    out = StringIO.new
    failures = Demo::Report.new("watchers", Demo::Watchers.run(Demo::Helpers.new), out: out).run
    expect(failures).to eq(0), out.string
    expect(out.string).to include("ALL PASS")
  end

  it "runs the check-before-you-post demo end to end (Stage 14 #5)" do
    release_models
    out = StringIO.new
    failures = Demo::Check.run(out: out)
    expect(failures).to eq(0), out.string
    expect(out.string).to include("ALL PASS")
    expect(out.string).to include("share card:")
  end
end
