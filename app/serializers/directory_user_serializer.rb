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
      active: @user.can_authenticate?,
      # Under 18, from the birthday. Krater asks for a stronger guardian check
      # before it gives a budget to a minor. False when the birthday is not
      # known yet (see User#slack_onboarding_step).
      minor: @user.minor?,
      # A Weave admin has a signed guardian form and spoke with the guardian.
      # Apps that hand out money or other risk (Krater budgets) ask for it.
      guardian_verified: @user.guardian_verified?,
      # Identity verification: needs_submission, pending, verified or
      # ineligible (see User#verification_status).
      verification_status: @user.verification_status,
      # US residency (not citizenship): true or false while a result stands,
      # null otherwise. OSPool lets only US residents use its capacity. The
      # state of residence stays in Weave.
      us_resident: @user.us_resident?,
      us_residency_checked_on: @user.us_residency_checked_on&.iso8601,
      # The member saved demographics answers. Never the answers themselves.
      # Krater asks for it before a member's first grant application.
      demographics_answered: DemographicsVault.answered?(@user)
    }.merge(age_fields)
  end

  private

  # Only for an app allowed the age scope, like the age_band claim. The key is
  # left out, not null, when the birthday is not known.
  def age_fields
    return {} unless @application.scopes.exists?("age")

    { age_band: @user.age_band }.compact
  end

end
