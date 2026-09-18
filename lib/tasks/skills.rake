namespace :skills do
  desc "Render skills/galedra.md into the per-host skill files"
  task build: :environment do
    require "skills/build"
    Skills::Build.write!.each { |path| puts "wrote #{path}" }
  end
end
