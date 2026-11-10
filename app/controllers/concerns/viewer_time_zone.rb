# frozen_string_literal: true

# Shows every time on a page in the viewer's time zone (see TimeHelper and
# the "Times are local" rule in the internal-docs design guide).
#
# The zone comes from, in order:
# 1. the tz cookie, which app/javascript/application.js sets from the
#    browser on every page load, so it follows the device in use now;
# 2. the zone of the current session, saved at sign-in;
# 3. UTC.
module ViewerTimeZone
  extend ActiveSupport::Concern

  COOKIE = "tz"

  included do
    around_action :use_viewer_time_zone
    helper_method :viewer_time_zone
  end

  private

  def use_viewer_time_zone(&) = Time.use_zone(viewer_time_zone, &)

  def viewer_time_zone
    @viewer_time_zone ||= TimeHelper.find_zone(cookies[COOKIE]) ||
                          TimeHelper.find_zone(current_user_session&.timezone) ||
                          ActiveSupport::TimeZone["UTC"]
  end
end
