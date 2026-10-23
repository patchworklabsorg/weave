# frozen_string_literal: true

# The key ceremony page (see KeyCustody::Ceremony). The operator's browser
# makes the master key pair and the shares, and seals each share to its
# holder's seal public keys. Weave gets only the public key and the sealed
# shares.
class Identity::KeyCeremoniesController < Identity::BaseController
  include KeyCustodyAccess

  def new
    @blocker = KeyCustody::Ceremony.blocker
    @can_run = KeyCustody::Ceremony.can_run?(current_user)
    @holders = KeyCustody.holders.includes(:identity_hardware_keys).to_a
    @rotation_of = KeyCustody.current_key_set
  end

  def start
    render json: KeyCustody::Ceremony.start!(by: current_user)
  end

  def create
    key_set = KeyCustody::Ceremony.complete!(by: current_user, ceremony: params[:ceremony].to_s,
                                             public_key: params[:public_key].to_s, shares: shares_param,
                                             credential: credential_param,
                                             operator_share: params[:operator_share].presence)
    given = KeyCustody::Activation.waiting_holder_ids(key_set).include?(current_user.id)
    json_success("The ceremony made key set #{key_set.public_id}. " \
                 "#{given ? 'Your share is given. The other holders must now activate it, each with their own share on their own computer.' : 'All three holders must now activate it, each with their own share.'}",
                 redirect: identity_key_custody_path)
  end

  private

  # The shares as plain Hashes. KeyCustody::Ceremony.check_shares! reads
  # only the fields it knows.
  def shares_param
    Array(params[:shares]).map { |share| share.respond_to?(:to_unsafe_h) ? share.to_unsafe_h.to_hash : nil }
  end

end
