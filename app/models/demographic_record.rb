# frozen_string_literal: true

# One member's self-reported demographics, as a sealed envelope (see
# DemographicsVault). The app writes it and never opens it. No version
# history is kept, so an update or a withdrawal leaves no copy behind.
# == Schema Information
#
# Table name: demographic_records
# Database name: primary
#
#  id         :bigint           not null, primary key
#  envelope   :text             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  key_id     :string           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_demographic_records_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class DemographicRecord < ApplicationRecord
  belongs_to :user

  validates :envelope, :key_id, presence: true

  # The envelope is ciphertext, but keep it out of logs and the console.
  self.filter_attributes += %w[envelope]

end
