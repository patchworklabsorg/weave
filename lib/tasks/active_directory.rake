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

  desc "Link every non-admin Weave user who has an AD account (employeeID = p_id). Safe to run more than once."
  task link: :environment do
    abort "AD is off or not configured. Run active_directory:doctor." unless ActiveDirectory::Config.current.usable?

    linked = 0
    User.where(directory_linked_at: nil).find_each do |user|
      linked += 1 if DirectoryPasswords.link(user)
    end
    puts "Linked #{linked} users. #{User.where.not(directory_linked_at: nil).count} users are linked in total."
    puts "Admins are not linked here. Link each one with active_directory:link_user P_ID=..."
  end

  desc "Link one user, admins too, after you checked their AD account. P_ID=PWL..."
  task link_user: :environment do
    user = User.find_by(p_id: ENV.fetch("P_ID") { abort "Set P_ID." }) || abort("No such user.")
    entry = DirectoryPasswords.client.find_employee(user.p_id) || abort("AD has no account with employeeID #{user.p_id}.")
    puts "AD account: #{entry.dn} (objectGUID #{entry.object_guid})"
    abort "Check that this is the right account, then run again with CONFIRM=1." unless ENV["CONFIRM"] == "1"

    if DirectoryPasswords.link(user, explicit: true)
      puts "Linked #{user.p_id}."
    else
      abort "Could not link #{user.p_id}. See the log."
    end
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
