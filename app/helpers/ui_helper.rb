# frozen_string_literal: true

# View helpers for the shared UI vocabulary. The CSS classes live in
# app/assets/tailwind/application.css and are documented in internal-docs,
# design/components.md. These helpers only save typing for the pieces that
# carry logic (tones, active states, errors).
module UiHelper
  BADGE_TONES = %i[neutral grape violet orchid sky teal success info warning danger solid outline].freeze

  # badge("Verified", tone: :success)
  # badge("Admin", tone: :grape, icon: :shield_check)
  def badge(text, tone: :neutral, icon: nil, **options)
    raise ArgumentError, "unknown badge tone #{tone.inspect}" unless BADGE_TONES.include?(tone.to_sym)

    classes = ["badge", ("badge-#{tone}" unless tone.to_sym == :neutral), options.delete(:class)].compact.join(" ")
    tag.span(class: classes, **options) do
      safe_join([(icon(icon, size: 12) if icon), text].compact)
    end
  end

  # page_header("Users", lede: "Everyone with a Weave account.") do
  #   link_to "New user", new_admin_user_path, class: "btn btn-primary"
  # end
  def page_header(title, lede: nil, title_tag: :h1, &block)
    tag.header(class: "page-header") do
      heading = tag.div do
        safe_join([
          content_tag(title_tag, title, class: "page-title"),
          (tag.p(lede, class: "page-lede") if lede)
        ].compact)
      end
      actions = block ? tag.div(class: "page-actions", &block) : nil
      safe_join([heading, actions].compact)
    end
  end

  # nav_link("Users", admin_users_path, icon: :users)
  # Marks the link current when the request path starts with the href, so a
  # section stays lit on its child pages. Pass active: to decide yourself.
  def nav_link(label, path, icon: nil, active: nil, exact: false, **options)
    active = nav_active?(path, exact:) if active.nil?
    classes = ["nav-link", options.delete(:class)].compact.join(" ")
    options["aria-current"] = "page" if active
    link_to(path, class: classes, **options) do
      safe_join([(icon(icon) if icon), tag.span(label)].compact)
    end
  end

  def nav_active?(path, exact: false)
    current = request.path
    return current == path if exact || path == "/"

    current == path || current.start_with?("#{path}/")
  end

  # empty_state("No groups yet", body: "Create a group to give users access to an app.", icon: :users) do
  #   link_to "New group", new_admin_group_path, class: "btn btn-primary"
  # end
  def empty_state(title, body: nil, icon: nil, &block)
    tag.div(class: "empty") do
      safe_join([
        (icon(icon, size: 28) if icon),
        tag.p(title, class: "empty-title"),
        (tag.p(body, class: "empty-body") if body),
        (capture(&block) if block)
      ].compact)
    end
  end

  # The validation summary above a form. Renders nothing without errors.
  def form_errors(record)
    return if record.errors.empty?

    render "shared/form_errors", record: record
  end

  # A value next to a button that copies it. Wires the clipboard controller.
  #   copy_button(application.uid)
  #   copy_button(uri, label: "Copy redirect URI")
  def copy_button(value, label: "Copy", **options)
    tag.div(class: "copyable", data: { controller: "clipboard", clipboard_text_value: value }) do
      safe_join([
                  tag.code(value, class: "code-chip"),
                  tag.button(type: "button", class: "btn btn-secondary btn-sm btn-icon", title: label, "aria-label": label,
                             data: { action: "clipboard#copy", clipboard_target: "button" }, **options) do
                    safe_join([icon(:copy, class: "copy-idle"), icon(:check, class: "copy-done", hidden: true)])
                  end
                ])
    end
  end

  # avatar(user)            -> 40px initials or Slack photo
  # avatar(user, size: :xl) -> 80px
  def avatar(user, size: nil)
    classes = ["avatar", ("avatar-#{size}" if size)].compact.join(" ")
    if user.respond_to?(:slack_profile_image_url) && user.slack_profile_image_url.present?
      image_tag(user.slack_profile_image_url, alt: user.full_name, class: classes)
    else
      tag.span(user.initials.to_s.upcase, class: classes, "aria-label": user.full_name, role: "img")
    end
  end

  # dl_row("Email", user.email)
  # dl_row("Role") { badge(user.role.humanize, tone: :grape) }
  def dl_row(label, value = nil, &block)
    tag.div(class: "dl-row") do
      safe_join([tag.dt(label), tag.dd(block ? capture(&block) : value)])
    end
  end
end
