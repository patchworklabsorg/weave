# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc, :legal_,
  # Identifiers from an ID at a verification decision (see VerificationIdentifiers).
  :document_number, :national_id, :date_of_birth, :issuing_country,
  # The uploaded ID image: its file name often holds the member's name.
  :id_document,
  # Self-reported answers for the demographics vault (see DemographicsVault).
  :demographic,
  # The internal trust score ledger: the written reason, the evidence
  # link, the "on behalf of" voucher and a project outcome must not reach the
  # logs or the API usage rows.
  :reason, :evidence_url, :voucher, :outcome
]
