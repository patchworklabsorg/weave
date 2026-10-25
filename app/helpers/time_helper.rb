# frozen_string_literal: true

# One way to show a time in the interface. Every view goes through here, so
# a date reads the same on a member page, an admin table and an audit log.
#
#   time_label(user.created_at)             -> <time datetime="…">Oct 25, 2026</time>
#   time_label(event.at, :datetime)         -> "Oct 25, 2026, 15:38 UTC"
#   time_label(user.last_seen_at, :relative) -> "3 days ago", the absolute time in title
#   time_label(user.slack_start_date, :month) -> "October 2026"
#   time_label(user.birthday, :day)         -> "October 25" (no year)
#   time_label(nil)                         -> nil, so `|| "Never"` works
#
# Times show in UTC, which is the app's time zone, and say so. Dates have no
# zone to show.
module TimeHelper
  FORMATS = {
    date: "%b %-d, %Y",
    datetime: "%b %-d, %Y, %H:%M UTC",
    month: "%B %Y",
    day: "%B %-d"
  }.freeze

  def time_label(value, style = :date, **options)
    return if value.blank?

    time = value.respond_to?(:utc) ? value.utc : value
    if style == :relative
      text = "#{time_ago_in_words(time)} ago"
      options[:title] ||= time.strftime(FORMATS[:datetime])
    else
      text = time.strftime(FORMATS.fetch(style))
    end
    time_tag(time, text, **options)
  end
end
