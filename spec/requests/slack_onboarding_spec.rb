# frozen_string_literal: true

require "rails_helper"

# /slack is the way into the Patchwork Labs Slack, and slack.patchworklabs.org
# points at it. Each visitor sees the next step they need to take.
RSpec.describe "Slack onboarding", type: :request do
  let(:user) { create(:user, :verified) }

  describe "slack.patchworklabs.org" do
    it "sends visitors to the onboarding page on the canonical host" do
      host! "slack.patchworklabs.org"

      get "/"

      expect(response).to have_http_status(:found)
      expect(response.location).to eq("http://example.com/slack")
    end

    it "sends any path there too" do
      host! "slack.patchworklabs.org"

      get "/join"

      expect(response.location).to eq("http://example.com/slack")
    end
  end

  describe "GET /slack" do
    it "asks an anonymous visitor to sign up for an invite" do
      get slack_onboarding_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Request an invite", signup_path)
    end

    it "sends an unconfirmed account to confirm its email first" do
      sign_in_via_magic_link(user)
      user.reload.update!(email_confirmed_at: nil)

      get slack_onboarding_path

      expect(response).to redirect_to(email_confirmation_path)
    end

    it "offers the invite to a confirmed account that doesn't have one yet" do
      sign_in_via_magic_link(user)

      get slack_onboarding_path

      expect(response.body).to include("Send my invite")
    end

    it "offers to accept the code of conduct to a guest" do
      user.update!(slack_id: "U1", slack_invited_at: 1.hour.ago)
      sign_in_via_magic_link(user)

      get slack_onboarding_path

      expect(response.body).to include("I accept the Code of Conduct")
    end

    it "welcomes a full member" do
      user.update!(slack_id: "U1", slack_membership: "member", slack_coc_accepted_at: 1.day.ago)
      sign_in_via_magic_link(user)

      get slack_onboarding_path

      expect(response.body).to include("You're a full member")
    end

    it "asks a full member who never accepted the code of conduct to accept it" do
      user.update!(slack_id: "U1", slack_membership: "member")
      sign_in_via_magic_link(user)

      get slack_onboarding_path

      expect(response.body).to include("now accepts our Code of Conduct", "I have read and accept", "How we use this information")
      expect(response.body).not_to include("Preferred first name")
    end

    it "asks for a name the Slack import could not find" do
      user.update!(slack_id: "U1", slack_membership: "member", first_name: "NOTSET", last_name: "NOTSET")
      sign_in_via_magic_link(user)

      get slack_onboarding_path

      expect(response.body).to include("Preferred first name", "Legal first name (optional)", "Slack nickname (optional)")
    end
  end

  describe "GET /slack/status" do
    it "reports the current step, so the page can reload when it changes elsewhere" do
      user.update!(slack_id: "U1", slack_membership: "member")
      sign_in_via_magic_link(user)

      get status_slack_onboarding_path

      expect(response.parsed_body).to eq("step" => "accept_code_of_conduct")
    end

    it "makes the accept step check the status" do
      user.update!(slack_id: "U1", slack_membership: "member")
      sign_in_via_magic_link(user)

      get slack_onboarding_path

      expect(response.body).to include('data-controller="onboarding-status"', status_slack_onboarding_path)
    end

    it "does not check the status once the person is a full member" do
      user.update!(slack_id: "U1", slack_membership: "member", slack_coc_accepted_at: 1.day.ago)
      sign_in_via_magic_link(user)

      get slack_onboarding_path

      expect(response.body).not_to include("onboarding-status")
    end
  end

  describe "POST /slack" do
    before { sign_in_via_magic_link(user) }

    it "sends the invite" do
      expect { post slack_onboarding_path }.to have_enqueued_job(InviteToSlackJob).with(user.id)

      expect(response).to redirect_to(slack_onboarding_path)
    end

    it "resends an invite sent a while ago" do
      user.update!(slack_invited_at: 1.day.ago)

      expect { post slack_onboarding_path }.to have_enqueued_job(InviteToSlackJob).with(user.id)
    end

    it "doesn't resend an invite sent a few minutes ago" do
      user.update!(slack_invited_at: 2.minutes.ago)

      expect { post slack_onboarding_path }.not_to have_enqueued_job(InviteToSlackJob)
      expect(flash[:alert]).to include("a few minutes ago")
    end

    it "doesn't invite someone who is already in the Slack" do
      user.update!(slack_id: "U1")

      expect { post slack_onboarding_path }.not_to have_enqueued_job(InviteToSlackJob)
    end

    it "requires a signed-in account" do
      delete logout_path

      expect { post slack_onboarding_path }.not_to have_enqueued_job(InviteToSlackJob)
      expect(response).to redirect_to("/login")
    end
  end

  describe "POST /slack/code-of-conduct" do
    before { sign_in_via_magic_link(user) }

    it "accepts the code of conduct for a guest" do
      user.update!(slack_id: "U1")

      expect { post accept_code_of_conduct_slack_onboarding_path, params: { accept: "1" } }
        .to have_enqueued_job(SlackCodeOfConductAcceptedJob).with("U1")
    end

    it "retries the promotion after an earlier acceptance" do
      user.update!(slack_id: "U1", slack_coc_accepted_at: 1.hour.ago)

      expect { post accept_code_of_conduct_slack_onboarding_path }
        .to have_enqueued_job(SlackCodeOfConductAcceptedJob).with("U1")
    end

    it "does not accept without the box checked" do
      user.update!(slack_id: "U1", slack_membership: "member")

      post accept_code_of_conduct_slack_onboarding_path

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Check the box")
      expect(user.reload.slack_coc_accepted_at).to be_nil
    end

    it "does nothing for someone who isn't in the Slack yet" do
      expect { post accept_code_of_conduct_slack_onboarding_path }.not_to have_enqueued_job(SlackCodeOfConductAcceptedJob)
    end

    it "does nothing for a full member who already accepted" do
      user.update!(slack_id: "U1", slack_membership: "member", slack_coc_accepted_at: 1.day.ago)

      expect { post accept_code_of_conduct_slack_onboarding_path }.not_to have_enqueued_job(SlackCodeOfConductAcceptedJob)
    end

    it "records the acceptance for a full member who joined before the code-of-conduct flow" do
      user.update!(slack_id: "U1", slack_membership: "member")

      post accept_code_of_conduct_slack_onboarding_path, params: { accept: "1" }

      expect(user.reload.slack_coc_accepted_at).to be_present
      expect(user).to be_slack_onboarding_complete
      expect(response).to redirect_to(slack_onboarding_path)
    end

    context "when the name is missing" do
      before { user.update!(slack_id: "U1", slack_membership: "member", first_name: "NOTSET", last_name: "NOTSET") }

      it "saves the name with the acceptance" do
        post accept_code_of_conduct_slack_onboarding_path, params: { accept: "1", first_name: "Ada", last_name: "Lovelace" }

        user.reload
        expect(user.full_name).to eq("Ada Lovelace")
        expect(user.legal_name?).to be(false)
        expect(user.slack_coc_accepted_at).to be_present
      end

      it "saves a legal name apart from the preferred name, and sends the preferred name to Slack" do
        expect do
          post accept_code_of_conduct_slack_onboarding_path,
               params: { accept: "1", first_name: "Ada", last_name: "Lovelace", legal_first_name: "Augusta", legal_last_name: "King" }
        end.to have_enqueued_job(PushSlackNameJob).with(user.id, nickname: nil)

        user.reload
        expect(user.full_name).to eq("Ada Lovelace")
        expect(user.legal_full_name).to eq("Augusta King")
      end

      it "asks for both parts of a legal name" do
        post accept_code_of_conduct_slack_onboarding_path,
             params: { accept: "1", first_name: "Ada", last_name: "Lovelace", legal_first_name: "Augusta" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Enter both parts of your legal name")
      end

      it "does not accept without a name" do
        post accept_code_of_conduct_slack_onboarding_path, params: { accept: "1", first_name: "Ada", last_name: "" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Enter your preferred last name.")
        expect(user.reload.slack_coc_accepted_at).to be_nil
        expect(user.first_name).to eq("NOTSET")
      end
    end
  end

  describe "GET /" do
    it "sends a member who hasn't finished joining the Slack to onboarding" do
      sign_in_via_magic_link(user)

      get root_path

      expect(response).to redirect_to(slack_onboarding_path)
    end

    it "sends a full member to their account" do
      user.update!(slack_id: "U1", slack_membership: "member", slack_coc_accepted_at: 1.day.ago)
      sign_in_via_magic_link(user)

      get root_path

      expect(response).to redirect_to(profile_path)
    end

    it "sends a full member who never accepted the code of conduct to onboarding" do
      user.update!(slack_id: "U1", slack_membership: "member")
      sign_in_via_magic_link(user)

      get root_path

      expect(response).to redirect_to(slack_onboarding_path)
    end
  end
end
