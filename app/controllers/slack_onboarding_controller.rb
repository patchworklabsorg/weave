# frozen_string_literal: true

# The way into the Patchwork Labs Slack (slack.patchworklabs.org lands here).
#
# Full Slack membership is part of being a member: see User#slack_membership.
# This page shows each person the next step they need to take and lets them
# ask for the next nudge:
#
#   sign up -> confirm email -> accept Slack invite -> accept code of conduct -> member
class SlackOnboardingController < ApplicationController
  skip_before_action :authenticate_user!, only: :show

  # Slack's invite endpoint answers `sent_recently` inside this window anyway,
  # so there is no point asking it again.
  INVITE_COOLDOWN = 10.minutes

  layout "sessions"

  def show
    if current_user && !current_user.email_verified?
      redirect_to email_confirmation_path
      return
    end

    @step = current_user ? current_user.slack_onboarding_step : :sign_up
  end

  # Sends the Slack invite, or sends it again.
  def create
    unless %i[request_invite accept_invite].include?(current_user.slack_onboarding_step)
      redirect_to slack_onboarding_path
      return
    end

    if current_user.slack_invited_at&.after?(INVITE_COOLDOWN.ago)
      redirect_to slack_onboarding_path, alert: "We sent your invite a few minutes ago. Check your email, or try again in a few minutes."
      return
    end

    InviteToSlackJob.perform_later(current_user.id)
    redirect_to slack_onboarding_path, notice: "Your Slack invite is on its way to #{current_user.email}."
  end

  # Accepts the code of conduct from the web, for people who can't find the
  # Slack DM. Also retries the promotion if it failed after an earlier
  # acceptance.
  def accept_code_of_conduct
    unless %i[accept_code_of_conduct awaiting_promotion].include?(current_user.slack_onboarding_step)
      redirect_to slack_onboarding_path
      return
    end

    SlackCodeOfConductAcceptedJob.perform_later(current_user.slack_id)
    redirect_to slack_onboarding_path, notice: "Thanks for accepting the Code of Conduct. Your full Slack access is on its way."
  end

end
