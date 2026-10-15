# frozen_string_literal: true

require "rails_helper"

# The CSP uses a script nonce, so browsers block inline onclick handlers.
# The copy and show buttons must go through Stimulus controllers instead.
RSpec.describe "Admin OAuth application secret buttons", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let(:application) do
    Doorkeeper::Application.create!(name: "Quilt", redirect_uri: "https://quilt.example.com/cb", scopes: "profile")
  end

  before do
    sign_in_via_magic_link(admin)
    get admin_oauth_application_path(application)
  end

  it "has no inline event handlers" do
    expect(response.body).not_to match(/\son(click|change|submit|input)=/)
  end

  it "wires the client secret to the reveal and clipboard controllers" do
    expect(response.body).to include('data-controller="reveal clipboard"')
    expect(response.body).to include(%(data-reveal-secret-value="#{application.secret}"))
    expect(response.body).to include('data-action="reveal#toggle"')
    expect(response.body).to include('data-action="clipboard#copy"')
  end

  it "wires the client ID to the clipboard controller" do
    expect(response.body).to include(%(data-clipboard-text-value="#{application.uid}"))
  end
end
