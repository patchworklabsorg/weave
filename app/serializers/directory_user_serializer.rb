# frozen_string_literal: true

# One user as the directory API shows it to one OAuth app. The fields match the
# claims the app can get at sign-in: `sub` is the Patchwork Labs ID, and
# `groups` and `roles` hold only what is linked to the app (see AppAccess).
class DirectoryUserSerializer
  def initialize(user, application)
    @user = user
    @application = application
  end

  def as_json(*)
    {
      sub: @user.p_id,
      name: @user.full_name,
      email: @user.email,
      email_verified: @user.email_verified?,
      slack_id: @user.slack_id,
      slack_member: @user.slack_member?,
      groups: AppAccess.group_slugs(@user, @application),
      roles: AppAccess.role_keys(@user, @application),
      active: @user.can_authenticate?
    }
  end

end
