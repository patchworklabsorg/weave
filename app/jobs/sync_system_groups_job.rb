# frozen_string_literal: true

# Repairs drift in the system groups (staff, board, ...). User callbacks keep
# them in sync as attributes change; this job catches changes that skipped
# callbacks, such as update_column or raw SQL.
class SyncSystemGroupsJob < ApplicationJob
  queue_as :low

  def perform
    PaperTrail.request(whodunnit: "SyncSystemGroupsJob") do
      SystemGroups.sync_all
    end
  end

end
