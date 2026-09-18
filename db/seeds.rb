# The public demo (spec 08) is the seed: `bin/rails db:seed` on a clean database.
# `bin/demo` runs the same script and checks every golden value.
Demo::Runner.prepare!
Demo::PublicDemo.run if Demo::Runner.clean?
