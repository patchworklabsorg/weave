# frozen_string_literal: true

require "rails_helper"

# A job never takes the zone of the request that enqueued it
# (config/initializers/job_time_zone.rb).
RSpec.describe "Job time zone" do # rubocop:disable RSpec/DescribeClass
  before do
    stub_const("ZoneProbeJob", Class.new(ApplicationJob) do
      cattr_accessor :zone
      def perform = self.class.zone = Time.zone.name
    end)
  end

  it "runs a job in UTC when it was enqueued in another zone" do
    data = Time.use_zone("Asia/Tokyo") { ZoneProbeJob.new.serialize }
    expect(data["timezone"]).to eq("Asia/Tokyo")

    ActiveJob::Base.execute(data)

    expect(ZoneProbeJob.zone).to eq("UTC")
  end
end
