# frozen_string_literal: true

require "rails_helper"

# /admin is guarded by AdminConstraint at the routing layer, which is all that
# stands in front of the engines mounted there (Blazer, Flipper, Mission
# Control, Audits1984). It used to trust session[:user_id] and check only the
# lock, so a signed-out or expired admin cookie, or a suspended admin, still got
# through. Doorkeeper's own application admin (/oauth/applications) had the same
# gap through admin_authenticator.
RSpec.describe "Admin access with a session that is no longer valid", type: :request do
  let(:admin) { create(:user, :admin, :verified) }

  before { sign_in_via_magic_link(admin) }

  describe "the /admin namespace" do
    it "lets a signed-in admin in" do
      get "/admin"

      expect(response).to have_http_status(:ok)
    end

    it "turns away an admin whose session was signed out" do
      admin.user_sessions.update_all(signed_out_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      get "/admin"

      expect(response).to redirect_to("/login")
    end

    it "turns away an admin whose session expired" do
      admin.user_sessions.update_all(expiration_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations

      get "/admin"

      expect(response).to redirect_to("/login")
    end

    it "turns away a suspended admin" do
      admin.suspend!

      get "/admin"

      expect(response).to redirect_to("/login")
    end

    it "keeps a signed-out admin away from the mounted engines" do
      get "/admin/flipper"
      expect(response).to have_http_status(:ok).or have_http_status(:found)
      expect(response.location.to_s).not_to include("/login")

      admin.user_sessions.update_all(signed_out_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      get "/admin/flipper"

      expect(response).to redirect_to("/login")
    end
  end

  describe "Doorkeeper's application admin (/oauth/applications)" do
    it "lets a signed-in admin in" do
      get oauth_applications_path

      expect(response).to have_http_status(:ok)
    end

    it "turns away a suspended admin" do
      admin.suspend!

      get oauth_applications_path

      expect(response).to redirect_to("/login")
    end
  end
end
