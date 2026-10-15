# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Managing passkeys", type: :request do
  let(:user) { create(:user, :verified) }
  let(:client) { fake_passkey_client }

  def add_passkey(nickname: "Phone")
    post options_passkeys_path, as: :json
    challenge = response.parsed_body.fetch("challenge")
    credential = client.create(challenge: challenge, user_verified: true)
    post passkeys_path, params: { credential: credential.to_json, nickname: nickname }
  end

  context "when the user is signed in" do
    before { sign_in_via_magic_link(user) }

    it "links the page from the profile" do
      get profile_path

      expect(response.body).to include(passkeys_path)
    end

    it "adds a passkey and emails the user" do
      expect { add_passkey }
        .to change { user.passkeys.count }.by(1)
        .and have_enqueued_mail(UserMailer, :passkey_added)

      expect(response).to redirect_to(passkeys_path)
      expect(user.passkeys.sole.nickname).to eq("Phone")

      get passkeys_path
      expect(response.body).to include("Phone")
    end

    it "uses each registration challenge only once" do
      post options_passkeys_path, as: :json
      challenge = response.parsed_body.fetch("challenge")
      credential = client.create(challenge: challenge, user_verified: true).to_json
      post passkeys_path, params: { credential: credential }

      expect do
        post passkeys_path, params: { credential: credential }
      end.not_to(change { user.passkeys.count })
      expect(flash[:alert]).to match(/timed out/)
    end

    it "removes a passkey and emails the user" do
      add_passkey(nickname: "Old phone")
      passkey = user.passkeys.sole

      expect { delete passkey_path(passkey) }
        .to change { user.passkeys.count }.by(-1)
        .and have_enqueued_mail(UserMailer, :passkey_removed)

      expect(response).to redirect_to(passkeys_path)
    end

    it "does not remove another user's passkey" do
      other = create(:user, :verified)
      other_passkey = register_passkey(other)

      expect { delete passkey_path(other_passkey) }.not_to(change(User::Passkey, :count))

      expect(flash[:alert]).to eq("Passkey not found.")
    end

    it "signs in with the passkey it added" do
      add_passkey
      delete logout_path

      post passkey_sign_in_options_path, as: :json
      challenge = response.parsed_body.fetch("challenge")
      post passkey_sign_in_path, params: { credential: passkey_assertion(client, challenge, user: user.reload) }

      expect(session[:user_id]).to eq(user.id)
    end
  end

  context "when an admin impersonates the user" do
    let(:admin) { create(:user, :owner, :verified) }

    before do
      sign_in_via_magic_link(admin)
      post impersonate_admin_user_path(user)
    end

    it "refuses to make registration options" do
      post options_passkeys_path, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses to add a passkey" do
      expect { post passkeys_path, params: { credential: "{}" } }.not_to(change(User::Passkey, :count))
      expect(flash[:alert]).to match(/while impersonating/)
    end

    it "refuses to remove a passkey" do
      passkey = register_passkey(user)

      expect { delete passkey_path(passkey) }.not_to(change(User::Passkey, :count))
      expect(flash[:alert]).to match(/while impersonating/)
    end
  end
end
