# frozen_string_literal: true

require "rails_helper"

RSpec.describe TimeHelper, type: :helper do
  let(:time) { Time.utc(2026, 10, 25, 15, 38) }

  it "shows a date by default, with the UTC time in the title" do
    expect(helper.time_label(time)).to eq('<time datetime="2026-10-25T15:38:00Z" title="Oct 25, 2026, 15:38 UTC">Oct 25, 2026</time>')
  end

  it "shows a time in Time.zone and names the zone" do
    Time.use_zone("America/New_York") do
      html = helper.time_label(time, :datetime)
      expect(html).to include("Oct 25, 2026, 11:38 AM EDT", 'datetime="2026-10-25T15:38:00Z"', 'title="Oct 25, 2026, 15:38 UTC"')
    end
  end

  it "names the zone for the moment shown, so winter is EST" do
    Time.use_zone("America/New_York") do
      expect(helper.time_label(Time.utc(2026, 12, 1, 15, 0), :datetime)).to include("Dec 1, 2026, 10:00 AM EST")
    end
  end

  it "says UTC when the zone is UTC" do
    expect(helper.time_label(time, :datetime)).to include("Oct 25, 2026, 3:38 PM UTC")
  end

  it "takes the date from the viewer's zone" do
    Time.use_zone("America/Los_Angeles") do
      expect(helper.time_label(Time.utc(2026, 10, 26, 2, 0))).to include(">Oct 25, 2026<")
    end
  end

  it "shows a relative time with the local and the UTC time in the title" do
    travel_to(time + 3.days) do
      Time.use_zone("America/New_York") do
        html = helper.time_label(time, :relative)
        expect(html).to include("3 days ago", 'title="Oct 25, 2026, 11:38 AM EDT (Oct 25, 2026, 15:38 UTC)"')
      end
    end
  end

  it "never moves a date that has no time" do
    Time.use_zone("Pacific/Kiritimati") do
      expect(helper.time_label(Date.new(2026, 10, 25), :month)).to include("October 2026")
      expect(helper.time_label(Date.new(2026, 10, 25), :day)).to include("October 25")
      html = helper.time_label(Date.new(2026, 10, 25))
      expect(html).to include(">Oct 25, 2026<")
      expect(html).not_to include("title=")
    end
  end

  it "returns nil for a blank value" do
    expect(helper.time_label(nil)).to be_nil
  end

  it "rejects an unknown style" do
    expect { helper.time_label(time, :weird) }.to raise_error(KeyError)
  end

  it "gives plain text in Time.zone for email" do
    Time.use_zone("Europe/Berlin") do
      expect(described_class.time_text(time)).to eq("Oct 25, 2026, 4:38 PM CET")
    end
  end

  it "finds a zone the tz database knows, and nothing else" do
    expect(described_class.find_zone("Asia/Kolkata").name).to eq("Asia/Kolkata")
    expect(described_class.find_zone("Etc/Unknown")).to be_nil
    expect(described_class.find_zone("")).to be_nil
  end
end
