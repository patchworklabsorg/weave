# frozen_string_literal: true

require "rails_helper"

# A sign-in link and a guardian consent link hold a raw token. The token
# travels as a job argument, and Active Job writes job arguments to the log
# unless the job says not to.
RSpec.describe "Jobs that carry a link token", type: :job do
  include ActiveJob::TestHelper

  let(:log) { StringIO.new }

  around do |example|
    logger = ActiveJob::Base.logger
    ActiveJob::Base.logger = ActiveSupport::TaggedLogging.new(Logger.new(log))
    example.run
  ensure
    ActiveJob::Base.logger = logger
  end

  it "keeps the magic link token out of the job log" do
    user = create(:user)

    perform_enqueued_jobs { MagicLinkJob.perform_later(user, LinkToken.new("raw-magic-token")) }

    expect(log.string).to include("MagicLinkJob")
    expect(log.string).not_to include("raw-magic-token")
  end

  it "keeps the guardian consent token out of the mail job log" do
    consent = create(:guardian_consent)

    perform_enqueued_jobs do
      GuardianConsentMailer.request_consent(consent, LinkToken.new("raw-consent-token")).deliver_later
      GuardianConsentMailer.receipt(consent, LinkToken.new("raw-receipt-token")).deliver_later
    end

    expect(log.string).to include("TokenMailDeliveryJob")
    expect(log.string).not_to include("raw-consent-token", "raw-receipt-token")
  end

  it "still logs the arguments of other mail jobs" do
    user = create(:user)

    perform_enqueued_jobs { UserMailer.welcome_email(user).deliver_later }

    expect(log.string).to include("welcome_email")
  end
end
