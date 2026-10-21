# frozen_string_literal: true

# Active Directory tasks. See docs/ACTIVE_DIRECTORY.md.
namespace :active_directory do
  desc "Show the AD settings Weave reads (never the password) and which are missing."
  task doctor: :environment do
    config = ActiveDirectory::Config.current
    puts "enabled:   #{config.enabled?}"
    puts "usable:    #{config.usable?}"
    puts "hosts:     #{config.hosts.join(', ')} (port #{config.port})"
    puts "base DN:   #{config.base_dn}"
    puts "bind DN:   #{config.bind_dn || '(missing)'}"
    puts "CA bundle: #{config.ca_file || '(missing)'}"
    puts "timeouts:  connect #{config.connect_timeout}s, operation #{config.timeout}s"
    puts "missing:   #{config.missing.join(', ')}" if config.missing.any?
  end

  desc "Link every Weave user who has an AD account (employeeID = p_id). Safe to run more than once."
  task link: :environment do
    abort "AD is off or not configured. Run active_directory:doctor." unless ActiveDirectory::Config.current.usable?

    linked = 0
    User.where(directory_linked_at: nil).find_each do |user|
      linked += 1 if DirectoryPasswords.link(user)
    end
    puts "Linked #{linked} users. #{User.where.not(directory_linked_at: nil).count} users are linked in total."
  end

  desc "Add the Weave users of an AD OU to a project group. OU='OU=HackBoston,...' GROUP=hackboston [CONFIRM=1]"
  task add_ou_to_group: :environment do
    ou = ENV.fetch("OU") { abort "Set OU to the distinguished name of the OU." }
    group = Group.find_by(slug: ENV.fetch("GROUP") { abort "Set GROUP to the group slug." }) || abort("No such group.")
    abort "#{group.slug} is a system group." unless group.manual?

    employee_ids = ActiveDirectory::Client.new.employee_ids_under(ou)
    users = User.where(p_id: employee_ids).where.not(id: group.memberships.select(:user_id))
    puts "#{employee_ids.size} AD users under #{ou}. #{users.count} Weave users are not in #{group.slug} yet."
    users.each { |user| puts "  #{user.p_id} #{user.email}" }

    unless ENV["CONFIRM"] == "1"
      puts "Dry run. Set CONFIRM=1 to add them."
      next
    end

    PaperTrail.request(whodunnit: "active_directory:add_ou_to_group") do
      users.each { |user| group.memberships.create!(user: user, source: "manual") }
    end
    puts "Added #{users.size} users to #{group.slug}."
  end
end
