# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeOfConductRequestJob do
  let(:slack) { instance_double(SlackService, configured?: true, post_code_of_conduct: true) }
  let!(:user) { create(:user, :verified, first_name: "ada", slack_id: "U1", slack_membership: "member") }

  before { allow(SlackService).to receive(:new).and_return(slack) }

  it "sends a Slack DM and an email, and records the request" do
    expect(slack).to receive(:post_code_of_conduct)
      .with("U1", intro: a_string_including("Hi Ada,", "Choose the button below"), collect_name: false)

    expect { described_class.perform_now(user.id) }
      .to have_enqueued_mail(UserMailer, :code_of_conduct_request)

    expect(user.reload.slack_coc_requested_at).to be_present
  end

  it "uses the form button when the name is missing" do
    user.update!(first_name: "NOTSET", last_name: "NOTSET")
    expect(slack).to receive(:post_code_of_conduct)
      .with("U1", intro: a_string_including("Hi there,", "don't have your name"), collect_name: true)

    described_class.perform_now(user.id)
  end

  it "includes the deadline when one is given" do
    expect(slack).to receive(:post_code_of_conduct)
      .with("U1", intro: a_string_including("Please accept by November 1, 2026."), collect_name: false)

    described_class.perform_now(user.id, deadline: Date.new(2026, 11, 1))
  end

  it "still sends the email when Slack fails" do
    allow(slack).to receive(:post_code_of_conduct).and_raise(Slack::Web::Api::Errors::SlackError, "channel_not_found")

    expect { described_class.perform_now(user.id) }.to have_enqueued_mail(UserMailer, :code_of_conduct_request)
  end

  it "skips someone who already accepted" do
    user.update!(slack_coc_accepted_at: 1.day.ago)

    expect { described_class.perform_now(user.id) }.not_to have_enqueued_mail(UserMailer, :code_of_conduct_request)
  end

  it "skips someone already asked, unless it is a reminder" do
    user.update!(slack_coc_requested_at: 1.week.ago)

    expect { described_class.perform_now(user.id) }.not_to have_enqueued_mail(UserMailer, :code_of_conduct_request)
    expect { described_class.perform_now(user.id, reminder: true) }.to have_enqueued_mail(UserMailer, :code_of_conduct_request)
  end

  it "skips an account that can't sign in" do
    user.update!(locked_at: Time.current)

    expect { described_class.perform_now(user.id) }.not_to have_enqueued_mail(UserMailer, :code_of_conduct_request)
  end
end
