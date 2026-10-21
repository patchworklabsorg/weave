# frozen_string_literal: true

# The base class of the console audit records: Console1984 sessions and
# commands, Audits1984 audits and ConsoleAccessRequest (see
# config.console1984.base_record_class). It has its own connection pool, so a
# console user who opens a transaction on the app's connection (BEGIN, then
# ROLLBACK) cannot roll back the audit records with it.
class ConsoleAuditRecord < ApplicationRecord
  self.abstract_class = true

  # Tests run each example in one transaction on the app's pool. A second
  # pool would not see the records that the example made.
  connects_to database: { writing: :primary } unless Rails.env.test?

end
