# frozen_string_literal: true

# == Schema Information
#
# Table name: user_magic_links
# Database name: primary
#
#  id           :bigint           not null, primary key
#  expires_at   :datetime         not null
#  requested_ip :string
#  token_digest :string           not null
#  used_at      :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_user_magic_links_on_expires_at    (expires_at)
#  index_user_magic_links_on_token_digest  (token_digest) UNIQUE
#  index_user_magic_links_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe User::MagicLink do
  let(:user) { create(:user) }

  describe ".issue!" do
    it "exposes the raw token once and stores only its digest" do
      link = described_class.issue!(user)

      expect(link.token).to be_present
      expect(link.token_digest).to eq(described_class.digest_for(link.token))
      expect(link.reload.attributes).not_to include("token")
      expect(described_class.where(token_digest: link.token).count).to eq(0)
    end

    it "expires the link 15 minutes out" do
      travel_to Time.current do
        expect(described_class.issue!(user).expires_at).to be_within(1.second).of(15.minutes.from_now)
      end
    end
  end

  describe ".for_token" do
    it "finds the link the raw token belongs to" do
      link = described_class.issue!(user)

      expect(described_class.for_token(link.token)).to eq(link)
    end

    it "returns nil for an unknown token" do
      described_class.issue!(user)

      expect(described_class.for_token("nope")).to be_nil
    end

    it "returns nil for a blank token" do
      expect(described_class.for_token("")).to be_nil
      expect(described_class.for_token(nil)).to be_nil
    end

    # A truncated token — mail clients wrapping long URLs, a bad copy-paste —
    # must not resolve to the link it was cut from.
    it "returns nil for a truncated token" do
      link = described_class.issue!(user)

      expect(described_class.for_token(link.token[0..-2])).to be_nil
    end
  end

  describe "#rejection_reason" do
    it "is nil while the link is live" do
      expect(described_class.issue!(user).rejection_reason).to be_nil
    end

    it "is :used once consumed" do
      link = described_class.issue!(user)
      link.consume!

      expect(link.rejection_reason).to eq(:used)
    end

    it "is :expired past the expiry" do
      link = create(:user_magic_link, :expired, user: user)

      expect(link.rejection_reason).to eq(:expired)
    end

    # Used wins over expired: a link that was used and then sat around is more
    # usefully described by what the reader did with it.
    it "prefers :used over :expired when both apply" do
      link = create(:user_magic_link, :used, :expired, user: user)

      expect(link.rejection_reason).to eq(:used)
    end
  end

  describe "#consume!" do
    it "marks the link used and returns true" do
      link = described_class.issue!(user)

      expect(link.consume!).to be true
      expect(link.reload.used_at).to be_present
    end

    it "refuses a second consume" do
      link = described_class.issue!(user)
      link.consume!

      expect(link.consume!).to be false
    end

    it "refuses an expired link" do
      link = create(:user_magic_link, :expired, user: user)

      expect(link.consume!).to be false
      expect(link.reload.used_at).to be_nil
    end

    # The claim is a conditional UPDATE, so only one of two racing requests can
    # win. That is the case a mail scanner racing the human produces.
    it "lets only one of two concurrent claims through" do
      link = described_class.issue!(user)
      other = described_class.find(link.id)

      results = [link.consume!, other.consume!]

      expect(results).to contain_exactly(true, false)
    end
  end

  describe "scopes" do
    it "counts only live links" do
      live = described_class.issue!(user)
      create(:user_magic_link, :used, user: user)
      create(:user_magic_link, :expired, user: user)

      expect(described_class.live).to contain_exactly(live)
    end
  end
end
