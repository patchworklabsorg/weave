# frozen_string_literal: true

# One way to show a time in the interface. Every view goes through here, so
# a date reads the same on a member page, an admin table and an audit log.
#
#   time_label(user.created_at)             -> <time datetime="…">Oct 25, 2026</time>
#   time_label(event.at, :datetime)         -> "Oct 25, 2026, 11:38 AM EDT"
#   time_label(user.last_seen_at, :relative) -> "3 days ago", the full time in title
#   time_label(user.slack_start_date, :month) -> "October 2026"
#   time_label(user.birthday, :day)         -> "October 25" (no year)
#   time_label(nil)                         -> nil, so `|| "Never"` works
#
# A timestamp shows in Time.zone, which is the viewer's zone on a page
# (ViewerTimeZone) and the recipient's zone in an email (ApplicationMailer).
# The zone is always named, and the title gives the UTC time, so two people
# in different zones can compare. A Date has no zone and never moves.
# The datetime attribute is always UTC.
module TimeHelper
  FORMATS = {
    date: "%b %-d, %Y",
    datetime: "%b %-d, %Y, %-I:%M %p %Z",
    month: "%B %Y",
    day: "%B %-d"
  }.freeze

  UTC_FORMAT = "%b %-d, %Y, %H:%M UTC"

  def time_label(value, style = :date, **options)
    return if value.blank?

    format = FORMATS.fetch(style) unless style == :relative
    return time_tag(value, value.strftime(format), **options) unless value.acts_like?(:time)

    time = value.in_time_zone
    utc = time.utc.strftime(UTC_FORMAT)
    if style == :relative
      text = "#{time_ago_in_words(time)} ago"
      options[:title] ||= time.utc_offset.zero? && time.zone == "UTC" ? utc : "#{time.strftime(FORMATS[:datetime])} (#{utc})"
    else
      text = time.strftime(format)
      options[:title] ||= utc
    end
    time_tag(time, text, datetime: time.utc.iso8601, **options)
  end

  # Plain text for an email or a Slack message: the time in Time.zone, with
  # the zone named.
  def self.time_text(value, style = :datetime)
    return "" if value.blank?

    value = value.in_time_zone if value.acts_like?(:time)
    value.strftime(FORMATS.fetch(style))
  end

  # The zone for an IANA name from a browser, or nil when the name is blank
  # or the tz database does not know it.
  def self.find_zone(name)
    ActiveSupport::TimeZone[name.to_s.first(64)] if name.present?
  end
end
