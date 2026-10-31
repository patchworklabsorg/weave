# frozen_string_literal: true

# Staging only: an address or a domain that an owner allowed in the app (see
# Admin::StagingMailAllowlistEntriesController). On staging,
# Interceptors::MailAllowlistInterceptor allows these entries together with
# the `mail_allowlist` credential, so a new tester needs no deploy. Production
# never reads this table.
# == Schema Information
#
# Table name: staging_mail_allowlist_entries
# Database name: primary
#
#  id            :bigint           not null, primary key
#  entry         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#
# Indexes
#
#  index_staging_mail_allowlist_entries_on_created_by_id  (created_by_id)
#  index_staging_mail_allowlist_entries_on_entry          (entry) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
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
