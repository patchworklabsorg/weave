# frozen_string_literal: true

class EmailConfirmationsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show, :confirm, :resend]
  before_action :authenticate_user_without_email_verification!, only: [:show, :resend]
  # An admin who impersonates a member must not reset the member's
  # confirmation token.
  before_action :refuse_while_impersonating, only: [:resend]

  layout "sessions", only: [:show]

  def show
    # Show the confirmation required page
    @user = current_user
    redirect_to(take_return_path || root_path) if @user&.email_verified?
  end

  def confirm
    @user = User.find_by(confirmation_token: params[:token])

    if @user.nil?
      flash[:alert] = "Invalid confirmation token."
    elsif @user.email_verified?
      flash[:notice] = "Your email has already been confirmed."
    else
      @user.verify_email
      # Send welcome email, sync to Slack, and notify ops now that email is confirmed
      WelcomeEmailJob.perform_later(@user)
      # Invite to Slack (as a single-channel guest pending code-of-conduct
      # acceptance); if they're already in the workspace this just syncs their ID.
      InviteToSlackJob.perform_later(@user.id)
      NotifyOpsOnNewUserJob.perform_later(@user)
      flash[:notice] = "Your email has been successfully confirmed!#{" You can now log in." unless current_user == @user}"
    end
    redirect_after_confirm
  end

  def resend
    @user = current_user

    if @user.email_verified?
      respond_to do |format|
        format.html do
          flash[:notice] = "Your email is already confirmed."
          redirect_to root_path
        end
        format.turbo_stream do
          flash.now[:notice] = "Your email is already confirmed."
          redirect_to root_path
        end
      end
    elsif @user.confirmation_period_valid?
      time_left = 5.minutes - (Time.current - @user.confirmation_sent_at)
      minutes_left = (time_left / 60).ceil

      respond_to do |format|
        format.html do
          flash[:alert] = "Please wait #{minutes_left} minutes before requesting another confirmation email."
          redirect_to email_confirmation_path
        end
        format.turbo_stream do
          flash.now[:alert] = "Please wait #{minutes_left} minutes before requesting another confirmation email."
          render turbo_stream: turbo_stream.replace("resend_section", partial: "resend_section", locals: { user: @user })
        end
      end
    else
      @user.send_confirmation_email

      respond_to do |format|
        format.html do
          flash[:notice] = "A new confirmation email has been sent to your email address."
          redirect_to email_confirmation_path
        end
        format.turbo_stream do
          flash.now[:notice] = "A new confirmation email has been sent to your email address."
          render turbo_stream: turbo_stream.replace("resend_section", partial: "resend_section", locals: { user: @user })
        end
      end
    end
  end

  private

  def refuse_while_impersonating
    return unless impersonating?

    redirect_to email_confirmation_path, alert: "You can't send a confirmation email while impersonating a user."
  end

  # Still signed in as the person who confirmed (the usual case: they opened
  # the email link in the same browser): send them on to the page they were
  # trying to reach when authenticate_user! stopped them (see
  # ReturnAfterSignIn). Anyone else signs in first, and the stored page
  # survives that sign-in.
  def redirect_after_confirm
    if @user && current_user == @user
      redirect_to(take_return_path || root_path)
    else
      redirect_to login_path
    end
  end

end
