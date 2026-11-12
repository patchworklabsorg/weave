# frozen_string_literal: true

namespace :patches do
  desc "Create a patch for each program in config/kyc/knot.yml. Safe to run more than once."
  task sync: :environment do
    PaperTrail.request(whodunnit: "patches:sync") do
      Patch.sync_programs!
    end

    Patch.order(:slug).each do |patch|
      puts "#{patch.slug}: #{patch.name}"
    end
  end
end
