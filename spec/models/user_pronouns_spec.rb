# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "pronouns normalization" do
    let(:user) { create(:user) }

    it "is optional" do
      user.pronouns = nil
      expect(user).to be_valid
    end

    it "strips surrounding whitespace" do
      user.update!(pronouns: "  they/them  ")
      expect(user.pronouns).to eq("they/them")
    end

    it "normalizes blank values to nil" do
      user.update!(pronouns: "   ")
      expect(user.pronouns).to be_nil
    end

    it "preserves the given value otherwise" do
      user.update!(pronouns: "ze/zir")
      expect(user.pronouns).to eq("ze/zir")
    end

    it "accepts up to #{User::PRONOUNS_MAX_LENGTH} characters" do
      user.pronouns = "a" * User::PRONOUNS_MAX_LENGTH
      expect(user).to be_valid
    end

    it "rejects longer values" do
      user.pronouns = "a" * (User::PRONOUNS_MAX_LENGTH + 1)
      expect(user).not_to be_valid
      expect(user.errors[:pronouns]).to be_present
    end
  end

  describe "syncing pronouns with Slack" do
    let(:user) { create(:user, slack_id: "U123") }

    it "pushes an edit made in Weave to Slack" do
      expect { user.update!(pronouns: "she/her") }
        .to have_enqueued_job(PushPronounsToSlackJob).with(user.id)
    end

    it "pushes a cleared value too, so Slack is cleared" do
      user.update!(pronouns: "she/her")

      expect { user.update!(pronouns: "") }.to have_enqueued_job(PushPronounsToSlackJob)
    end

    it "does not push when the account is not in Slack" do
      user.update!(slack_id: nil)

      expect { user.update!(pronouns: "she/her") }.not_to have_enqueued_job(PushPronounsToSlackJob)
    end

    it "pushes Weave's value when the account is first linked to Slack" do
      unlinked = create(:user, pronouns: "ze/zir")

      expect { unlinked.update!(slack_id: "U999") }.to have_enqueued_job(PushPronounsToSlackJob).with(unlinked.id)
    end

    describe "#apply_slack_pronouns!" do
      it "takes the value from Slack without pushing it back" do
        expect { user.apply_slack_pronouns!(" he/him ") }.not_to have_enqueued_job(PushPronounsToSlackJob)
        expect(user.reload.pronouns).to eq("he/him")
        expect(user.slack_pronouns).to eq("he/him")
      end

      it "keeps a Weave edit that has not reached Slack yet" do
        user.apply_slack_pronouns!("he/him")
        user.update!(pronouns: "they/them")

        user.apply_slack_pronouns!("he/him")

        expect(user.reload.pronouns).to eq("they/them")
      end

      it "takes a new Slack value even when a Weave edit is waiting" do
        user.apply_slack_pronouns!("he/him")
        user.update!(pronouns: "they/them")

        user.apply_slack_pronouns!("she/her")

        expect(user.reload.pronouns).to eq("she/her")
      end

      it "ignores a Slack value longer than the limit" do
        user.update!(pronouns: "they/them")

        user.apply_slack_pronouns!("a" * (User::PRONOUNS_MAX_LENGTH + 1))

        expect(user.reload.pronouns).to eq("they/them")
      end

      it "records the value even when another attribute is invalid" do
        user.update_column(:first_name, "") # rubocop:disable Rails/SkipsModelValidations

        user.apply_slack_pronouns!("he/him")

        expect(user.reload.pronouns).to eq("he/him")
      end

      it "keeps Weave's value when the account was just linked" do
        user.update!(pronouns: "they/them")

        user.apply_slack_pronouns!("he/him", just_linked: true)

        expect(user.reload.pronouns).to eq("they/them")
        expect(user.slack_pronouns).to eq("he/him")
      end

      it "takes Slack's value when the account was just linked and Weave has none" do
        user.apply_slack_pronouns!("he/him", just_linked: true)

        expect(user.reload.pronouns).to eq("he/him")
      end

      it "ignores a blank Slack value, so Weave's value is kept" do
        user.update!(pronouns: "they/them")

        user.apply_slack_pronouns!("")

        expect(user.reload.pronouns).to eq("they/them")
      end

      it "pushes later Weave edits again" do
        user.apply_slack_pronouns!("he/him")

        expect { user.update!(pronouns: "they/them") }.to have_enqueued_job(PushPronounsToSlackJob)
      end
    end
  end
end
