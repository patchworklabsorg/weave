# frozen_string_literal: true

# A member's passkeys, on /profile/passkeys: list them, add one, remove one.
#
# Adding a passkey gives a new way into the account, so it is refused while an
# admin impersonates the member, and the member gets an email each time a
# passkey is added or removed.
class PasskeysController < ApplicationController
  include PasskeyChallenges

  REGISTRATION_ERRORS = {
    expired: "The passkey request timed out. Try again.",
    invalid: "We couldn't add that passkey. Try again.",
    duplicate: "That passkey is already set up for Weave."
  }.freeze

  before_action :require_passkeys_enabled
  before_action :refuse_while_impersonating, only: [:options, :create, :destroy]

  def index
    @passkeys = current_user.passkeys.order(created_at: :desc)
  end

  # Step one of adding a passkey: the options for navigator.credentials.create.
  def options
    options = PasskeyAuthentication.registration_options(current_user)
    store_passkey_challenge(:registration, options.challenge)
    render json: options
  end

  # Step two: the new credential, signed with the challenge from step one.
  def create
    passkey = PasskeyAuthentication.register!(
      current_user,
      credential: params[:credential].to_s,
      challenge: take_passkey_challenge(:registration),
      nickname: params[:nickname]
    )
    UserMailer.passkey_added(passkey).deliver_later
    redirect_to passkeys_path, notice: "Passkey added. You can use it the next time you sign in."
  rescue PasskeyAuthentication::Failure => e
    redirect_to passkeys_path, alert: REGISTRATION_ERRORS.fetch(e.reason, REGISTRATION_ERRORS[:invalid])
  end

  def destroy
    passkey = find_passkey
    if passkey.nil?
      redirect_to passkeys_path, alert: "Passkey not found."
      return
    end

    passkey.destroy!
    UserMailer.passkey_removed(current_user, passkey.display_name).deliver_later
    redirect_to passkeys_path, notice: "Passkey removed."
  end

  private

  def require_passkeys_enabled
    return if Flipper.enabled?(:passkeys, current_user)

    redirect_to profile_path, alert: "Passkeys aren't available for your account yet."
  end

  def refuse_while_impersonating
    return unless impersonating?

    message = "You can't change passkeys while impersonating a user."
    respond_to do |format|
      format.html { redirect_to passkeys_path, alert: message }
      format.json { render json: { error: message }, status: :forbidden }
    end
  end

  def find_passkey
    current_user.passkeys.find_by(id: User::Passkey.find(params[:id].to_s).id)
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
