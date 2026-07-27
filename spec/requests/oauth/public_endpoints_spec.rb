# frozen_string_literal: true

require "rails_helper"

# Regression coverage for a bug where analytics broke the protocol.
#
# Ahoy's default `user_method` falls back to Doorkeeper's
# `current_resource_owner` for controllers that have no `current_user`. That
# call is not a passive read — it runs the `resource_owner_authenticator` block,
# which redirects to /oauth/login. Ahoy runs as a `before_action` on every
# controller, so the redirect fired before the endpoint's own code, and every
# unauthenticated OAuth endpoint answered 302 to a login page.
#
# The requests here carry a browser User-Agent on purpose. Ahoy does not track
# visits it believes are bots, and rack-test's default agent is treated as one,
# so a default request spec never reaches the code that broke — which is why the
# existing discovery specs stayed green throughout.
RSpec.describe "Unauthenticated OAuth/OIDC endpoints", type: :request do
  # A visit Ahoy will actually try to attribute to somebody.
  let(:browser) do
    {
      "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
                           "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    }
  end

  describe "the visit attribution itself" do
    # The invariant, stated directly and without depending on bot detection:
    # resolving a visit's user must never reach an authenticator with side
    # effects.
    it "never consults Doorkeeper's resource owner authenticator" do
      doorkeeper_style_controller = Class.new do
        def current_resource_owner
          raise "resource_owner_authenticator was invoked during analytics"
        end
      end.new

      expect(Ahoy.user_method.call(doorkeeper_style_controller)).to be_nil
    end

    it "still attributes a visit to the signed-in user" do
      user = create(:user)
      app_style_controller = Class.new do
        attr_reader :current_user

        def initialize(user) = @current_user = user
      end.new(user)

      expect(Ahoy.user_method.call(app_style_controller)).to eq(user)
    end
  end

  describe "GET /.well-known/openid-configuration" do
    it "serves the discovery document to an anonymous browser" do
      get "/.well-known/openid-configuration", headers: browser

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["issuer"]).to be_present
    end
  end

  describe "GET /oauth/discovery/keys" do
    it "serves the JWKS to an anonymous browser" do
      get "/oauth/discovery/keys", headers: browser

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["keys"]).to be_present
    end
  end

  describe "POST /oauth/token" do
    # RFC 6749 section 3.2: the token endpoint authenticates the *client*. A
    # resource owner session is not involved, and a browser redirect is never a
    # valid answer — the client is a server, and it parses JSON.
    it "answers a bad grant with a JSON error rather than a login redirect" do
      post "/oauth/token",
           params: { grant_type: "authorization_code", code: "not-a-real-code" },
           headers: browser

      expect(response).not_to have_http_status(:redirect)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["error"]).to be_present
    end
  end
end
