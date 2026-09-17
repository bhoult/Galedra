namespace :ledger do
  desc "Generate an Ed25519 system key pair; paste the output into .env"
  task keygen: :environment do
    pair = Crypto::Ed25519::KeyPair.generate
    puts "#{Crypto::SystemKey::PRIVATE_ENV}=#{pair.private_key}"
    puts "#{Crypto::SystemKey::PUBLIC_ENV}=#{pair.public_key}"
    puts "# key_id: #{pair.key_id}"
  end
end
