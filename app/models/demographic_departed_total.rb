# frozen_string_literal: true

# The running totals for members who have left, per cohort (see
# DemographicsReport). One row, sealed with the vault key pair: the totals are
# raw counts, so the app and Blazer must not read them. Only the reporting
# run opens the row, adds the new departed members, and seals it again.
# == Schema Information
#
# Table name: demographic_departed_totals
# Database name: primary
#
#  id         :bigint           not null, primary key
#  envelope   :text             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  key_id     :string           not null
#
class DemographicDepartedTotal < ApplicationRecord
  validates :envelope, :key_id, presence: true

  self.filter_attributes += %w[envelope]

end
