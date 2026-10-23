# frozen_string_literal: true

# A request to decrypt a stored ID image outside pre-review (see BreakGlass).
#
# An identity team member asks, with a written reason. Their browser makes a
# one-time X25519 key pair and sends only the public key
# (requester_public_key). Two different key holders approve, and an approval
# is the submission of the holder's share of the master key with a hardware
# key (see KeyCustody). The second share rebuilds the master key in memory,
# and Weave seals the data key of this one image to the requester's public
# key (handoff_sealed_key). The requester opens it once, in their browser,
# before handoff_expires_at. Weave then deletes the sealed key. To see the
# image again, ask again. The open is a BreakGlassDecryption, and it sends
# the notice ladder (BreakGlassNotice).
# == Schema Information
# Schema version: 20261023120000
#
# Table name: break_glass_records
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  denial_reason        :text
#  denied_at            :datetime
#  expires_at           :datetime
#  granted_at           :datetime
#  handoff_expires_at   :datetime
#  handoff_sealed_key   :text
#  opened_at            :datetime
#  reason               :text             not null
#  requester_public_key :text
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  denied_by_id         :bigint
#  key_set_id           :bigint
#  requested_by_id      :bigint
#  user_id              :bigint
#  verification_id      :bigint           not null
#
# Indexes
#
#  index_break_glass_records_on_denied_by_id     (denied_by_id)
#  index_break_glass_records_on_key_set_id       (key_set_id)
#  index_break_glass_records_on_requested_by_id  (requested_by_id)
#  index_break_glass_records_on_user_id          (user_id)
#  index_break_glass_records_on_verification_id  (verification_id)
#
# Foreign Keys
#
#  fk_rails_...  (denied_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (key_set_id => key_custody_key_sets.id)
#  fk_rails_...  (requested_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (verification_id => verifications.id)
#
class BreakGlassRecord < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :brgl

  has_paper_trail

  belongs_to :verification
  belongs_to :key_set, class_name: "KeyCustodyKeySet", optional: true
  belongs_to :user, optional: true
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :denied_by, class_name: "User", optional: true
  # Every approval, also the lapsed ones (a share that left server memory
  # before the request was granted).
  has_many :approvals, class_name: "BreakGlassApproval", dependent: :restrict_with_exception
  has_many :live_approvals, -> { where(lapsed_at: nil) }, class_name: "BreakGlassApproval", inverse_of: :break_glass_record,
                            dependent: nil
  has_many :approvers, through: :live_approvals
  has_many :decryptions, class_name: "BreakGlassDecryption", dependent: :restrict_with_exception

  validates :reason, presence: true, length: { minimum: 10, maximum: 2000 }
  validates :denial_reason, presence: true, if: :denied_at?
  validate :requester_public_key_shape, on: :create

  scope :pending, -> { where(granted_at: nil, denied_at: nil) }

  def denied? = denied_at.present?

  def granted? = granted_at.present? && !denied?

  def pending? = !granted? && !denied?

  # The requester can open the image now: granted, not opened, and the
  # handoff window has not passed.
  def handoff_open? = granted? && opened_at.nil? && handoff_sealed_key.present? && handoff_expires_at&.future? || false

  # The 32 bytes of the requester's one-time X25519 public key, or nil.
  def requester_public_key_bytes
    bytes = Base64.strict_decode64(requester_public_key.to_s)
    bytes.bytesize == KeyCustody::Crypto::KEY_BYTES ? bytes : nil
  rescue ArgumentError
    nil
  end

  # Who saw the image: the requester, who opened it in their browser.
  def viewer = decryptions.first&.viewer

  # pending, ready (granted, waits for the requester to open it), opened,
  # expired (the handoff window passed) or denied.
  def status
    if denied? then :denied
    elsif opened_at then :opened
    elsif handoff_open? then :ready
    elsif granted? then :expired
    else
      :pending
    end
  end

  private

  def requester_public_key_shape
    return if requester_public_key_bytes

    errors.add(:requester_public_key, "is missing: your browser makes a one-time key for the request. Turn on JavaScript and ask again.")
  end

end
