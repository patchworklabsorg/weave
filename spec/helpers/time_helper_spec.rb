# frozen_string_literal: true

require "rails_helper"

RSpec.describe TimeHelper, type: :helper do
  let(:time) { Time.utc(2026, 10, 25, 15, 38) }

  it "shows a date by default" do
    expect(helper.time_label(time)).to eq('<time datetime="2026-10-25T15:38:00Z">Oct 25, 2026</time>')
  end

  it "shows a time in UTC and says so" do
    expect(helper.time_label(time.in_time_zone("America/New_York"), :datetime)).to include("Oct 25, 2026, 15:38 UTC")
  end

  it "shows a relative time with the absolute time in the title" do
    travel_to(time + 3.days) do
      html = helper.time_label(time, :relative)
      expect(html).to include("3 days ago")
      expect(html).to include('title="Oct 25, 2026, 15:38 UTC"')
    end
  end

  it "shows a month and a day without a year" do
    expect(helper.time_label(Date.new(2026, 10, 25), :month)).to include("October 2026")
    expect(helper.time_label(Date.new(2026, 10, 25), :day)).to include("October 25")
  end

  it "returns nil for a blank value" do
    expect(helper.time_label(nil)).to be_nil
  end

  it "rejects an unknown style" do
    expect { helper.time_label(time, :weird) }.to raise_error(KeyError)
  end
end
