# frozen_string_literal: true

# Labels for the admin Thread Count pages (see ThreadCount). Admin only: the
# score never appears in a member-facing view.
module ThreadCountHelper
  def thread_count_label(kind, level = nil)
    label = t("admin.thread_count.kinds.#{kind}", default: kind.to_s.humanize)
    return label if level.blank?

    "#{label}: #{t("admin.thread_count.levels.#{level}", default: level.to_s.humanize)}"
  end

  def thread_count_number(value)
    number_with_precision(value, precision: 1, strip_insignificant_zeros: true)
  end

end
