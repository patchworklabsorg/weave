# frozen_string_literal: true

# Reminds members whose US residency result ends soon (see ResidencyCheck and
# config/kyc/verification.yml). One reminder for each result. Running it
# twice sends nothing new.
class RenewResidencyChecksJob < ApplicationJob
  queue_as :low

  def perform
    window = VerificationSettings.residency_renewal_reminder
    valid_for = VerificationSettings.residency_valid_for
    due = ResidencyCheck.where(status: "decided", us_resident: true, ended_at: nil, renewal_reminded_at: nil)
                        .where.not(user_id: nil)
                        .where(decided_at: (Time.current - valid_for)..(Time.current + window - valid_for))
    due.find_each do |check|
      next unless ResidencyFlow.current_check(check.user) == check
      next if ResidencyFlow.open_check(check.user)

      check.update!(renewal_reminded_at: Time.current)
      ResidencyMailer.renewal_due(check).deliver_later
    end
  end

end
