# frozen_string_literal: true

# Shows every time on a page in the viewer's time zone (see TimeHelper and
# the "Times are local" rule in the internal-docs design guide).
#
# The zone applies only while the view renders. The action itself, the
# models, webhooks, exports and every job it enqueues stay in UTC, so a
# viewer's zone (a cookie the client sets) never moves a date range, an age
# check or a stored value.
#
# The zone comes from, in order:
# 1. the tz cookie, which app/javascript/application.js sets from the
#    browser on every page load, so it follows the device in use now;
# 2. the zone of the current session, saved at sign-in;
# 3. UTC.
#
# A form that takes a time sends the browser zone in a hidden time_zone field
# (the time-zone Stimulus controller). form_time reads the value in that zone.
module ViewerTimeZone
  extend ActiveSupport::Concern

  COOKIE = "tz"

  class UnknownTimeZone < StandardError; end

  included do
    helper_method :viewer_time_zone
    rescue_from UnknownTimeZone, with: :refuse_unknown_time_zone
  end

  def render_to_body(options = {})
    Time.use_zone(viewer_time_zone) { super }
  end

  private

  def viewer_time_zone
    @viewer_time_zone ||= TimeHelper.find_zone(cookies[COOKIE]) ||
                          TimeHelper.find_zone(viewer_session_time_zone) ||
                          ActiveSupport::TimeZone["UTC"]
  end

  def viewer_session_time_zone
    current_user_session&.timezone if respond_to?(:current_user_session, true)
  end

  # The zone a form sent. No zone (no JavaScript) means UTC. A zone that
  # Weave does not know gives nil, so the time is not read as UTC by mistake.
  def form_time_zone(name = params[:time_zone])
    return ActiveSupport::TimeZone["UTC"] if name.blank?

    TimeHelper.find_zone(name)
  end

  # A datetime-local value from a form, read in the zone the form sent.
  def form_time(value)
    return if value.blank?

    zone = form_time_zone or raise UnknownTimeZone, params[:time_zone].to_s.first(64)
    zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def refuse_unknown_time_zone(error)
    redirect_back fallback_location: root_path,
                  alert: "Weave does not know the time zone #{error.message}, so it saved nothing. Tell the Weave team."
  end
end
