# frozen_string_literal: true

# A key holder's hardware keys (see KeyCustody::Enrollment and
# KeyCustody::Recovery): enroll, register the seal key, revoke a lost key,
# and seal the share for a new key. Every step runs on the holder's own
# computer.
class Identity::HardwareKeysController < Identity::BaseController
  include KeyCustodyAccess

  before_action :set_key, only: [:revoke, :seal_key_options, :seal_key, :rewrap_options, :rewrap]

  # The options for navigator.credentials.create.
  def options
    render json: KeyCustody::Enrollment.creation_options(current_user)
  end

  # Enrollment. A key that gave its PRF output at creation sends the seal
  # public key here too, and is ready at once (one touch). Otherwise the
  # answer holds the options of the second touch: an assertion of the new
  # key with PRF on its seal salt.
  def create
    key = KeyCustody::Enrollment.enroll!(current_user, credential: credential_param, role: params[:role].to_s,
                                                       nickname: params[:nickname],
                                                       seal_public_key: params[:seal_public_key].presence)
    if key.sealable?
      render json: { message: "Enrolled the #{key.role} hardware key with its seal key. It is ready to hold your share.",
                     one_touch: true }
    else
      render json: { message: "Enrolled the #{key.role} hardware key. Touch it again to set up its seal key.",
                     one_touch: false,
                     seal: KeyCustody::Enrollment.seal_key_options(current_user, key),
                     seal_url: seal_key_identity_hardware_key_path(key) }
    end
  end

  # The options to set up the seal key of a key that has none yet.
  def seal_key_options
    render json: KeyCustody::Enrollment.seal_key_options(current_user, @key)
  end

  # Step 2 of enrollment: the seal public key and the assertion.
  def seal_key
    KeyCustody::Enrollment.register_seal_key!(current_user, @key, credential: credential_param,
                                                                  seal_public_key: params[:seal_public_key].to_s)
    json_success("The #{@key.role} hardware key is ready to hold your share.")
  end

  def revoke
    KeyCustody::Enrollment.revoke!(@key, by: current_user, reason: params[:reason].to_s.strip)
    redirect_to identity_key_custody_path, notice: "The key is revoked, and the board is told."
  end

  # The options to seal the share for this new key with a remaining key.
  def rewrap_options
    render json: KeyCustody::Recovery.options(current_user, new_key: @key)
  end

  def rewrap
    KeyCustody::Recovery.rewrap!(current_user, new_key: @key, old_credential: credential_param(:old_credential),
                                               sealed: params[:sealed].to_s)
    json_success("Your share is sealed for the new key. The board is told.")
  end

  private

  def set_key
    @key = IdentityHardwareKey.find_by_public_param!(params[:id])
  end

end
