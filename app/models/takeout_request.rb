# frozen_string_literal: true

# A member's data export (takeout, proposal section 06). BuildTakeoutJob
# writes every exportable category (DataCategories.exportable) to one JSON
# file. The member downloads it from /profile/export for
# takeout.download_days, then DataRetention::Sweeps deletes the file.
#
# The file is encrypted at rest with Lockbox. Demographics are never in it:
# the vault has no read path for one member.
# == Schema Information
#
# Table name: takeout_requests
# Database name: primary
#
#  id            :bigint           not null, primary key
#  downloaded_at :datetime
#  expires_at    :datetime
#  ready_at      :datetime
#  status        :string           default("pending"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  user_id       :bigint           not null
#
# Indexes
#
#  index_takeout_requests_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class TakeoutRequest < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :takeout

  STATUSES = %w[pending ready failed expired].freeze

  belongs_to :user

  has_one_attached :archive
  encrypts_attached :archive

  validates :status, inclusion: { in: STATUSES }

  scope :downloadable, -> { where(status: "ready").where(expires_at: Time.current..) }

  def pending? = status == "pending"

  def downloadable? = status == "ready" && expires_at&.future? && archive.attached?

end
