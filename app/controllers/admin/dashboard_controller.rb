# frozen_string_literal: true

class Admin::DashboardController < Admin::BaseController
  def index
    # Admin dashboard stats
    @users_count = User.count
    @admin_count = User.admin.count

    # API metrics data
    prepare_api_metrics
  end

  private



end
