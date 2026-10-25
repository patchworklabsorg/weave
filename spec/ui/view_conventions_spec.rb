# frozen_string_literal: true

require "rails_helper"

# The interface rules from docs/UI.md that a file scan can hold. Each check
# names the files that break it. If one fails, fix the view: do not add an
# exception here unless the file is outside the design system (mailers, the
# static error pages and the PWA manifest already are).
RSpec.describe "View conventions" do # rubocop:disable RSpec/DescribeClass
  root = Rails.root

  # Mailers use inline styles for email clients; the PWA manifest is JSON.
  outside_the_system = ->(path) { path.include?("_mailer/") || path.include?("/layouts/mailer.") || path.include?("/pwa/") }

  views = Dir.glob(root.join("app/views/**/*.erb"))
             .map { |path| Pathname(path).relative_path_from(root).to_s }
             .reject(&outside_the_system)
             .sort

  # ERB comments explain code and may quote anything.
  strip_comments = ->(text) { text.gsub(/<%#.*?%>/m, "") }

  def offenders(views, root, strip_comments)
    views.filter_map do |path|
      text = strip_comments.call(File.read(root.join(path)))
      lines = text.lines.each_with_index.filter_map { |line, index| "#{path}:#{index + 1}" if yield(line, text) }
      lines unless lines.empty?
    end.flatten
  end

  it "scans the member, admin and focus views" do
    expect(views).to include("app/views/users/show.html.erb", "app/views/admin/users/index.html.erb", "app/views/auth/_magic_link_form.html.erb")
    expect(views).not_to include("app/views/user_mailer/magic_link.html.erb")
  end

  it "shows every date and time through time_label" do
    bad = offenders(views, root, strip_comments) do |line, _|
      line.match?(/strftime\(|to_fs\(:|time_ago_in_words|(?<![a-z_])l\(/) &&
        !line.include?("TimeHelper::FORMATS") && !line.include?("%H:%M UTC")
    end
    expect(bad).to be_empty, "use time_label (app/helpers/time_helper.rb) in:\n#{bad.join("\n")}"
  end

  it "calls the public identifier the Weave ID" do
    bad = offenders(views, root, strip_comments) { |line, _| line.match?(/PWL ID|PWL id|\bP_ID\b/) }
    expect(bad).to be_empty, "say Weave ID in:\n#{bad.join("\n")}"
  end

  it "uses tokens, never a hex color or a raw Tailwind palette color" do
    palette = /\b(bg|text|border|ring|fill|stroke|from|to|via|outline|decoration|shadow)-(red|green|blue|yellow|gray|grey|slate|zinc|neutral|stone|purple|indigo|violet|pink|rose|orange|amber|lime|emerald|teal|cyan|sky|fuchsia)-\d{2,3}\b/
    bad = offenders(views - ["app/views/shared/_head.html.erb"], root, strip_comments) do |line, _|
      line.match?(/#[0-9a-fA-F]{6}\b/) || line.match?(palette)
    end
    expect(bad).to be_empty, "use a token utility (bg-paper, text-ink-soft, border-hairline) in:\n#{bad.join("\n")}"
  end

  it "has no inline style attributes" do
    bad = offenders(views, root, strip_comments) { |line, _| line.match?(/\sstyle="/) }
    expect(bad).to be_empty, "use a class, or the hidden attribute, in:\n#{bad.join("\n")}"
  end

  it "has no emoji and no em dash in a sentence" do
    bad = offenders(views, root, strip_comments) do |line, _|
      line.match?(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/) || line.match?(/\p{L} — \p{L}/)
    end
    expect(bad).to be_empty, "no emoji in the interface; write two sentences instead of an em dash in:\n#{bad.join("\n")}"
  end

  # Turbo ignores a form with data-turbo="false", so data-turbo-confirm on it
  # never asks. Those forms confirm through the confirm-submit controller.
  it "never puts turbo_confirm on a form with Turbo off" do
    bad = views.flat_map do |path|
      text = strip_comments.call(File.read(root.join(path)))
      text.scan(/<%=?.*?%>/m).filter_map do |tag|
        "#{path}: #{tag.lines.first.strip}" if tag.include?("turbo_confirm") && tag.match?(/turbo:\s*false/)
      end
    end
    expect(bad).to be_empty, "use confirm-submit (see admin/users/index) in:\n#{bad.join("\n")}"
  end

  it "gives every page a title" do
    pages = views.reject { |path| File.basename(path).start_with?("_") || path.include?("/layouts/") || path.include?("/shared/") }
    bad = pages.reject { |path| File.read(root.join(path)).match?(/content_for[ (]:title/) }
    expect(bad).to be_empty, "add <% content_for :title, \"…\" %> to:\n#{bad.join("\n")}"
  end

  it "starts every layout with a skip link and names the main landmark" do
    layouts = views.select { |path| path.include?("/layouts/") }
    bad = layouts.reject do |path|
      text = File.read(root.join(path))
      text.include?('class="skip-link"') && text.include?('id="main"')
    end
    expect(bad).to be_empty, "add the skip link and id=\"main\" to:\n#{bad.join("\n")}"
  end

  it "keeps a wide table inside a scrolling wrapper" do
    bad = views.select do |path|
      text = strip_comments.call(File.read(root.join(path)))
      text.include?("<table") && !text.include?("table-wrap")
    end
    expect(bad).to be_empty, "wrap the table in <div class=\"table-wrap\"> in:\n#{bad.join("\n")}"
  end

  it "keeps the design tokens as light-dark() pairs" do
    css = File.read(root.join("app/assets/tailwind/application.css"))
    theme = css[/@theme \{.*?\n\}/m]
    colors = theme.scan(/--color-[a-z-]+:\s*([^;]+);/).flatten
    plain = colors.reject { |value| value.start_with?("light-dark(") }
    expect(plain).to be_empty, "every --color-* token needs a light-dark() pair: #{plain.join(', ')}"
  end
end
