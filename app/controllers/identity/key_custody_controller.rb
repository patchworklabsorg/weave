# frozen_string_literal: true

# The key custody page (see KeyCustody): the key sets, the key holders and
# their hardware keys, the ceremony, recovery and rotation, and the log.
class Identity::KeyCustodyController < Identity::BaseController
  include KeyCustodyAccess

  LOG_LIMIT = 50

  def show
    @current = KeyCustody.current_key_set
    @pending = KeyCustody.pending_key_set
    @key_sets = KeyCustodyKeySet.includes(shares: :holder).order(id: :desc).limit(10)
    @holders = KeyCustody.holders.includes(:identity_hardware_keys).to_a
    @my_keys = current_user.identity_hardware_keys.order(:created_at).to_a
    @my_share = @current&.share_for(current_user)
    @events = KeyCustodyEvent.newest_first.includes(:actor, :subject, :key_set).limit(LOG_LIMIT)
    @activation_progress = KeyCustody::Activation.progress(@pending) if @pending
  end

end
