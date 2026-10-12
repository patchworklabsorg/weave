# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureFlags::ActorNames do
  let!(:user) { create(:user, email: "ada@example.com") }

  describe ".call" do
    it "names a p_id gate by its user's email" do
      expect(described_class.call([user.flipper_id])).to eq(user.flipper_id => "ada@example.com")
    end

    it "flags a gate saved as an email and names the p_id to use" do
      expect(described_class.call(["ada@example.com"]))
        .to eq("ada@example.com" => "NOT MATCHED: enter #{user.flipper_id} for ada@example.com")
    end

    it "flags a gate that matches no user" do
      expect(described_class.call(["nobody@example.com"]))
        .to eq("nobody@example.com" => "NOT MATCHED: enter an email or a PWL id")
    end

    it "leaves out a p_id gate whose user no longer exists" do
      expect(described_class.call(["PWL0000000000"])).to eq({})
    end
  end

  it "is the actor names source for the Flipper UI" do
    expect(Flipper::UI.configuration.actor_names_source.call([user.flipper_id])).to eq(user.flipper_id => "ada@example.com")
  end
end
