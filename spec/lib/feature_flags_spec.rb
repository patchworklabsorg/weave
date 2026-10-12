# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureFlags do
  before { stub_const("FeatureFlags::FLAGS", { spec_flag: "A flag for specs" }) }

  describe "strict mode" do
    it "allows a registered flag that is not in the store yet" do
      expect(Flipper.enabled?(:spec_flag)).to be(false)
    end

    it "raises for a flag that is not in FLAGS" do
      expect { Flipper.enabled?(:not_a_flag) }.to raise_error(FeatureFlags::UnknownFlag, /"not_a_flag" is not in FeatureFlags::FLAGS/)
    end

    it "only logs in production" do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.logger).to receive(:warn)

      expect(Flipper.enabled?(:not_a_flag)).to be(false)
      expect(Rails.logger).to have_received(:warn).with(/"not_a_flag" is not in FeatureFlags::FLAGS/)
    end
  end

  describe ".add_all" do
    it "creates every flag in FLAGS, disabled" do
      described_class.add_all

      expect(Flipper.features.map(&:key)).to include("spec_flag")
      expect(Flipper.enabled?(:spec_flag)).to be(false)
    end
  end

  it "gives the Flipper UI the description of each flag" do
    expect(Flipper::UI.configuration.descriptions_source.call(["spec_flag", "other"])).to eq("spec_flag" => "A flag for specs")
  end
end
