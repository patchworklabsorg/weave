# frozen_string_literal: true

namespace :roles do
  desc "Create or update the roles table from config/roles.yml. Safe to run more than once."
  task sync: :environment do
    roles = RoleRegistry.sync!
    roles.each_value do |role|
      holders = role.user_roles.active.count
      puts "#{role.key}: #{role.name}#{' (scopable)' if role.scopable} - #{holders} active assignment(s)"
    end
  end
end
