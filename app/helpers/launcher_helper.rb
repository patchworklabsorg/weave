# frozen_string_literal: true

# The app launcher on the member dashboard (see AppLauncher).
module LauncherHelper
  # The app's icon, or its first letter when it has none. The icon URL is
  # validated as https (see OauthApplicationLauncher).
  def app_icon(application, size: :lg)
    classes = ["avatar", ("avatar-#{size}" if size)].compact.join(" ")
    if application.launcher_icon_url.present?
      image_tag(application.launcher_icon_url, alt: "", class: classes)
    else
      tag.span(application.name.to_s.first.to_s.upcase, class: classes, "aria-hidden": "true")
    end
  end
end
