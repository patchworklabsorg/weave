# frozen_string_literal: true

# The member's data export (see Takeout): ask for an export and download it.
class TakeoutsController < ApplicationController
  # An admin who impersonates a member must not export the member's data.
  before_action :refuse_impersonation, only: %i[create download]

  def show
    @takeouts = current_user.takeout_requests.order(created_at: :desc).limit(5)
  end

  def create
    result = Takeout.request!(current_user)
    if result.success?
      redirect_to takeout_path, notice: t("data_handling.takeout.requested")
    else
      redirect_to takeout_path, alert: result.errors[:base]
    end
  end

  def download
    takeout = current_user.takeout_requests.find_by_public_param(params[:id])
    return redirect_to(takeout_path, alert: t("data_handling.takeout.errors.unavailable")) unless takeout&.downloadable?

    takeout.update!(downloaded_at: Time.current)
    response.headers["Cache-Control"] = "no-store"
    send_data takeout.archive.download, type: "application/json", disposition: "attachment",
                                        filename: takeout.archive.filename.to_s
  end

  private

  def refuse_impersonation
    redirect_to takeout_path, alert: t("data_handling.impersonating") if impersonating?
  end

end
