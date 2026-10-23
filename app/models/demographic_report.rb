# frozen_string_literal: true

# The output of one reporting run (see DemographicsReport): counts after
# small-count suppression. A suppressed count is stored as nil, so the small
# number never reaches the database.
# == Schema Information
#
# Table name: demographic_reports
# Database name: primary
#
#  id               :bigint           not null, primary key
#  folds_counted    :integer          default(0), not null
#  generated_at     :datetime         not null
#  results          :jsonb            not null
#  run_by           :string
#  threshold        :integer          not null
#  unreadable_count :integer          default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_demographic_reports_on_generated_at  (generated_at)
#
class DemographicReport < ApplicationRecord
  validates :generated_at, :threshold, presence: true

  def self.latest = order(generated_at: :desc).first

  # { "respondents" => n or nil, "fields" => { field => { value => count or nil } } }
  def active = results.fetch("active", {})

  # Cohort name => the same shape as #active.
  def departed = results.fetch("departed", {})

end
