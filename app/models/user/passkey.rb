# frozen_string_literal: true

# == Schema Information
#
# Table name: user_passkeys
# Database name: primary
#
#  id             :bigint           not null, primary key
#  compromised_at :datetime
#  last_used_at   :datetime
#  nickname       :string
#  public_key     :text             not null
#  sign_count     :bigint           default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  external_id    :string           not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_user_passkeys_on_external_id  (external_id) UNIQUE
#  index_user_passkeys_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class User
  # A WebAuthn credential that signs its owner in without an email link.
  #
  # Passkeys are discoverable: the authenticator keeps the user handle
  # (User#webauthn_id), so sign-in starts without an email address and the
  # credential itself says whose it is. Each one is made with user verification
  # (a PIN, fingerprint or face), so a passkey alone counts as a full sign-in.
  #
  # Only the public key is stored. It is not a secret, so it is not encrypted.
  #
  # A removed passkey is deleted, not soft-deleted: it must never sign in again,
  # and the PaperTrail version keeps the record of it.
  class Passkey < ApplicationRecord
    include EncodedIds::HashidIdentifiable
    set_public_id_prefix :pkey

    self.table_name = "user_passkeys"

    NICKNAME_MAX_LENGTH = 50

    has_paper_trail

    belongs_to :user

    scope :active, -> { where(compromised_at: nil) }

    validates :external_id, presence: true, uniqueness: true
    validates :public_key, presence: true
    validates :sign_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :nickname, length: { maximum: NICKNAME_MAX_LENGTH }

    normalizes :nickname, with: ->(value) { value.strip.presence }

    def compromised? = compromised_at.present?

    def display_name
      nickname || "Passkey added #{created_at.to_date.to_fs(:long)}"
    end

  end

end
