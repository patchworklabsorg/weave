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

  # The current step, as JSON. The page polls it while it waits on something
  # that can happen elsewhere (accepting in Slack, the promotion), and reloads
  # when the step changes.
  def status
    render json: { step: current_user.slack_onboarding_step }
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
  # Slack DM and for full members who joined before the code-of-conduct flow.
  # Also asks for a real name when the Slack import could not find one, and
  # retries the promotion if it failed after an earlier acceptance.
  def accept_code_of_conduct
    unless %i[accept_code_of_conduct awaiting_promotion].include?(current_user.slack_onboarding_step)
      redirect_to slack_onboarding_path
      return
    end

    # "Try again" after an earlier acceptance needs no new check.
    unless params[:accept] == "1" || current_user.slack_coc_accepted_at.present?
      render_form_errors(accept: I18n.t("code_of_conduct_form.accept_error"))
      return
    end

    result = CodeOfConductAcceptance.call(
      current_user,
      names: params.slice(*CodeOfConductAcceptance::NAME_FIELDS).permit(*CodeOfConductAcceptance::NAME_FIELDS).to_h.symbolize_keys
    )
    unless result.success?
      render_form_errors(result.errors)
      return
    end

    # Sent here from an app's sign-in (see Oauth::AuthorizationsController).
    return_to = session.delete(:code_of_conduct_return_to).to_s
    if return_to.start_with?("/oauth/authorize")
      redirect_to return_to
      return
    end

    notice = if current_user.slack_member?
               "Thanks for accepting the Code of Conduct."
             else
               "Thanks for accepting the Code of Conduct. Your full Slack access is on its way."
             end
    redirect_to slack_onboarding_path, notice: notice
  end

  private

  def render_form_errors(errors)
    @step = current_user.slack_onboarding_step
    @form_errors = errors
    render :show, status: :unprocessable_content
  end

end
