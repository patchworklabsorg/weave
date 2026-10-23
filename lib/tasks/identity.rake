# frozen_string_literal: true

# The one-time bootstrap of the identity team (see
# IdentityGovernance.bootstrap! and docs/KYC_ROLLOUT.md).
namespace :identity do
  desc "Add the first verifiers. BY=<owner email> MEMBERS=<email>,<email>,<email> (in circle order)"
  task bootstrap: :environment do
    abort "Refused: the bootstrap ran before. It runs one time only. Use proposals." if IdentityGovernance.bootstrap_ran?

    owner = User.find_by(email: ENV.fetch("BY", "").strip.downcase)
    abort "Set BY to the email of an owner." if owner.nil?

    emails = ENV.fetch("MEMBERS", "").split(",").map { |email| email.strip.downcase }.compact_blank
    users = emails.map { |email| User.find_by(email:) || abort("No user with the email #{email}.") }

    result = IdentityGovernance.bootstrap!(users, by: owner)
    abort "Refused: #{result.message}" unless result.success?

    puts "Added to the identity team. Now verify each other in this circle:"
    result.record.each do |user, verifier|
      puts "  #{verifier.full_name} (#{verifier.email}) verifies #{user.full_name} (#{user.email})"
    end
    puts "Check the progress with: bin/rails identity:bootstrap_status"
  end

  desc "Show who verifies whom in the bootstrap circle, and each status"
  task bootstrap_status: :environment do
    rows = IdentityGovernance.bootstrap_status
    abort "No bootstrap has run." if rows.empty?

    rows.each do |row|
      name = row[:user]&.full_name || "A deleted user"
      verified_by = row[:verified_by] ? ", verified by #{row[:verified_by].full_name}" : ""
      puts "#{name}: planned verifier #{row[:verifier]&.full_name || 'unknown'}, status #{row[:status] || 'gone'}#{verified_by}"
    end
    puts(IdentityGovernance.bootstrap_open? ? "The bootstrap is open." : "The bootstrap is closed. It runs one time only.")
  end
end
