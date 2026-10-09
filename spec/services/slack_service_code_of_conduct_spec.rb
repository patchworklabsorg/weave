# frozen_string_literal: true

require "rails_helper"

# The code-of-conduct DM and form are Block Kit views rendered with slocks
# (app/views/slack/code_of_conduct).
RSpec.describe SlackService do
  subject(:service) { described_class.new }

  let(:client) { instance_double(Slack::Web::Client) }

  before do
    service.instance_variable_set(:@client, client)
    allow(described_class).to receive(:code_of_conduct_url).and_return("https://patchworklabs.org/coc")
  end

  def block_types(blocks) = blocks.map { |block| block[:type] }

  describe "#post_code_of_conduct" do
    it "sends a rich DM with the paragraphs, a link to the Code of Conduct, and an accept button" do
      expect(client).to receive(:chat_postMessage) do |args|
        blocks = args[:blocks]
        expect(block_types(blocks)).to eq(%w[header section section divider section actions context])
        expect(blocks.first(2).map { |block| block[:text][:text] }).to eq(["Hello", "First paragraph"])
        expect(blocks[2][:accessory][:url]).to eq("https://patchworklabs.org/coc")
        expect(blocks[5][:elements].first).to include(action_id: "accept_coc", value: "U1", style: "primary")
        expect(blocks[6][:elements].first[:text]).to include("/slack")
      end

      service.post_code_of_conduct("U1", title: "Hello", paragraphs: ["First paragraph"])
    end

    it "uses the form button when asked" do
      expect(client).to receive(:chat_postMessage) do |args|
        button = args[:blocks].find { |block| block[:type] == "actions" }[:elements].first
        expect(button[:action_id]).to eq("open_coc_form")
      end

      service.post_code_of_conduct("U1", form: true)
    end
  end

  describe "#open_code_of_conduct_form" do
    let(:user) { build(:user, first_name: "NOTSET", last_name: "NOTSET") }

    it "opens a form with a required box, name fields for a missing name, and how the data is used" do
      expect(client).to receive(:views_open) do |args|
        view = args[:view]
        expect(args[:trigger_id]).to eq("T1")
        expect(view).to include(type: "modal", callback_id: "coc_form", private_metadata: { channel: "D1", ts: "1.2" }.to_json)
        inputs = view[:blocks].select { |block| block[:type] == "input" }
        expect(inputs.map { |block| block[:block_id] }).to eq(%w[first_name last_name accept])
        expect(inputs.last[:element][:type]).to eq("checkboxes")
        expect(view[:blocks].last[:elements].first[:text]).to include("How we use this information")
      end

      service.open_code_of_conduct_form(trigger_id: "T1", user: user, message: { channel: "D1", ts: "1.2" })
    end

    it "leaves the name fields out when the name is known" do
      user.assign_attributes(first_name: "Ada", last_name: "Lovelace")
      expect(client).to receive(:views_open) do |args|
        block_ids = args[:view][:blocks].filter_map { |block| block[:block_id] }
        expect(block_ids).to eq(%w[accept])
      end

      service.open_code_of_conduct_form(trigger_id: "T1", user: user)
    end
  end
end
