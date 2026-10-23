# frozen_string_literal: true

module DemographicsVault
  # A throwaway key pair for local development only, in tmp/, made on first
  # use. Production and staging set their own public key and never use this.
  module DevelopmentKeys
    DIR = "tmp/demographics-dev"

    class << self
      def public_pem
        ensure_keys
        File.read(path("public.pem"))
      end

      def private_pem
        ensure_keys
        File.read(path("private.pem"))
      end

      private

      def path(name) = Rails.root.join(DIR, name)

      def ensure_keys
        return if File.exist?(path("private.pem"))

        FileUtils.mkdir_p(Rails.root.join(DIR))
        key = OpenSSL::PKey::RSA.generate(3072)
        File.write(path("private.pem"), key.private_to_pem, perm: 0o600)
        File.write(path("public.pem"), key.public_to_pem)
      end

    end
  end
end
