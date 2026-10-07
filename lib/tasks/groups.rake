# frozen_string_literal: true

namespace :groups do
  desc "Create the system groups and sync every user into them. Safe to run more than once."
  task sync_system: :environment do
    PaperTrail.request(whodunnit: "groups:sync_system") do
      SystemGroups.sync_all
    end

    Group.system.order(:name).each do |group|
      puts "#{group.slug}: #{group.users.count} members"
    end
  end
end
