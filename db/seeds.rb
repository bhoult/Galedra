# The public demo (spec 08) is the seed: `bin/rails db:seed` on a clean database.
# `bin/demo` runs the same script and checks every golden value.
Demo::Runner.prepare!
if Demo::Runner.clean?
  Demo::PublicDemo.run
else
  warn "db:seed: the log already holds contributions; nothing seeded. Use bin/demo --reset (development only)."
end
