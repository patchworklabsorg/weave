# frozen_string_literal: true

# A preview of each funder's aggregate report (see FunderReport). Admins only.
# Counts and sums after the funder's own small-count threshold: nothing here
# names or links to a member. There is no export and no send yet.
class Admin::FunderReportsController < Admin::BaseController
  def index
    @profiles = FunderProfiles.all
  end

  def show
    profile = FunderProfiles.find(params[:funder])
    return redirect_to(admin_funder_reports_path, alert: "There is no funder #{params[:funder]}.") if profile.nil?

    @report = FunderReport.build(profile)
  end

end
