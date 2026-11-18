# frozen_string_literal: true

require "rails_helper"

# The queue table stores job arguments as text, and /admin/jobs shows them. A
# link token must be stored encrypted (LinkToken), and the mail must still
# hold the link that works.
RSpec.describe "Link tokens in job arguments", type: :job do
  include ActiveJob::TestHelper

  # What the queue adapter writes to the queue table.
  def stored_arguments = enqueued_jobs.map { |job| job[:args].to_json }.join("\n")

  it "stores the magic link token encrypted, and mails the link that works" do
    user = create(:user)

    user.send_magic_link
    stored = stored_arguments
    perform_enqueued_jobs
    token = ActionMailer::Base.deliveries.last.body.encoded[/\/auth\/magic_link\/([\w-]+)/, 1]

    expect(User::MagicLink.find_by(token_digest: User::MagicLink.digest_for(token)).user).to eq(user)
    expect(stored).to include("LinkToken::Serializer")
    expect(stored).not_to include(token)
  end

  it "stores the guardian consent request token encrypted, and mails the link that works" do
    member = create(:user, :verified, :minor)

    consent = GuardianConsentFlow.request(member, guardian_name: "Pat Parent", guardian_email: "pat@example.org").consent
    stored = stored_arguments
    perform_enqueued_jobs

    expect(stored).not_to include(consent.token)
    expect(ActionMailer::Base.deliveries.last.body.encoded).to include("/guardian/#{consent.token}")
    expect(GuardianConsent.for_token(consent.token)).to eq(consent)
  end

  it "stores the token of the guardian receipt encrypted, and mails the revoke link" do
    consent = create(:guardian_consent, raw_token: "receipt-raw-token-0123456789")

    GuardianConsentFlow.grant(consent, token: "receipt-raw-token-0123456789", signed_name: "Pat Parent",
                                       ip: "203.0.113.5", user_agent: "Spec")
    stored = stored_arguments
    perform_enqueued_jobs

    expect(stored).not_to include("receipt-raw-token-0123456789")
    receipt = ActionMailer::Base.deliveries.find { |mail| mail.to == [consent.guardian_email] }
    expect(receipt.body.encoded).to include("/guardian/receipt-raw-token-0123456789")
  end

  it "still runs a job that was queued with a plain token before the change" do
    user = create(:user)

    MagicLinkJob.perform_now(user, "plain-token-from-an-old-job")

    expect(ActionMailer::Base.deliveries.last.body.encoded).to include("/auth/magic_link/plain-token-from-an-old-job")
  end

  it "refuses a stored token that was changed" do
    stored = LinkToken::Serializer.serialize(LinkToken.new("raw"))

    expect { LinkToken::Serializer.deserialize(stored.merge("value" => "#{stored['value']}x")) }
      .to raise_error(ActiveSupport::MessageEncryptor::InvalidMessage)
  end

  it "refuses to enqueue a plain token" do
    user = create(:user)
    consent = create(:guardian_consent)

    expect { MagicLinkJob.perform_later(user, "plain-token") }.to raise_error(ArgumentError, /LinkToken/)
    expect { GuardianConsentMailer.receipt(consent, "plain-token").deliver_later }.to raise_error(ArgumentError, /LinkToken/)
    expect(enqueued_jobs).to be_empty
  end

  it "still enqueues the guardian mails that have no token" do
    consent = create(:guardian_consent, :granted)

    expect { GuardianConsentMailer.granted(consent).deliver_later }.to have_enqueued_mail(GuardianConsentMailer, :granted)
  end

  it "does not show the token when it is inspected or written as JSON" do
    token = LinkToken.new("raw-secret")

    expect(token.inspect).not_to include("raw-secret")
    expect({ arguments: [token] }.to_json).not_to include("raw-secret")
  end

  it "does not wrap a token two times" do
    expect(LinkToken.new(LinkToken.new("raw-secret")).to_param).to eq("raw-secret")
  end
end
