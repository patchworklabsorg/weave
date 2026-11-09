# frozen_string_literal: true

# The "to do" list on the member home page (home#index): the things that wait
# for this member, each with the page that does it. Empty for most members on
# most days, and the page hides the list then.
#
# Identity verification is not a task: it gates program resources only, so the
# home page shows its status in the account card and does not push it.
module MemberTasks
  Task = Data.define(:key, :title, :body, :path, :action, :icon)

  def self.for(user)
    [email(user), guardian_consent(user), access_requests(user)].compact
  end

  def self.email(user)
    return if user.email_verified?

    Task.new(key: :email, icon: :mail,
             title: "Confirm your email address",
             body: "Open the link we sent to #{user.email}. Some apps stay closed until you do.",
             path: Rails.application.routes.url_helpers.email_confirmation_path, action: "Continue")
  end

  def self.guardian_consent(user)
    return unless user.email_verified? && user.guardian_consent_missing?

    Task.new(key: :guardian_consent, icon: :shield_check,
             title: I18n.t("guardian_consent.form.title"), body: I18n.t("guardian_consent.form.banner"),
             path: Rails.application.routes.url_helpers.guardian_consent_request_path, action: "Continue")
  end

  # Only group managers get this, and only while someone else's request waits
  # for them.
  def self.access_requests(user)
    count = AccessRequest.pending.where(group_id: user.managed_groups.select(:id)).where.not(user_id: user.id).count
    return if count.zero?

    Task.new(key: :access_requests, icon: :key_round,
             title: "#{count} access #{'request'.pluralize(count)} #{count == 1 ? 'waits' : 'wait'} for you",
             body: "Members of your groups asked for access to an app.",
             path: Rails.application.routes.url_helpers.groups_path, action: "Review")
  end
  private_class_method :email, :guardian_consent, :access_requests
end
