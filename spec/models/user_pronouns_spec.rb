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
end
