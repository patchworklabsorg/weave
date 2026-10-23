# frozen_string_literal: true

# One decryption of a stored ID image under a granted BreakGlassRecord. The
# same transaction creates its notices (see BreakGlass.decrypt!), so a
# decryption with no notice can't exist. A row never changes.
# == Schema Information
#
# Table name: break_glass_decryptions
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  ip                    :string
#  user_agent            :string
#  created_at            :datetime         not null
#  break_glass_record_id :bigint           not null
#  viewer_id             :bigint
#
# Indexes
#
#  index_break_glass_decryptions_on_break_glass_record_id  (break_glass_record_id)
#  index_break_glass_decryptions_on_viewer_id              (viewer_id)
#
# Foreign Keys
#
#  fk_rails_...  (break_glass_record_id => break_glass_records.id)
#  fk_rails_...  (viewer_id => users.id) ON DELETE => nullify
#
class BreakGlassDecryption < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :bgdx

  belongs_to :break_glass_record
  belongs_to :viewer, class_name: "User", optional: true
  has_many :notices, class_name: "BreakGlassNotice", dependent: :restrict_with_exception

  scope :between, ->(range) { where(created_at: range) }

  def readonly? = persisted? || super

end
