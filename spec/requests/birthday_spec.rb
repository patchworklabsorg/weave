# frozen_string_literal: true

require "rails_helper"

# Weave needs a birthday to check a member's age: sign-up asks for it, and a
# member without one is asked before anything else.
RSpec.describe "Birthday", type: :request do
  include ActiveJob::TestHelper

  let(:signup) { { first_name: "Ada", last_name: "Lovelace", email: "ada@example.com" } }

  describe "sign-up" do
    it "needs a birthday" do
      post signup_path, params: { user: signup }

      expect(response).to have_http_status(:unprocessable_content)
      expect(User.find_by(email: "ada@example.com")).to be_nil
    end

    it "turns away people under 13" do
      post signup_path, params: { user: signup.merge(birthday: 12.years.ago.to_date.iso8601) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("You must be 13 or older")
      expect(User.find_by(email: "ada@example.com")).to be_nil
    end

    it "refuses a date in the future" do
      post signup_path, params: { user: signup.merge(birthday: 1.day.from_now.to_date.iso8601) }

      expect(User.find_by(email: "ada@example.com")).to be_nil
    end

    it "creates the account with a real birthday" do
      post signup_path, params: { user: signup.merge(birthday: "2010-05-01") }

      expect(User.find_by(email: "ada@example.com").birthday).to eq(Date.new(2010, 5, 1))
    end
  end

  describe "a member without a birthday" do
    let(:user) { create(:user, :verified, birthday: nil, slack_birthday: Date.new(1999, 4, 2)) }

    before { sign_in_via_magic_link(user) }

    it "is asked for it first, with the Slack birthday filled in" do
      get root_path
      expect(response).to redirect_to(slack_onboarding_path)

      get slack_onboarding_path
      expect(response.body).to include("Add your birthday", 'value="1999-04-02"')
    end

    it "saves it once and moves on" do
      expect { post birthday_path, params: { birthday: "1999-04-02" } }.to have_enqueued_job(InviteToSlackJob)

      expect(user.reload.birthday).to eq(Date.new(1999, 4, 2))
      expect(response).to redirect_to(slack_onboarding_path)

      post birthday_path, params: { birthday: "2001-01-01" }
      expect(user.reload.birthday).to eq(Date.new(1999, 4, 2))
    end

    it "shows an error for a date that is not real" do
      post birthday_path, params: { birthday: "not a date" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.birthday).to be_nil
    end

    it "sends a member under 18 the Slack invite without guardian consent" do
      expect { post birthday_path, params: { birthday: 15.years.ago.to_date.iso8601 } }
        .to have_enqueued_job(InviteToSlackJob).with(user.id)

      expect(user.reload.slack_onboarding_step).to eq(:request_invite)
    end

    it "stops a member under 13 and tells the admins" do
      expect { post birthday_path, params: { birthday: 12.years.ago.to_date.iso8601 } }
        .to have_enqueued_mail(AdminMailer, :under_minimum_age)
        .and have_enqueued_job(RevokeLostAppAccessJob).with(user_id: user.id)

      follow_redirect!
      expect(response.body).to include("You must be 13 or older")
    end

    it "saves it even when another field on the old account is not valid" do
      user.update_column(:phone_number, "not a phone") # rubocop:disable Rails/SkipsModelValidations

      post birthday_path, params: { birthday: "1999-04-02" }

      expect(user.reload.birthday).to eq(Date.new(1999, 4, 2))
    end
  end
end
