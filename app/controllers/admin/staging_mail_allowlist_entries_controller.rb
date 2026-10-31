# frozen_string_literal: true

# Staging only: an owner allows an address or a domain to receive mail from
# staging, with no credentials change and no deploy (see
# StagingMailAllowlistEntry). Answers 404 everywhere else.
class Admin::StagingMailAllowlistEntriesController < Admin::BaseController
  before_action :require_staging_owner

  def index
    @entries = StagingMailAllowlistEntry.includes(:created_by).order(:entry)
    @entry = StagingMailAllowlistEntry.new
    @credential_count = Array(Weave.mail_allowlist).size
  end

  def create
    @entry = StagingMailAllowlistEntry.new(entry: params.dig(:staging_mail_allowlist_entry, :entry), created_by: current_user)
    if @entry.save
      redirect_to admin_staging_mail_allowlist_entries_path, notice: "Staging can now mail #{@entry.entry}."
    else
      @entries = StagingMailAllowlistEntry.includes(:created_by).order(:entry)
      @credential_count = Array(Weave.mail_allowlist).size
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    entry = StagingMailAllowlistEntry.find(params[:id])
    entry.destroy!
    redirect_to admin_staging_mail_allowlist_entries_path, notice: "Staging no longer mails #{entry.entry}."
  end

  private

  def require_staging_owner
    raise ActionController::RoutingError, "Not Found" unless StagingTools.allowed?(current_user)
  end

end
