# frozen_string_literal: true

# Activating or discarding a pending key set (see KeyCustody::Activation and
# KeyCustody::Ceremony.discard!).
class Identity::KeySetsController < Identity::BaseController
  include KeyCustodyAccess

  before_action :set_key_set

  def activation_options
    render json: KeyCustody::Activation.options(current_user, @key_set)
  end

  def activate
    outcome = KeyCustody::Activation.submit!(current_user, @key_set, credential: credential_param,
                                                                     new_share: params[:new_share].presence,
                                                                     old_share: params[:old_share].presence)
    if outcome == :activated
      json_success("Key set #{@key_set.public_id} is active.#{' The old set is retired.' if @key_set.rotation?}")
    else
      json_success("Your share waits, encrypted, for #{VerificationSettings.pending_share_ttl.inspect}. " \
                   "Every other holder must give theirs in that time.")
    end
  end

  def discard
    KeyCustody::Ceremony.discard!(@key_set, by: current_user, reason: params[:reason].to_s)
    redirect_to identity_key_custody_path, notice: "Key set #{@key_set.public_id} is discarded."
  end

  private

  def set_key_set
    @key_set = KeyCustodyKeySet.find_by_public_param!(params[:id])
  end

end
