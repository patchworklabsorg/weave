# frozen_string_literal: true

# The member's own demographics form (see DemographicsVault). The member can
# answer, answer again, or take their answers back. The form always starts
# empty: Weave has no way to read the answers back, not even for the member.
#
# Apps send the member here before their first grant application (Krater
# reads `demographics_answered` in the directory API). return_to sends the
# member back to the app after they save.
class DemographicsController < ApplicationController
  # An admin who impersonates a member must not answer for them or take their
  # answers back.
  before_action :refuse_impersonation

  def show
    @answered_at = DemographicsVault.answered_at(current_user)
    @available = DemographicsVault.available?
    @return_to = safe_return_to
  end

  def update
    return redirect_to(demographics_path, alert: t("demographics.form.unavailable")) unless DemographicsVault.available?

    result = DemographicsVault.record(current_user, submitted_answers)
    if result.success?
      redirect_to (safe_return_to || demographics_path), notice: t("demographics.form.saved"), allow_other_host: true
    else
      @answered_at = DemographicsVault.answered_at(current_user)
      @available = true
      @return_to = safe_return_to
      @form_errors = result.errors
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    DemographicsVault.withdraw!(current_user)
    redirect_to profile_path, notice: t("demographics.form.withdrawn")
  end

  private

  # The answers from the form. A malformed "demographics" param counts as no
  # answers, not as a server error.
  def submitted_answers
    raw = params[:demographics]
    raw.is_a?(ActionController::Parameters) ? raw.permit(*DemographicsVault.permitted_params) : {}
  end

  # return_to, only when it is on the origin of a registered OAuth app
  # redirect URI. Anything else is dropped, so this is no open redirect.
  def safe_return_to
    uri = URI.parse(params[:return_to].to_s)
    return unless uri.is_a?(URI::HTTP) && uri.host.present?

    origin = [uri.scheme, uri.host, uri.port]
    allowed = Doorkeeper::Application.pluck(:redirect_uri).flat_map { |uris| uris.to_s.split }.any? do |redirect_uri|
      registered = URI.parse(redirect_uri)
      [registered.scheme, registered.host, registered.port] == origin
    rescue URI::InvalidURIError
      false
    end
    uri.to_s if allowed
  rescue URI::InvalidURIError
    nil
  end

  def refuse_impersonation
    redirect_to profile_path, alert: t("demographics.form.impersonating") if impersonating?
  end

end
