# System specs run on Capybara's rack_test driver: every interaction here is a
# plain form or a native <details> disclosure, so no browser is needed. To use a
# real browser later: driven_by :selenium, using: :headless_chrome.
RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :rack_test }
end
