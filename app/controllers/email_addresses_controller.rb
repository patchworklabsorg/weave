# frozen_string_literal: true

class EmailAddressesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:confirm]

  def create
    @email_address = current_user.email_addresses.new(email_address_params)

    if @email_address.save
      @email_address.send_confirmation_email
      redirect_to edit_profile_path, notice: "#{@email_address.email} added. Check that inbox for a confirmation link."
    else
      redirect_to edit_profile_path, alert: @email_address.errors.full_messages.to_sentence
    end
  end

  # Confirmation links work whether or not the user is signed in — possession
  # of the token is the proof of ownership.
  def confirm
    email_address = params[:token].present? ? EmailAddress.find_by(confirmation_token: params[:token]) : nil
    destination = current_user ? edit_profile_path : login_path

    if email_address.nil?
      redirect_to destination, alert: "Invalid confirmation token."
    elsif email_address.confirmed?
      redirect_to destination, notice: "This email address has already been confirmed."
    else
      email_address.confirm!
      redirect_to destination, notice: "#{email_address.email} has been confirmed."
    end
  end

  def make_primary
    email_address = find_email_address
    if email_address.nil?
      redirect_to edit_profile_path, alert: "Email address not found."
      return
    end

    if email_address.make_primary!
      redirect_to edit_profile_path, notice: "#{email_address.email} is now your primary email address."
    else
      redirect_to edit_profile_path, alert: email_address.errors.full_messages.to_sentence
    end
  end

  def resend_confirmation
    email_address = find_email_address
    if email_address.nil?
      redirect_to edit_profile_path, alert: "Email address not found."
      return
    end

    if email_address.confirmed?
      redirect_to edit_profile_path, notice: "#{email_address.email} is already confirmed."
    elsif email_address.confirmation_period_valid?
      time_left = 5.minutes - (Time.current - email_address.confirmation_sent_at)
      minutes_left = (time_left / 60).ceil
      redirect_to edit_profile_path, alert: "Please wait #{minutes_left} #{'minute'.pluralize(minutes_left)} before requesting another confirmation email."
    else
      email_address.send_confirmation_email
      redirect_to edit_profile_path, notice: "Confirmation email sent to #{email_address.email}."
    end
  end

  def destroy
    email_address = find_email_address
    if email_address.nil?
      redirect_to edit_profile_path, alert: "Email address not found."
      return
    end

    if email_address.destroy
      redirect_to edit_profile_path, notice: "#{email_address.email} removed."
    else
      redirect_to edit_profile_path, alert: email_address.errors.full_messages.to_sentence
    end
  end

  private

  # Email addresses are addressed by their encoded public id in URLs. Resolve
  # that back to the primary key so we can scope to the current user.
  def find_email_address
    current_user.email_addresses.find_by(id: resolve_email_address_id(params[:id]))
  end

  def resolve_email_address_id(param)
    EmailAddress.find(param.to_s).id
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def email_address_params
    params.require(:email_address).permit(:email)
  end

end
