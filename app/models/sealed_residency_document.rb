# frozen_string_literal: true

# A residency proof document after pre-review (see ResidencyDocumentVault),
# sealed like an ID image (SealedIdDocument): encrypted with its own random
# data key, and the data key sealed to the master public key of a key set.
#
# The ciphertext attachment is not Lockbox: it is already encrypted, and the
# server key must not open it.
# == Schema Information
#
# Table name: sealed_residency_documents
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  content_type       :string           not null
#  extension          :string
#  sealed_at          :datetime         not null
#  sealed_data_key    :text             not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  key_set_id         :bigint           not null
#  residency_check_id :bigint           not null
#
# Indexes
#
#  index_sealed_residency_documents_on_key_set_id          (key_set_id)
#  index_sealed_residency_documents_on_residency_check_id  (residency_check_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (key_set_id => key_custody_key_sets.id)
#  fk_rails_...  (residency_check_id => residency_checks.id)
#
class SealedResidencyDocument < ApplicationRecord
  belongs_to :residency_check
  belongs_to :key_set, class_name: "KeyCustodyKeySet"
  has_one_attached :ciphertext

  validates :sealed_data_key, :content_type, :sealed_at, presence: true

  def sealed_data_key_bytes = Base64.strict_decode64(sealed_data_key)

end
