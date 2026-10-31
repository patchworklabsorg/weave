# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Linking social profiles", type: :request do
  let(:user) { create(:user, :verified) }

  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
  end

  def mock_github(uid: "583231", nickname: "octocat")
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(provider: "github", uid: uid, info: { nickname: nickname })
  end

  # The request phase, then the callback that OmniAuth's test mode redirects to.
  def link_github(**)
    mock_github(**)
    post "/auth/github"
    follow_redirect!
  end

  context "when the user is signed in" do
    before { sign_in_via_magic_link(user) }

    it "links the page from the profile" do
      get profile_path

      expect(response.body).to include(social_profiles_path)
    end

    it "offers GitHub and lets the page post to GitHub" do
      get social_profiles_path

      expect(response.body).to include("Link GitHub")
      expect(response.headers["Content-Security-Policy"]).to include("form-action 'self' https://github.com")
    end

    it "links a GitHub account and emails the user" do
      expect { link_github }
        .to change { user.social_profiles.count }.by(1)
        .and have_enqueued_mail(UserMailer, :social_profile_linked)

      expect(response).to redirect_to(social_profiles_path)
      expect(user.social_profiles.sole).to have_attributes(provider: "github", uid: "583231", username: "octocat")

      get social_profiles_path
      expect(response.body).to include("https://github.com/octocat")
      expect(response.body).not_to include("Link GitHub")
    end

    it "refreshes the username when the same account is linked again, without a new email" do
      link_github
      get social_profiles_path
      expect(response.body).to include("Refresh")

      expect { link_github(nickname: "octocat-renamed") }.not_to have_enqueued_mail(UserMailer, :social_profile_linked)

      expect(user.social_profiles.sole.username).to eq("octocat-renamed")
      expect(flash[:notice]).to match(/refreshed/)
    end

    it "replaces the account with another one and emails the user" do
      link_github

      expect { link_github(uid: "999", nickname: "other-account") }
        .to have_enqueued_mail(UserMailer, :social_profile_linked)

      expect(user.social_profiles.sole).to have_attributes(uid: "999", username: "other-account")
    end

    it "still emails the user when the account is unlinked before the email job runs" do
      link_github
      delete social_profile_path(user.social_profiles.sole)

      expect { perform_enqueued_jobs }.to change { ActionMailer::Base.deliveries.count }.by(1)
      expect(ActionMailer::Base.deliveries.last.text_part.body.to_s).to include("octocat")
    end

    it "explains a callback without an account" do
      get "/auth/github/callback"

      expect(response).to redirect_to(social_profiles_path)
      expect(flash[:alert]).to match(/couldn't link/)
    end

    it "refuses an account that another user linked" do
      create(:user, :verified).social_profiles.create!(provider: "github", uid: "583231", username: "octocat")

      expect { link_github }.not_to(change(SocialProfile, :count))

      expect(flash[:alert]).to match(/already linked to another Weave account/)
    end

    it "explains a failed sign-in on the site" do
      OmniAuth.config.mock_auth[:github] = :access_denied
      post "/auth/github"
      follow_redirect!
      follow_redirect!

      expect(response).to redirect_to(social_profiles_path)
      expect(flash[:alert]).to match(/couldn't link/)
    end

    it "refuses the request phase without the CSRF token" do
      ActionController::Base.allow_forgery_protection = true
      mock_github
      post "/auth/github"

      expect(response.location.to_s).not_to include("/auth/github/callback")
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "unlinks an account" do
      profile = user.social_profiles.create!(provider: "github", uid: "583231", username: "octocat")

      expect { delete social_profile_path(profile) }.to change { user.social_profiles.count }.by(-1)

      expect(response).to redirect_to(social_profiles_path)
    end

    it "does not unlink another user's account" do
      other_profile = create(:user, :verified).social_profiles.create!(provider: "github", uid: "1", username: "other")

      expect { delete social_profile_path(other_profile) }.not_to(change(SocialProfile, :count))

      expect(flash[:alert]).to eq("Social profile not found.")
    end
  end

  context "when the user is signed out" do
    it "sends the callback to sign in and links nothing" do
      mock_github
      get "/auth/github/callback"

      expect(response).to redirect_to(login_path)
      expect(SocialProfile.count).to eq(0)
    end
  end

  context "when an admin impersonates the user" do
    let(:admin) { create(:user, :owner, :verified) }

    before do
      sign_in_via_magic_link(admin)
      post impersonate_admin_user_path(user)
    end

    it "refuses to link an account" do
      expect { link_github }.not_to(change(SocialProfile, :count))
      expect(flash[:alert]).to match(/while impersonating/)
    end

    it "refuses to unlink an account" do
      profile = user.social_profiles.create!(provider: "github", uid: "583231", username: "octocat")

      expect { delete social_profile_path(profile) }.not_to(change(SocialProfile, :count))
      expect(flash[:alert]).to match(/while impersonating/)
    end
  end
end
