# frozen_string_literal: true

require "rails_helper"

# AuthController#handle_login_error answers Turbo with
# turbo_stream.update("flash", …). Every layout must render an element with
# that id, even when there is no flash yet, or the error never shows.
RSpec.describe "Flash target", type: :request do
  let(:admin) { create(:user, :admin, :verified) }

  it "is in the sign-in layout" do
    get login_path
    expect(response.body).to include('id="flash"')
  end

  it "is in the member and admin layouts" do
    sign_in_via_magic_link(admin)

    get profile_path
    expect(response.body).to include('id="flash"')

    get admin_root_path
    expect(response.body).to include('id="flash"')
  end

  it "is updated when a Turbo sign-in fails" do
    post login_path, params: { user: { email: "nobody@example.com", password: "wrong" } },
                     headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.body).to include('target="flash"')
  end
end
