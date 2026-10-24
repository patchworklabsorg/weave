# frozen_string_literal: true

# A member's part in a program in one year (participation data, proposal
# section 06). KnotGrants records one when a grant is given.
#
# At deletion, the generalized bands of each row (program, year, outcome, age
# band, region, amount band) fold into the delete-time aggregates
# (DeleteTimeAggregates) and the row is destroyed. The one exception: when
# a funder of the program requires individual records
# (config/kyc/data_retention.yml), the row stays without a link to the
# person, with its bands, until retained_until. Then it folds into the
# aggregates like everything else (DataRetention::Sweeps).
# == Schema Information
#
# Table name: program_participations
# Database name: primary
#
#  id             :bigint           not null, primary key
#  age_band       :string
#  amount_band    :string
#  detached_at    :datetime
#  funder         :string
#  outcome        :string           not null
#  program        :string           not null
#  region         :string
#  retained_until :datetime
#  year           :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  user_id        :bigint
#
# Indexes
#
#  index_program_participations_on_retained_until                (retained_until)
#  index_program_participations_on_user_id                       (user_id)
#  index_program_participations_on_user_id_and_program_and_year  (user_id,program,year) UNIQUE WHERE (user_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class ProgramParticipation < ApplicationRecord
  OUTCOMES = %w[applied accepted granted completed withdrawn denied].freeze

  belongs_to :user, optional: true

  validates :program, inclusion: { in: ->(_) { KnotSettings.program_keys } }
  # A record keeps its own funder: one of the funders of its program.
  validates :funder, inclusion: { in: ->(record) { DataRetention.funders_for_program(record.program) } }, allow_blank: true
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :year, numericality: { only_integer: true, greater_than: 2000 }

  scope :live, -> { where.not(user_id: nil) }
  # Kept after the account was deleted, under a funder contract.
  scope :retained, -> { where(user_id: nil).where.not(retained_until: nil) }
  scope :retention_expired, -> { retained.where(retained_until: ..Time.current) }

  # Records the outcome for the member, the program and the year. A second
  # call for the same year changes the outcome.
  # funder names the funder of this record when the program has more than
  # one. With one funder, the record keeps that one.
  def self.record!(user, program:, outcome:, year: Date.current.year, funder: nil)
    row = find_or_initialize_by(user:, program: program.to_s, year:)
    row.update!(outcome: outcome.to_s, funder: funder.presence || row.funder || DataRetention.funder_for_program(program))
    row
  end

  def funder_key = funder.presence || DataRetention.funder_for_program(program)

  # The time an individual record stays after the account is deleted, or nil
  # when the funder does not require one.
  def individual_record_window = DataRetention.individual_record_window(funder_key, program:)

  # The time until the record stays after a deletion at from, or nil.
  def individual_record_until(from = Time.current) = DataRetention.individual_record_until(funder_key, program:, from:)

  def program_name = KnotSettings.program(program)&.name || program

end
