# frozen_string_literal: true

require "rails_helper"

# A member who may not use a restricted app asks for access, and a manager of
# the app's access request group decides (see AccessRequests). Approval adds
# the member to the group, so AppAccess lets them in.
RSpec.describe "Access requests", type: :request do
  include ActiveJob::TestHelper

  def redirect_uri = "https://client.example.com/callback"

  let(:member) { create(:user, :verified, :accepted_code_of_conduct) }
  let(:manager) { create(:user, :verified, :accepted_code_of_conduct) }
  let(:group) { create(:group, name: "Reviewers", slug: "reviewers") }
  let(:application) do
    Doorkeeper::Application.create!(name: "Krater", redirect_uri: redirect_uri, scopes: "openid profile", confidential: true,
                                    access_policy: "restricted")
  end

  before do
    create(:group_membership, group:, user: manager, role: "manager")
    ApplicationAccessGrant.create!(application:, grantee: group)
    application.update!(access_request_group: group)
  end

  def authorization_params
    {
      client_id: application.uid, redirect_uri: redirect_uri, response_type: "code", scope: "openid profile",
      code_challenge: Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest("v" * 64), padding: false),
      code_challenge_method: "S256"
    }
  end

  def ask_for_access(reason: "I review proposals for the spring cohort.")
    post access_requests_path, params: { access_request: { application: application.to_param, reason: } }
  end

  it "lets a member ask from the no-access page, and a manager approve" do # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    sign_in_via_magic_link(member)
    get oauth_authorization_path, params: authorization_params
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include("You can ask for access", "Request access")

    perform_enqueued_jobs { ask_for_access }
    expect(response).to redirect_to(profile_path)
    request_record = AccessRequest.sole
    expect(request_record).to have_attributes(user: member, application:, group:, status: "pending")
    expect(ActionMailer::Base.deliveries.map(&:to)).to contain_exactly([manager.email])
    expect(ActionMailer::Base.deliveries.last.body.encoded).to include("I review proposals")

    get oauth_authorization_path, params: authorization_params
    expect(response.body).to include("You asked for access")

    sign_in_via_magic_link(manager)
    get group_path(group)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(member.full_name, "I review proposals for the spring cohort.")

    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { patch approve_access_request_path(request_record) }
    expect(response).to redirect_to(group_path(group))
    expect(request_record.reload).to have_attributes(status: "approved", decided_by: manager)
    expect(group.users).to include(member)
    expect(AppAccess.permitted?(member, application)).to be(true)
    expect(ActionMailer::Base.deliveries.sole.to).to eq([member.email])
    expect(ActionMailer::Base.deliveries.sole.subject).to include("You now have access to Krater")
  end

  it "lets a manager deny a request, and tells the member" do
    request_record = AccessRequest.create!(user: member, application:, group:, reason: "Please")
    sign_in_via_magic_link(manager)

    perform_enqueued_jobs { patch deny_access_request_path(request_record) }

    expect(request_record.reload).to have_attributes(status: "denied", decided_by: manager)
    expect(group.users).not_to include(member)
    expect(ActionMailer::Base.deliveries.sole.subject).to include("was not approved")
  end

  it "gives a member one pending request per app" do
    sign_in_via_magic_link(member)
    ask_for_access
    ask_for_access

    expect(AccessRequest.count).to eq(1)
    expect(flash[:notice]).to include("You already asked")
  end

  it "needs a reason" do
    sign_in_via_magic_link(member)

    ask_for_access(reason: " ")

    expect(response).to have_http_status(:unprocessable_content)
    expect(AccessRequest.count).to eq(0)
  end

  it "refuses requests for an app that takes none" do
    application.update!(access_request_group: nil)
    sign_in_via_magic_link(member)

    get new_access_request_path(application: application.to_param)
    expect(response).to redirect_to(profile_path)

    ask_for_access
    expect(AccessRequest.count).to eq(0)
  end

  it "does not offer a request to a member who already has access" do
    create(:group_membership, group:, user: member)
    sign_in_via_magic_link(member)

    get new_access_request_path(application: application.to_param)

    expect(response).to redirect_to(profile_path)
    expect(flash[:notice]).to include("You already have access")
  end

  it "does not offer a request when the code of conduct is what is missing" do
    member.update!(slack_coc_accepted_at: nil)
    sign_in_via_magic_link(member)

    ask_for_access

    expect(AccessRequest.count).to eq(0)
  end

  it "does not offer a request when the member has no address on the app's email domains" do
    application.update!(email_domains: ["patchworklabs.org"])
    sign_in_via_magic_link(member)

    ask_for_access

    expect(AccessRequest.count).to eq(0)
  end

  it "emails the superadmins when the group has no managers" do
    Group::Membership.where(user: manager).delete_all
    superadmin = create(:user, :superadmin, :verified)
    sign_in_via_magic_link(member)

    perform_enqueued_jobs { ask_for_access }

    expect(ActionMailer::Base.deliveries.map(&:to)).to include([superadmin.email])
    expect(ActionMailer::Base.deliveries.last.body.encoded).to include("has no managers")
  end

  describe "deciding" do
    let!(:request_record) { AccessRequest.create!(user: member, application:, group:, reason: "Please") }

    it "is refused to someone who does not manage the group" do
      other = create(:user, :verified)
      sign_in_via_magic_link(other)

      patch approve_access_request_path(request_record)

      expect(response).to redirect_to(profile_path)
      expect(request_record.reload).to be_pending
      expect(group.users).not_to include(member)
    end

    it "is refused to a plain member of the group" do
      plain = create(:user, :verified)
      create(:group_membership, group:, user: plain)
      sign_in_via_magic_link(plain)

      patch approve_access_request_path(request_record)

      expect(request_record.reload).to be_pending
    end

    it "is refused to the member who asked" do
      sign_in_via_magic_link(member)

      patch approve_access_request_path(request_record)

      expect(request_record.reload).to be_pending
    end

    it "is allowed to a superadmin" do
      superadmin = create(:user, :superadmin, :verified)
      sign_in_via_magic_link(superadmin)

      patch approve_access_request_path(request_record)

      expect(request_record.reload).to be_approved
      expect(group.users).to include(member)
    end

    it "happens once" do
      sign_in_via_magic_link(manager)
      patch deny_access_request_path(request_record)

      patch approve_access_request_path(request_record)

      expect(request_record.reload).to be_denied
      expect(group.users).not_to include(member)
    end

    it "is refused after the app stops taking requests through the group" do
      application.update!(access_request_group: nil)
      sign_in_via_magic_link(manager)

      patch approve_access_request_path(request_record)

      expect(request_record.reload).to be_cancelled
      expect(group.users).not_to include(member)
    end

    it "closes the pending requests of a deleted group, so the member can ask again" do
      group.destroy

      expect(request_record.reload).to be_cancelled
      expect(AccessRequests.pending_for(member, application)).to be_nil
    end

    it "changes nothing when joining the group would still not let the member in" do
      application.update!(email_domains: ["patchworklabs.org"])
      sign_in_via_magic_link(manager)

      patch approve_access_request_path(request_record)

      expect(flash[:alert]).to include("still can't use Krater")
      expect(request_record.reload).to be_pending
      expect(group.users).not_to include(member)
    end

    it "renews an expired manager row as a plain member" do
      membership = create(:group_membership, group:, user: member, role: "manager", expires_at: 1.day.from_now)
      membership.update_column(:expires_at, 1.day.ago) # rubocop:disable Rails/SkipsModelValidations
      sign_in_via_magic_link(manager)

      patch approve_access_request_path(request_record)

      expect(membership.reload).to have_attributes(expires_at: nil, role: "member")
    end

    it "renews an expired membership on approval" do
      membership = create(:group_membership, group:, user: member, expires_at: 1.day.from_now)
      membership.update_column(:expires_at, 1.day.ago) # rubocop:disable Rails/SkipsModelValidations
      sign_in_via_magic_link(manager)

      patch approve_access_request_path(request_record)

      expect(membership.reload.expires_at).to be_nil
      expect(AppAccess.permitted?(member, application)).to be(true)
    end
  end
end
