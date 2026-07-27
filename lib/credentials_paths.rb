# frozen_string_literal: true

# Resolves which encrypted credentials file to read and which key opens it.
#
# Rails derives these two paths independently: the content path checks for
# config/credentials/<env>.yml.enc, while the key path checks for
# config/credentials/<env>.key and falls back to config/master.key when it is
# absent. When only one of the pair is present — which is exactly the state a
# machine is left in after credentials are split onto dedicated per-environment
# keys (#77) — Rails pairs the per-environment file with the old master key and
# tries to decrypt it. That aborts boot with
#
#   AEAD authentication tag verification failed
#
# which reads like a corrupt credentials file rather than a missing key, and it
# happens even though a missing key is supposed to degrade to empty credentials
# in environments that do not set `require_master_key`.
#
# Resolving both halves together keeps the file and its key in lockstep: either
# the per-environment pair or the shared pair, never one of each.
module CredentialsPaths
  module_function

  # Returns [content_path, key_path] as Pathnames. Neither is guaranteed to
  # exist — an absent key is a valid state that Rails handles on its own.
  def resolve(root:, env:)
    env_content = root.join("config/credentials/#{env}.yml.enc")

    if env_content.exist?
      [env_content, root.join("config/credentials/#{env}.key")]
    else
      [root.join("config/credentials.yml.enc"), root.join("config/master.key")]
    end
  end
end
