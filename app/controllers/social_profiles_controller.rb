# frozen_string_literal: true

# A member's social profiles, on /profile/social: list them, link one, unlink
# one.
#
# The "Link" button posts to /auth/:provider, where OmniAuth sends the member
# to the site to sign in. The site sends them back to #create with the account
# in request.env["omniauth.auth"]. A failed or cancelled sign-in comes back to
# #failure.
#
# Linking is refused while an admin impersonates the member, and the member
# gets an email each time an account is linked.
class SocialProfilesController < ApplicationController
  # The link form posts to /auth/:provider, which redirects to the site.
  # Chrome and Safari apply form-action to each hop of that redirect.
  content_security_policy only: :index do |policy|
    policy.form_action(:self, *SocialProfile.authorize_origins)
  end

  before_action :refuse_while_impersonating, only: [:create, :destroy]

  def index
    @social_profiles = current_user.social_profiles.order(:provider)
    @linkable_providers = SocialProfile.configured_providers - @social_profiles.map(&:provider)
  end

  def create
    auth = request.env["omniauth.auth"]
    if auth.nil? || auth.provider != params[:provider]
      redirect_to social_profiles_path, alert: "We couldn't link that account. Try again."
      return
    end

    provider_name = SocialProfile.provider_name(auth.provider)
    if SocialProfile.where(provider: auth.provider, uid: auth.uid.to_s).where.not(user: current_user).exists?
      redirect_to social_profiles_path, alert: "That #{provider_name} account is already linked to another Weave account."
      return
    end

    # Linking again updates the handle, or replaces the account with another.
    profile = current_user.social_profiles.find_or_initialize_by(provider: auth.provider)
    profile.update!(uid: auth.uid.to_s, username: auth.info.nickname)
    if profile.saved_change_to_uid?
      UserMailer.social_profile_linked(current_user, provider_name, profile.username).deliver_later
      redirect_to social_profiles_path, notice: "#{provider_name} account #{profile.username} linked."
    else
      redirect_to social_profiles_path, notice: "#{provider_name} account #{profile.username} refreshed."
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to social_profiles_path, alert: "We couldn't link that #{provider_name} account. Try again."
  end

  def failure
    redirect_to social_profiles_path, alert: "We couldn't link that account. Try again."
  end

  def destroy
    profile = current_user.social_profiles.find_by_public_param(params[:id])
    if profile.nil?
      redirect_to social_profiles_path, alert: "Social profile not found."
      return
    end

    profile.destroy!
    redirect_to social_profiles_path, notice: "#{profile.provider_name} account unlinked."
  end

  private

  def refuse_while_impersonating
    return unless impersonating?

    redirect_to social_profiles_path, alert: "You can't change social profiles while impersonating a user."
  end

end
