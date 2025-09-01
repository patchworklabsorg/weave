# frozen_string_literal: true

class Admin::DashboardController < Admin::BaseController
  def index
    # Admin dashboard stats
    @users_count = User.count
    # @admin_count is all the users in the :admin scope
    @admin_count = User.admin.count

  end

  private



end
