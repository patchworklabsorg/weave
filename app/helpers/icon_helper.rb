# frozen_string_literal: true

# Lucide is the Patchwork icon set (see internal-docs, design/icons.md).
# The lucide-rails gem bundles every icon; this wrapper fixes the size and
# the accessibility attributes so every call site reads the same.
#
#   icon(:search)                       # 16px, decorative
#   icon("log-out", size: 20)           # dashes or underscores both work
#   icon(:check, title: "Verified")     # announced to screen readers
module IconHelper
  def icon(name, size: 16, title: nil, **options)
    attributes = options.merge(width: size, height: size)
    if title
      # lucide-rails adds aria-hidden="true" by default; a labelled icon must
      # override it or assistive tech skips the label.
      attributes[:role] = "img"
      attributes["aria-label"] = title
      attributes["aria-hidden"] = "false"
    else
      attributes["aria-hidden"] = "true"
    end
    lucide_icon(name.to_s.tr("_", "-"), **attributes.transform_keys(&:to_s))
  end
end
