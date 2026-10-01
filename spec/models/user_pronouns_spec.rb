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
