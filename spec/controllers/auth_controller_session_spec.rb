# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuthController, type: :controller do
  describe "GET #magic_link_login (login session handling)" do
    let(:user) { create(:user, :verified, :with_magic_link) }

    it "rotates the session id on login and drops pre-login keys (fixation)" do
      token = user.magic_link_token

      get :magic_link_login,
          params: { token: token },
          session: { pre_login: "attacker-fixed-value", oauth_client_id: "client-123" }

      expect(session[:user_id]).to eq(user.id)
      # reset_session cleared the attacker-planted key...
      expect(session[:pre_login]).to be_nil
      # ...but the in-progress OAuth context is preserved across the reset.
      expect(session[:oauth_client_id]).to eq("client-123")
    end

    it "backs the login with a user_sessions record" do
      expect {
        get :magic_link_login, params: { token: user.magic_link_token }
      }.to change { user.user_sessions.count }.by(1)
    end
  end
end
