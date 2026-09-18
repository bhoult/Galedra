module EnvHelpers
  # Rate limits are off under the test null store; this turns them on for a block.
  def with_rate_limiting
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

  def with_env(overrides)
    saved = overrides.keys.to_h { |k| [ k, ENV[k] ] }
    overrides.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end

RSpec.configure do |c|
  c.include EnvHelpers
  # Examples may designate moderators; never let that leak between examples.
  c.around(:each) do |example|
    saved = ENV["LEDGER_MODERATOR_KEY_IDS"]
    example.run
  ensure
    saved.nil? ? ENV.delete("LEDGER_MODERATOR_KEY_IDS") : ENV["LEDGER_MODERATOR_KEY_IDS"] = saved
  end
end
