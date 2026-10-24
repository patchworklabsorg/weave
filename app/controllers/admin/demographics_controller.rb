# frozen_string_literal: true

# Demographics aggregates for funder reports (see DemographicsReport). The
# page shows only the latest report, after small-count suppression. It can't
# show a member's answers: the web app has no key to open them.
#
# Only the latest report is shown, because two reports side by side can show
# one member's answer by their difference.
class Admin::DemographicsController < Admin::BaseController
  RUN_HISTORY = 10

  def show
    @report = DemographicReport.latest
    @runs = DemographicReport.order(generated_at: :desc).limit(RUN_HISTORY).pluck(:generated_at, :run_by)
    # The threshold the shown report used, which can differ from the config now.
    @threshold = @report&.threshold || DemographicsVault.small_count_threshold
  end

end
