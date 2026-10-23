# frozen_string_literal: true

# One cell of the delete-time aggregates (see DeleteTimeAggregates): a count
# of departed members for one combination of generalized bands. No row per
# person, no identifier, no timestamps, and a random id. Read it only through
# DeleteTimeAggregates.report, which applies small-count suppression.
# == Schema Information
#
# Table name: delete_time_aggregates
# Database name: primary
#
#  id          :uuid             not null, primary key
#  age_band    :string           not null
#  amount_band :string           not null
#  count       :integer          default(0), not null
#  outcome     :string           not null
#  program     :string           not null
#  region      :string           not null
#  year        :integer          not null
#
# Indexes
#
#  index_delete_time_aggregates_on_bands  (program,year,outcome,age_band,region,amount_band) UNIQUE
#
class DeleteTimeAggregate < ApplicationRecord
  validates :program, :year, :outcome, :age_band, :region, :amount_band, presence: true
  validates :count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

end
