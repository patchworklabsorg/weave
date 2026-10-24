# frozen_string_literal: true

# The digital ID path of verification (verification_method
# "digital_id_call"), for example the EU digital identity wallet. The member
# presents a digital ID instead of uploading an image, and the live call
# follows as usual.
#
# No provider exists yet. This is the interface a provider implements, so the
# flow and the data model do not change when one is added:
#
#   class EudiWalletProvider < DigitalIdProvider::Base
#     def key = "eudi_wallet"
#     def start(verification, return_url:) = ...   # URL the member opens
#     def result(verification, params) = ...       # a VerificationIdentifiers
#   end
#
# Set DigitalIdProvider.current to an instance to turn the path on. Until
# then, members can't choose it.
module DigitalIdProvider
  class NotConfigured < StandardError; end

  class Base
    def key = raise(NotImplementedError)

    # Starts a presentation for the attempt. Returns the URL that the member
    # opens to present their digital ID.
    def start(_verification, return_url:) = raise(NotImplementedError)

    # Reads the presentation result. Returns a VerificationIdentifiers. The
    # identifiers are never stored (see VerificationIdentifiers).
    def result(_verification, _params) = raise(NotImplementedError)

  end

  class << self
    attr_accessor :current

    def available? = !current.nil?

    def fetch! = current || raise(NotConfigured, "No digital ID provider is configured")

  end
end
