# frozen_string_literal: true

# Delay a member's break-glass notice for an active fraud investigation, or
# sign off or lift the delay (see BreakGlass.delay_member_notice).
class Identity::BreakGlassNoticesController < Identity::BaseController
  # An owner signs off a fraud delay even when they are not on the identity
  # team (see BreakGlass.may_sign_off_delay?).
  skip_before_action :require_identity_team, only: :sign_off_delay
  before_action :set_notice

  def delay
    if BreakGlass.delay_member_notice(@notice, by: current_user, reason: params[:reason].to_s.strip)
      redirect_to identity_break_glass_records_path,
                  notice: "The delay is asked for. An owner or the identity team lead must sign it off. The lead was told."
    else
      redirect_to identity_break_glass_records_path, alert: "Give the reason for the delay. Only an unsent member notice can be delayed."
    end
  end

  def sign_off_delay
    if BreakGlass.sign_off_delay(@notice, by: current_user)
      redirect_to identity_break_glass_records_path,
                  notice: "You signed off the delay. It holds the notice until #{@notice.delay_ends_at.utc.strftime('%b %-d %H:%M UTC')} at the latest."
    else
      redirect_to identity_break_glass_records_path,
                  alert: "Only an owner or the identity team lead can sign off a delay, and never the person who asked for the delay or the access."
    end
  end

  def lift_delay
    if BreakGlass.lift_delay(@notice, by: current_user)
      redirect_to identity_break_glass_records_path, notice: "The delay is lifted. The member will get the notice."
    else
      redirect_to identity_break_glass_records_path, alert: "This notice is not delayed."
    end
  end

  private

  def set_notice
    @notice = BreakGlassNotice.find_by_public_param!(params[:id])
  end

end
