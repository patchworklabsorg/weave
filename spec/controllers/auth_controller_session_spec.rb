# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuthController, type: :controller do
  describe "POST #confirm_magic_link (login session handling)" do
    let(:user) { create(:user, :verified) }
    let(:link) { User::MagicLink.issue!(user) }

    it "rotates the session id on login and drops pre-login keys (fixation)" do
      post :confirm_magic_link,
           params: { token: link.token },
           session: { pre_login: "attacker-fixed-value", oauth_client_id: "client-123" }

      expect(session[:user_id]).to eq(user.id)
      # reset_session cleared the attacker-planted key...
      expect(session[:pre_login]).to be_nil
      # ...but the in-progress OAuth context is preserved across the reset.
      expect(session[:oauth_client_id]).to eq("client-123")
    end

    it "backs the login with a user_sessions record" do
      expect {
        post :confirm_magic_link, params: { token: link.token }
      }.to change { user.user_sessions.count }.by(1)
    end
  end
end
