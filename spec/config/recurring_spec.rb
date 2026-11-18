# frozen_string_literal: true

require "rails_helper"
require "fugit"

# Solid Queue reads config/recurring.yml only when the worker starts. An entry
# with a typing error stops the worker, drops the task, or fails each time it
# runs, and no other spec sees it.
RSpec.describe "config/recurring.yml" do # rubocop:disable RSpec/DescribeClass
  known_keys = %w[class command args schedule queue priority description]

  YAML.load_file(Rails.root.join("config/recurring.yml")).each do |key, options|
    describe key do
      it "has a schedule that Solid Queue can read" do
        expect(Fugit.parse(options["schedule"], multi: :fail)).to be_a(Fugit::Cron)
      end

      it "uses only the keys that Solid Queue reads" do
        expect(options.keys - known_keys).to be_empty
      end

      if options["class"]
        it "names a job class that exists" do
          expect(options["class"].safe_constantize).to be < ActiveJob::Base
        end
      else
        it "calls a method that exists" do
          receiver, method = options.fetch("command").match(/\A([\w:]+)\.(\w+)/).captures

          expect(receiver.constantize).to respond_to(method)
        end
      end
    end
  end
end
