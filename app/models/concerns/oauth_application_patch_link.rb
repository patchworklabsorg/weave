# frozen_string_literal: true

# The patch an OAuth app belongs to, if any (see Patch). Included into
# Doorkeeper::Application by config/initializers/oauth_application_public_id.rb.
#
# Introspection of the app's client_credentials tokens names the patch slug as
# `patch` (see config/initializers/doorkeeper.rb), so a resource server such as
# Quilt can tell which patch the calling app belongs to.
module OauthApplicationPatchLink
  extend ActiveSupport::Concern

  included do
    belongs_to :patch, optional: true, inverse_of: :applications

    # A patch_id that names no patch is a form error, not a foreign key error.
    validates :patch, presence: { message: "must be a patch that exists" }, if: :patch_id?
  end

end
