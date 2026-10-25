# frozen_string_literal: true

# Helpers for a screenshot seed script. Require this file from the seed you
# write for the change:
#
#   require_relative "<repo>/.claude/skills/pr-screenshots/scripts/seed_helpers"
#   member = ScreenshotSeed.person("Robin", "Okafor", "robin@example.com")
#
# Every helper finds the record first, so a seed can run again.
module ScreenshotSeed
  PASSWORD = "Screenshot-Pass-123!"

  module_function

  # A member who has finished onboarding: email confirmed, code of conduct
  # accepted, adult birthday. Pass role: "admin" or "superadmin" for staff.
  def person(first_name, last_name, email, role: nil, **attributes)
    user = User.find_by(email:) || User.create!(
      first_name:, last_name:, email:, password: PASSWORD, birthday: Date.new(1995, 4, 2),
      email_confirmed_at: Time.current, slack_coc_accepted_at: Time.current, **attributes
    )
    user.update!(role:) if role && user.role != role
    user
  end

  def group(name, **attributes)
    Group.find_by(name:) || Group.create!(name:, **attributes)
  end

  def oauth_app(name, **attributes)
    Doorkeeper::Application.find_by(name:) ||
      Doorkeeper::Application.create!(name:, redirect_uri: "https://#{name.parameterize}.example.com/callback",
                                      scopes: "openid profile", **attributes)
  end
end
