# frozen_string_literal: true

# == Schema Information
#
# Table name: lockbox_audits
# Database name: primary
#
#  id           :bigint           not null, primary key
#  context      :string
#  data         :jsonb
#  ip           :string
#  subject_type :string
#  viewer_type  :string
#  created_at   :datetime
#  subject_id   :bigint
#  viewer_id    :bigint
#
# Indexes
#
#  index_lockbox_audits_on_subject  (subject_type,subject_id)
#  index_lockbox_audits_on_viewer   (viewer_type,viewer_id)
#
# One read of a user's private data. The subject is the user, the viewer is who
# read it. A patch app that reads a shipping address writes one row per read
# (context SHIPPING_ADDRESS_READ, the viewer is the OAuth app).
class LockboxAudit < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :laud

  SHIPPING_ADDRESS_READ = "shipping_address_read"

  belongs_to :subject, polymorphic: true
  belongs_to :viewer, polymorphic: true

  scope :shipping_address_reads, -> { where(context: SHIPPING_ADDRESS_READ) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

end
