# frozen_string_literal: true

# The demographics vault reporting run and key setup (see docs/KYC.md).
namespace :demographics do
  desc "Count the demographics vault into a suppressed aggregate report (needs the private key)"
  task report: :environment do
    reader = DemographicsVault::Reader.from_env
    report = DemographicsReport.generate!(reader:, run_by: ENV.fetch("RUN_BY", ENV.fetch("USER", "rake")))
    # Print only what the admin page shows: suppressed totals, never a cell
    # below the threshold.
    puts "Report #{report.id} saved at #{report.generated_at.iso8601}."
    puts "Respondents (current members): #{report.active['respondents'] || 'hidden'}."
    puts "Departed envelopes counted: #{report.folds_counted}. Unreadable envelopes: #{report.unreadable_count}."
  end

  desc "Make a new key pair: writes private.pem (mode 600) to DIR and prints the public key"
  task generate_keypair: :environment do
    dir = ENV.fetch("DIR") { abort "Set DIR to a folder outside the repository, for example DIR=~/weave-demographics-key" }
    dir = File.expand_path(dir)
    path = File.join(dir, "private.pem")
    abort "#{path} exists. Move it away first." if File.exist?(path)

    FileUtils.mkdir_p(dir, mode: 0o700)
    key = OpenSSL::PKey::RSA.generate(3072)
    File.write(path, key.private_to_pem, perm: 0o600)
    puts "Private key written to #{path}. Keep it offline. Never put it in credentials or weave-env."
    puts "Key id: #{DemographicsVault::Envelope.key_id(key)}"
    puts "Public key, for credentials (demographics.public_key):"
    puts key.public_to_pem
  end
end
