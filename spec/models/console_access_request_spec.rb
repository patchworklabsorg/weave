# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsoleAccessRequest do
  let(:superadmin) { create(:user, :superadmin) }

  describe ".open!" do
    it "returns a readable code and stores only its digest" do
      request = described_class.open!(kind: "console", host: "weave-web")

      expect(request.code).to match(/\A[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}\z/)
      expect(request.reload.code_digest).to eq(described_class.digest_for(request.code))
      expect(request.code_digest).not_to include(request.code.delete("-"))
    end
  end

  describe ".find_pending_by_code" do
    let!(:request) { described_class.open!(kind: "sql") }

    it "ignores case and dashes, and reads O as 0 and I or L as 1" do
      typed = request.code.downcase.delete("-").tr("0", "o").tr("1", "l")

      expect(described_class.find_pending_by_code(typed)).to eq(request)
    end

    it "finds nothing for a wrong, expired or decided code" do
      expect(described_class.find_pending_by_code("0000-0000")).to be_nil

      travel(ConsoleAccessRequest::EXPIRATION + 1.second) do
        expect(described_class.find_pending_by_code(request.code)).to be_nil
      end

      request.approve!(by: superadmin)
      expect(described_class.find_pending_by_code(request.code)).to be_nil
    end
  end

  describe "#approve!" do
    let!(:request) { described_class.open!(kind: "console") }

    it "records the superadmin who approved" do
      expect(request.approve!(by: superadmin)).to be(true)
      expect(request.reload).to have_attributes(status: "approved", decided_by: superadmin)
    end

    it "refuses an admin who is not a superadmin" do
      expect(request.approve!(by: create(:user, :admin))).to be(false)
      expect(request.reload).to be_pending
    end

    it "refuses an expired request" do
      travel(ConsoleAccessRequest::EXPIRATION + 1.second) do
        expect(request.approve!(by: superadmin)).to be(false)
        expect(request.reload).to be_expired
      end
    end

    it "refuses a request that was denied" do
      request.deny!(by: superadmin)

      expect(request.approve!(by: superadmin)).to be(false)
      expect(request.reload).to be_denied
    end
  end

  describe "#claim!" do
    let(:request) { described_class.open!(kind: "console") }

    it "returns the approver once" do
      request.approve!(by: superadmin)

      expect(request.claim!).to eq(superadmin)
      expect(request.claim!).to be_nil
      expect(request.reload.claimed_at).to be_present
    end

    it "returns nil before an approval" do
      expect(request.claim!).to be_nil
    end

    it "returns nil for an approval that no console claimed in time" do
      request.approve!(by: superadmin)

      travel(ConsoleAccessRequest::EXPIRATION + 1.second) do
        expect(request.claim!).to be_nil
      end
    end
  end

  # Console1984 protects the tables of its own models from console commands.
  it "is a Console1984 model, so a console cannot change its own approval" do
    expect(described_class.ancestors).to include(Console1984::Base)
  end
end
