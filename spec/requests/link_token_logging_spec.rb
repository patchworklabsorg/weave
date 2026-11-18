# frozen_string_literal: true

require "rails_helper"

# A link from an email has the raw token in its path. The token must not go
# to the request log or to the visit table.
RSpec.describe "Link tokens in the request log", type: :request do
  let(:token) { "s3cr3t-Link_T0ken-0123456789" }
  let(:log) { StringIO.new }

  around do |example|
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(log))
    original = Rails.logger
    Rails.logger = logger
    ActionController::Base.logger = logger
    example.run
  ensure
    Rails.logger = original
    ActionController::Base.logger = original
  end

  it "does not log the token of a guardian consent link" do
    get "/guardian/#{token}"

    expect(log.string).to include('Started GET "/guardian/[FILTERED]"')
    expect(log.string).not_to include(token)
  end

  it "does not log the token of a magic link" do
    get "/auth/magic_link/#{token}"

    expect(log.string).to include('Started GET "/auth/magic_link/[FILTERED]"')
    expect(log.string).not_to include(token)
  end

  it "does not log the token in the redirect after a guardian gives consent" do
    consent = create(:guardian_consent)
    consent.reissue!
    consent.save!

    post "/guardian/#{consent.token}", params: { confirm: "1", signed_name: "Pat Parent" }

    expect(response).to have_http_status(:found)
    expect(log.string).to include("Redirected to [FILTERED]")
    expect(log.string).not_to include(consent.token)
  end

  it "does not store the token in the landing page of a visit" do
    # Ahoy records no visit for a request without a browser user agent.
    get "/guardian/#{token}", headers: { "User-Agent" => "Mozilla/5.0 (Macintosh) AppleWebKit/605.1.15 Safari/605.1.15" }

    landing_pages = Ahoy::Visit.pluck(:landing_page).join(" ")

    expect(landing_pages).to include("/guardian/[FILTERED]")
    expect(landing_pages).not_to include(token)
  end
end
