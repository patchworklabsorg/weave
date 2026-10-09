# frozen_string_literal: true

require "rails_helper"

# The whole way from signup to full Slack membership, and what OAuth clients
# see at each end of it. Slack itself is stubbed; everything in Weave is real.
RSpec.describe "Slack membership flow", type: :request do
  include ActiveJob::TestHelper

  let(:slack) do
    instance_double(
      SlackService,
      configured?: true,
      find_user_by_email: nil,
      invite_to_workspace: { ok: true, already_member: false },
      post_code_of_conduct: true,
      promote_to_member: { ok: true }
    )
  end

  # Opted out of the code-of-conduct requirement, so the claims can be read
  # before the user accepts (see AppAccess).
  let(:application) do
    Doorkeeper::Application.create!(
      name: "Krater", redirect_uri: "https://krater.example.com/callback", scopes: "openid profile slack",
      requires_code_of_conduct: false
    )
  end

  before { allow(SlackService).to receive(:new).and_return(slack) }

  def slack_claims(user)
    token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id, scopes: "openid slack")
    get oauth_userinfo_path, headers: { "Authorization" => "Bearer #{token.plaintext_token}" }
    expect(response).to have_http_status(:ok)
    response.parsed_body.slice("slack_member", "slack_id")
  end

  it "takes a signup through invite and code of conduct to full membership" do # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    post signup_path, params: { user: { first_name: "Ada", last_name: "Lovelace", email: "ada@example.com" } }
    user = User.find_by!(email: "ada@example.com")
    expect(slack_claims(user)).to eq("slack_member" => false)

    # Confirming the email sends the Slack invite as a single-channel guest.
    expect(slack).to receive(:invite_to_workspace)
      .with(hash_including(email: "ada@example.com", guest: :single_channel))
    get confirm_email_path(token: user.reload.confirmation_token)
    perform_enqueued_jobs(only: InviteToSlackJob)
    expect(user.reload.slack_onboarding_step).to eq(:accept_invite)

    # They accept the invite and land in Slack as a guest.
    SlackWebhookService.process_team_join(
      "id" => "U0ADA", "is_restricted" => true, "is_ultra_restricted" => true, "profile" => { "email" => "ada@example.com" }
    )
    expect(user.reload.slack_onboarding_step).to eq(:accept_code_of_conduct)
    expect(slack_claims(user)).to eq("slack_member" => false, "slack_id" => "U0ADA")

    # They accept the code of conduct and are promoted.
    expect(slack).to receive(:promote_to_member).with("U0ADA")
    SlackCodeOfConductAcceptedJob.perform_now("U0ADA")
    expect(user.reload).to be_slack_member
    expect(slack_claims(user)).to eq("slack_member" => true, "slack_id" => "U0ADA")
  end

  it "makes a full member imported from Slack a member straight away" do
    service = SlackService.allocate
    allow(service).to receive_messages(configured?: true, list_members: [
                                         { "id" => "U0OLD", "updated" => 1.year.ago.to_i, "profile" => { "email" => "old@example.com", "real_name" => "Old Timer" } }
                                       ])

    service.sync_slack_users_to_idp

    user = User.find_by!(email: "old@example.com")
    expect(user).to be_slack_member
    expect(slack_claims(user)).to eq("slack_member" => true, "slack_id" => "U0OLD")
  end

  it "makes an existing account a member when the Slack sync finds it as a full member" do
    user = create(:user, :verified, :accepted_code_of_conduct, email: "known@example.com", slack_id: "U0KNOWN")
    service = SlackService.allocate
    allow(service).to receive_messages(configured?: true, list_members: [
                                         { "id" => "U0KNOWN", "updated" => 1.year.ago.to_i, "profile" => { "email" => "known@example.com" } }
                                       ])

    service.sync_slack_users_to_idp

    expect(user.reload).to be_slack_member
  end
end
