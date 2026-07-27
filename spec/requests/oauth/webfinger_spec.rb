# frozen_string_literal: true

require "rails_helper"

# WebFinger is the one OIDC endpoint that takes a user identifier and needs no
# authentication, which makes "what does it reveal about who has an account
# here?" the central question — hence the enumeration examples below.
RSpec.describe "WebFinger", type: :request do
  # The response is application/jrd+json, which Rails does not register as a
  # JSON variant, so `parsed_body` would hand back a raw String.
  let(:json) { JSON.parse(response.body) }
  let(:issuer) { Doorkeeper::OpenidConnect.resolve_issuer }
  let(:host) { URI.parse(issuer).host }
  let(:issuer_rel) { Oauth::WebfingerController::ISSUER_RELATION }

  def webfinger(resource, **query)
    get "/.well-known/webfinger", params: { resource: resource, **query }
  end

  describe "GET /.well-known/webfinger" do
    it "returns the issuer for an acct: identifier on our host" do
      webfinger("acct:someone@#{host}")

      expect(response).to have_http_status(:ok)
      expect(json).to eq(
        "subject" => "acct:someone@#{host}",
        "links"   => [{ "rel" => issuer_rel, "href" => issuer }]
      )
    end

    it "serves the JRD media type RFC 7033 §10.2 registers" do
      webfinger("acct:someone@#{host}")

      expect(response.media_type).to eq("application/jrd+json")
    end

    it "is readable cross-origin, since browser clients are the point" do
      webfinger("acct:someone@#{host}")

      expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
    end

    it "accepts a bare email-style identifier" do
      webfinger("someone@#{host}")

      expect(response).to have_http_status(:ok)
      expect(json["subject"]).to eq("someone@#{host}")
    end

    it "accepts an https: identifier" do
      webfinger("#{issuer}/users/someone")

      expect(response).to have_http_status(:ok)
      expect(json["links"].sole["href"]).to eq(issuer)
    end

    it "matches the host case-insensitively, per RFC 3986 §3.2.2" do
      webfinger("acct:someone@#{host.upcase}")

      expect(response).to have_http_status(:ok)
    end
  end

  # The whole reason this controller exists rather than the gem's. A 404 for
  # "no such user" would let anyone test an address for registration, one
  # request at a time, with no credentials and no rate-limit signal.
  describe "account enumeration" do
    # An address on our own host, so host matching cannot be what distinguishes
    # the two requests below — only account existence could.
    let!(:user) { create(:user, email: "registered@#{host}") }

    it "answers identically for a registered and an unregistered address" do
      webfinger("acct:#{user.email}")
      registered = [response.status, response.body.sub("registered@", "SUBJECT@")]

      webfinger("acct:unregistered@#{host}")

      expect([response.status, response.body.sub("unregistered@", "SUBJECT@")]).to eq(registered)
    end

    # Stronger than mocking a finder: if the users table is never queried, no
    # amount of refactoring can accidentally reintroduce an existence check.
    it "never queries the users table" do
      queries = []
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        queries << payload[:sql]
      end

      webfinger("acct:#{user.email}")

      expect(response).to have_http_status(:ok)
      expect(queries.grep(/\busers\b/)).to be_empty
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end
  end

  describe "identifiers we do not serve" do
    it "404s an identifier on someone else's host" do
      webfinger("acct:someone@example.org")

      expect(response).to have_http_status(:not_found)
    end

    it "404s an identifier with no host at all" do
      webfinger("someone")

      expect(response).to have_http_status(:not_found)
    end

    it "404s an unparseable identifier rather than raising" do
      webfinger("acct:someone@#{host}/ ]not a uri[")

      expect(response).to have_http_status(:not_found)
    end

    # The gem uses params.require here, which surfaces as a 500.
    it "400s when resource is missing" do
      get "/.well-known/webfinger"

      expect(response).to have_http_status(:bad_request)
    end

    it "400s when resource is blank" do
      webfinger("")

      expect(response).to have_http_status(:bad_request)
    end
  end

  # RFC 7033 §4.3
  describe "rel filtering" do
    it "returns the issuer link when it is the requested rel" do
      webfinger("acct:someone@#{host}", rel: issuer_rel)

      expect(json["links"]).to eq([{ "rel" => issuer_rel, "href" => issuer }])
    end

    it "returns an empty link set, not an error, for an unmatched rel" do
      webfinger("acct:someone@#{host}", rel: "http://webfinger.net/rel/avatar")

      expect(response).to have_http_status(:ok)
      expect(json["subject"]).to eq("acct:someone@#{host}")
      expect(json["links"]).to eq([])
    end

    # rel may repeat; a client asking for several link types at once must not
    # lose the one it can use because Rack keeps only the last occurrence.
    it "honours a repeated rel parameter" do
      get "/.well-known/webfinger?resource=acct:someone@#{host}" \
          "&rel=http://webfinger.net/rel/avatar&rel=#{CGI.escape(issuer_rel)}"

      expect(json["links"]).to eq([{ "rel" => issuer_rel, "href" => issuer }])
    end
  end

  # The gem mounts its own webfinger at this exact path. Ours is declared first
  # so it wins; if that ordering is ever lost, these two diverge.
  it "is served by our controller, not the gem's" do
    expect(Rails.application.routes.recognize_path("/.well-known/webfinger"))
      .to include(controller: "oauth/webfinger", action: "show")
  end
end
