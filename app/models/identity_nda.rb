# frozen_string_literal: true

# A signed NDA of a person on (or joining) the identity team (see
# IdentityGovernance). NDAs are signed with Adobe Acrobat Sign.
# An owner records each one here: the date it was signed, the NDA version and
# the Adobe Acrobat Sign agreement ID. Weave keeps no copy of the document.
#
# Rows are append-only. A row never changes and the app never deletes one. A
# newer row supersedes an older one (see User#current_identity_nda).
# == Schema Information
#
# Table name: identity_ndas
# Database name: primary
#
#  id                :bigint           not null, primary key
#  signature_reference :string           not null
#  nda_version       :string           not null
#  signed_on         :date             not null
#  created_at        :datetime         not null
#  recorded_by_id    :bigint
#  user_id           :bigint
#
# Indexes
#
#  index_identity_ndas_on_recorded_by_id  (recorded_by_id)
#  index_identity_ndas_on_user_id         (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (recorded_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class IdentityNda < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :inda

  class ImmutableError < StandardError; end

  belongs_to :user, optional: true
  belongs_to :recorded_by, class_name: "User", optional: true

  validates :signed_on, :nda_version, :signature_reference, presence: true
  validates :nda_version, :signature_reference, length: { maximum: 200 }
  validate :signed_on_not_in_future

  before_update { raise ImmutableError, "NDA records can't change" }
  before_destroy { raise ImmutableError, "NDA records can't be deleted" }

  # The newest record first. The newest signature wins, then the newest row.
  scope :newest_first, -> { order(signed_on: :desc, created_at: :desc, id: :desc) }

  def readonly? = persisted? || super

  private

  def signed_on_not_in_future
    return if signed_on.blank? || signed_on <= Date.current

    errors.add(:signed_on, "can't be in the future")
  end

end
