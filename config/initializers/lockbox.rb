# frozen_string_literal: true

# Use a deterministic, throwaway key in the test environment so encrypted
# attributes and blind indexes work without the production credentials. This is
# not a real secret and must never be used outside of tests.
Lockbox.master_key =
  Rails.application.credentials.dig(:lockbox, :master_key) ||
  (Rails.env.test? ? "0" * 64 : nil)

BlindIndex.master_key = Lockbox.master_key if defined?(BlindIndex)

# argon2-kdf (used by blind_index) loads a libargon2 that it builds for glibc.
# That build does not load on musl, so the Alpine image uses its own
# argon2-libs package. Both builds give the same hashes.
system_libargon2 = "/usr/lib/libargon2.so.1"
if File.exist?(system_libargon2)
  require "argon2/kdf"
  Argon2::KDF.ffi_lib = system_libargon2
end
