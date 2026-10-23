# frozen_string_literal: true

# A warning email before the dormancy cutoff (see DormancyJob). last_active_at
# is the last activity the warning was for. A sign-in moves the activity, so
# the old warnings stop counting and the clock starts again.
# == Schema Information
#
# Table name: dormancy_warnings
# Database name: primary
#
#  id             :bigint           not null, primary key
#  days_before    :integer          not null
#  last_active_at :datetime         not null
#  sent_at        :datetime         not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_dormancy_warnings_on_user_id  (user_id)
#  index_dormancy_warnings_unique      (user_id,days_before,last_active_at) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class DormancyWarning < ApplicationRecord
  belongs_to :user

  validates :days_before, numericality: { only_integer: true, greater_than: 0 }
  validates :last_active_at, :sent_at, presence: true

end
