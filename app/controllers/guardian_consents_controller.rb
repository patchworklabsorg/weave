# frozen_string_literal: true

# The page a parent or guardian opens from the consent email (see
# GuardianConsent). No account is needed: the link token is the proof. The
# guardian reads what Patchwork Labs is and gives consent, and can later take
# it back from the same link.
class GuardianConsentsController < ApplicationController
  skip_before_action :authenticate_user!

  layout "sessions"

  before_action :set_consent

  def show
    render_state
  end

  def create
    return render_state unless @consent.pending? && !@consent.link_expired?

    @form_errors = {}
    # The member can't consent for themselves from their own session.
    @form_errors[:confirm] = t("guardian_consent.page.self_error", first_name: @user.first_name) if current_user&.id == @consent.user_id
    @form_errors[:confirm] ||= t("guardian_consent.page.confirm_error") unless params[:confirm] == "1"
    @form_errors[:signed_name] = t("guardian_consent.page.signed_name_error") if params[:signed_name].to_s.strip.blank?
    return render_state(status: :unprocessable_content) if @form_errors.any?

    GuardianConsentFlow.grant(@consent, token: params[:token], signed_name: params[:signed_name].to_s.strip.truncate(100),
                                        ip: request.remote_ip, user_agent: request.user_agent)
    redirect_to guardian_consent_path(token: params[:token])
  end

  def destroy
    GuardianConsentFlow.revoke(@consent) if @consent.granted?
    redirect_to guardian_consent_path(token: params[:token])
  end

  private

  def set_consent
    @consent = GuardianConsent.for_token(params[:token])
    @user = @consent&.user
    render_state(status: :not_found) if @consent.nil? || @user.nil?
  end

  # One page, with a part for each state of the consent.
  def render_state(status: :ok)
    @state = if @consent.nil? || @consent.superseded? then :invalid
             elsif @consent.pending? then @consent.link_expired? ? :expired : :form
             else
               @consent.status.to_sym
             end
    render :show, status:
  end

end
