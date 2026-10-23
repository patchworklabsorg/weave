# frozen_string_literal: true

# Helpers for specs that record a verification pass.
module VerificationHelpers
  # A pass needs the legal name and the birth date on the ID to match the
  # account (see VerificationFlow.account_mismatches). This sets the account
  # to the identifiers without callbacks, so no re-verification trigger runs.
  def match_account!(user, identifiers)
    first, rest = identifiers.legal_name.to_s.split(" ", 2)
    user.update_columns(legal_first_name: first, legal_last_name: rest.presence || first, birthday: identifiers.date_of_birth)
    user
  end
end

RSpec.configure do |config|
  config.include VerificationHelpers
end
