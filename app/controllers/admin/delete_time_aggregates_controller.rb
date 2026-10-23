# frozen_string_literal: true

# The delete-time aggregates for funder reports: counts of departed members,
# after small-count suppression (see DeleteTimeAggregates). Never a row per
# person.
class Admin::DeleteTimeAggregatesController < Admin::BaseController
  def show
    @report = DeleteTimeAggregates.report
  end

end
