# frozen_string_literal: true

# One run of the deletion pipeline for a DeletionRequest (see
# DeletionPipeline). steps lists each step in order, with its result and the
# time. A failed run keeps its error, so every run is logged.
# == Schema Information
#
# Table name: deletion_runs
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  error_class         :string
#  error_message       :text
#  finished_at         :datetime
#  outcome             :string           default("running"), not null
#  started_at          :datetime         not null
#  steps               :jsonb            not null
#  deletion_request_id :bigint           not null
#
# Indexes
#
#  index_deletion_runs_on_deletion_request_id  (deletion_request_id)
#
# Foreign Keys
#
#  fk_rails_...  (deletion_request_id => deletion_requests.id) ON DELETE => cascade
#
class DeletionRun < ApplicationRecord
  OUTCOMES = %w[running completed failed].freeze

  belongs_to :deletion_request

  validates :outcome, inclusion: { in: OUTCOMES }

  def step_names = steps.map { |step| step["step"] }

end
