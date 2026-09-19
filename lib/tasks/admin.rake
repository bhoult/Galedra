# Recovery for a site with no reachable admin (Stage 24).
namespace :admin do
  desc "Make the user with EMAIL an admin: bin/rails admin:grant[someone@example.com]"
  task :grant, [ :email ] => :environment do |_, args|
    user = User.find_by!(email_address: args[:email].to_s.strip.downcase)
    user.update!(admin: true, admin_granted_at: Time.current, admin_granted_by_id: nil)
    puts "#{user.email_address} is now an admin."
  end
end
