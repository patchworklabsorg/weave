# frozen_string_literal: true

require "rails_helper"

RSpec.describe HeartbeatJob, type: :job do
  it "returns without emitting metrics outside of development" do
    # Guard clause returns early in non-development environments (before the
    # StatsD call), so perform is a no-op here.
    expect(described_class.new.perform("web")).to be_nil
  end
end
