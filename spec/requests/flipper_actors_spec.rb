# frozen_string_literal: true

require "rails_helper"

# An admin adds a user to a flag from the Flipper UI. FeatureFlags::UserActorAdapter
# turns what the admin types into the user's flipper_id.
RSpec.describe "Flipper UI actor gates", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let!(:user) { create(:user, email: "ada@example.com") }
  let(:actors_path) { "/admin/flipper/features/spec_flag/actors" }

  before do
    stub_const("FeatureFlags::FLAGS", { spec_flag: "A flag for specs" })
    Flipper.add(:spec_flag)
    sign_in_via_magic_link(admin)
  end

  # Flipper::UI has its own CSRF check, so read the token from its form.
  def add_actor(value)
    get actors_path
    token = response.body[/name="authenticity_token" value="([^"]+)"/, 1]
    post actors_path, params: { value:, operation: "enable", authenticity_token: token }
  end

  it "saves an email as the user's flipper_id" do
    add_actor("Ada@Example.com")

    expect(response).to redirect_to("/admin/flipper/features/spec_flag")
    expect(Flipper[:spec_flag].actors_value).to eq(Set[user.flipper_id])
  end

  it "sends the admin back to the form with an error for a value that matches no user" do
    add_actor("nobody@example.com")

    expect(response).to have_http_status(:found)
    follow_redirect!
    expect(response.body).to include("&quot;nobody@example.com&quot; matches no user")
    expect(Flipper[:spec_flag].actors_value).to be_empty
  end

  it "shows the email next to each actor" do
    Flipper.enable_actor(:spec_flag, user)

    get "/admin/flipper/features/spec_flag"

    expect(response.body).to include("ada@example.com (#{user.flipper_id})")
  end
end
