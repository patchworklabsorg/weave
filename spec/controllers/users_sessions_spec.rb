# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsersController, type: :controller do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "DELETE #destroy_session" do
    it "revokes the specified session" do
      session_record = user.user_sessions.create!(
        session_token: "revoke-me", expiration_at: 1.day.from_now
      )

      delete :destroy_session, params: { id: session_record.to_param }

      expect(session_record.reload.signed_out_at).to be_present
      expect(response).to redirect_to(profile_sessions_path)
    end

    it "retains the revoked session record instead of deleting it" do
      session_record = user.user_sessions.create!(
        session_token: "keep-data", expiration_at: 1.day.from_now, device_info: "Chrome 150"
      )

      expect {
        delete :destroy_session, params: { id: session_record.to_param }
      }.not_to change(User::Session, :count)

      expect(session_record.reload.device_info).to eq("Chrome 150")
    end

    it "redirects with an alert when the session is not found" do
      delete :destroy_session, params: { id: "nonexistent" }

      expect(response).to redirect_to(profile_sessions_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "DELETE #destroy_all_sessions" do
    it "signs out other active sessions" do
      other = user.user_sessions.create!(
        session_token: "other", expiration_at: 1.day.from_now
      )

      delete :destroy_all_sessions

      expect(other.reload.signed_out_at).to be_present
      expect(response).to redirect_to(profile_sessions_path)
    end
  end
end
