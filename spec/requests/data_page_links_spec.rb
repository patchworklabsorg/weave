# frozen_string_literal: true

require "rails_helper"

# Every place that collects or handles identity, verification, demographics
# or guardian data links to "What we do with your data" (Weave.data_page_url).
RSpec.describe "What we do with your data links", type: :request do
  let(:link) { %(href="#{Weave.data_page_url}") }
  let(:member) { create(:user, :verified) }

  # The site-wide footer has the link on every page, so a page counts only
  # with its own link outside the footer.
  def expect_link
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    links = page.css(%(a[href="#{Weave.data_page_url}"]))
    expect(links.reject { |node| node.ancestors("[data-testid='data-footer']").any? }).not_to be_empty
  end

  it "is on the sign-up page" do
    get signup_path
    expect_link
  end

  it "is in the site-wide footer, also on the home page" do
    get root_path
    expect(response.body).to include('data-testid="data-footer"', link)
  end

  context "when signed in" do
    before { sign_in_via_magic_link(member) }

    {
      "the account and profile page" => :profile_path,
      "the verification page"        => :verification_path,
      "the demographics form"        => :demographics_path,
      "the takeout page"             => :takeout_path,
      "the deletion request page"    => :deletion_request_path
    }.each do |name, path|
      it "is on #{name}" do
        get public_send(path)
        expect_link
      end
    end

    it "is on the verification status page after a submit" do
      create(:verification, user: member)
      get verification_path
      expect_link
    end

    it "is on the guardian consent step of the Slack onboarding" do
      member.update_columns(birthday: 15.years.ago.to_date) # rubocop:disable Rails/SkipsModelValidations
      get slack_onboarding_path
      expect_link
    end
  end

  it "is on the guardian consent page" do
    consent = create(:guardian_consent, raw_token: "guardian-token")

    get guardian_consent_path(token: "guardian-token")

    expect(consent).to be_persisted
    expect_link
  end

  it "is in the admin pages through the footer" do
    sign_in_via_magic_link(create(:user, :identity_team))

    get admin_deletion_requests_path

    expect(response.body).to include('data-testid="data-footer"', link)
  end

  it "is in every guardian consent email, in both parts" do
    consent = create(:guardian_consent, user: create(:user, :verified, :minor))
    mails = [GuardianConsentMailer.request_consent(consent, "token"), GuardianConsentMailer.receipt(consent, "token"),
             GuardianConsentMailer.granted(consent), GuardianConsentMailer.revoked(consent)]

    mails.each do |mail|
      parts = mail.multipart? ? mail.parts : [mail]
      parts.each { |part| expect(part.body.decoded).to include(Weave.data_page_url) }
    end
  end
end
