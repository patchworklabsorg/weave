# frozen_string_literal: true

require "rails_helper"

# The CSP uses a script nonce, so browsers block inline onclick handlers.
# The copy and show buttons must go through Stimulus controllers instead.
#
# Client secrets are stored hashed (hash_application_secrets). The stored value
# is the hash, and it does not work as a secret, so the page must never show
# it. The plaintext exists only in the response right after create or
# regenerate.
RSpec.describe "Admin OAuth application secret buttons", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:application) do
    Doorkeeper::Application.create!(name: "Quilt", redirect_uri: "https://quilt.example.com/cb", scopes: "profile")
  end

  def shown_secret
    response.body[/data-reveal-secret-value="([^"]+)"/, 1]
  end

  context "when an admin opens the app page" do
    before do
      sign_in_via_magic_link(admin)
      get admin_oauth_application_path(application)
    end

    it "has no inline event handlers" do
      expect(response.body).not_to match(/\son(click|change|submit|input)=/)
    end

    it "does not show the stored secret, which is only a hash" do
      expect(response.body).not_to include(application.secret)
      expect(shown_secret).to be_nil
      expect(response.body).to include("Weave stores only a hash of the secret")
    end

    it "wires the client ID to the clipboard controller" do
      expect(response.body).to include(%(data-clipboard-text-value="#{application.uid}"))
    end
  end

  context "when a superadmin regenerates the secret" do
    before do
      sign_in_via_magic_link(superadmin)
      patch regenerate_secret_admin_oauth_application_path(application)
    end

    it "renders the page with no-store and the reveal and copy buttons" do
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).to include('data-controller="reveal clipboard"')
      expect(response.body).to include('data-action="reveal#toggle"')
      expect(response.body).to include('data-action="clipboard#copy"')
    end

    it "shows the new plaintext secret, and it authenticates the app" do
      secret = shown_secret
      expect(secret).to be_present
      expect(secret).not_to eq(application.reload.secret)
      expect(Doorkeeper::Application.by_uid_and_secret(application.uid, secret)).to eq(application)
    end

    it "does not show it again on the next visit" do
      secret = shown_secret
      get admin_oauth_application_path(application)

      expect(response.body).not_to include(secret)
    end
  end

  context "when an admin creates an app" do
    before { sign_in_via_magic_link(admin) }

    it "shows the plaintext secret once, and it authenticates the app" do
      post admin_oauth_applications_path, params: {
        doorkeeper_application: { name: "New", redirect_uri: "https://new.example.com/cb", scopes: "profile" }
      }

      created = Doorkeeper::Application.find_by!(name: "New")
      secret = shown_secret
      expect(response).to have_http_status(:ok)
      expect(secret).to be_present
      expect(Doorkeeper::Application.by_uid_and_secret(created.uid, secret)).to eq(created)
    end
  end
end
