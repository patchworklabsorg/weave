# frozen_string_literal: true

# Use a deterministic, throwaway key in the test environment so encrypted
# attributes and blind indexes work without the production credentials. This is
# not a real secret and must never be used outside of tests.
Lockbox.master_key =
  Rails.application.credentials.dig(:lockbox, :master_key) ||
  (Rails.env.test? ? "0" * 64 : nil)

BlindIndex.master_key = Lockbox.master_key if defined?(BlindIndex)
