# frozen_string_literal: true

# Applies the retention windows each day (see DataRetention::Sweeps and
# config/kyc/data_retention.yml): verification audit records after their
# window (not under the fraud-evidence hold), financial anonymization,
# funder-required records that fold into the aggregates, guardian contact of
# adults, expired takeout files, and old webhook delivery logs.
class DataRetentionJob < ApplicationJob
  queue_as :low

  def perform
    counts = DataRetention::Sweeps.run_all
    Rails.logger.info("[DataRetentionJob] #{counts.to_json}") if counts.values.any?(&:positive?)
  end

end
