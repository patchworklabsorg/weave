# frozen_string_literal: true

# Staging only: an address or a domain that an owner allowed in the app (see
# Admin::StagingMailAllowlistEntriesController). On staging,
# Interceptors::MailAllowlistInterceptor allows these entries together with
# the `mail_allowlist` credential, so a new tester needs no deploy. Production
# never reads this table.
class StagingMailAllowlistEntry < ApplicationRecord
  # An exact address, or a domain after "@".
  FORMAT = /\A(?:[^@\s]+@|@)[a-z0-9-]+(?:\.[a-z0-9-]+)+\z/

  belongs_to :created_by, class_name: "User", optional: true

  normalizes :entry, with: ->(value) { value.to_s.strip.downcase }

  validates :entry, presence: true, uniqueness: true,
                    format: { with: FORMAT, message: "must be an email address or a domain that starts with @" }

  # The entries, for the interceptor. Empty outside staging.
  def self.entries
    return [] unless Weave.staging?

    pluck(:entry)
  end

end
