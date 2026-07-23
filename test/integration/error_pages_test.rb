# frozen_string_literal: true

require "test_helper"

class ErrorPagesTest < ActiveSupport::TestCase
  # Pure file-content checks — no database or fixtures needed.
  self.fixture_table_names = []

  PAGES = {
    "400.html"                     => "400",
    "404.html"                     => "404",
    "406-unsupported-browser.html" => "406",
    "422.html"                     => "422",
    "500.html"                     => "500",
    "503.html"                     => "503"
  }.freeze

  PAGES.each do |file, code|
    test "#{file} is branded and self-contained" do
      path = Rails.public_path.join(file)
      assert path.exist?, "expected public/#{file} to exist"

      html = path.read
      assert_includes html, %(<p class="code">#{code}</p>)
      assert_includes html, "Weave · Patchwork Labs"

      # Static error pages must not depend on the asset pipeline or
      # external hosts — they are served when the app itself is down.
      assert_no_match(/<%/, html)
      assert_no_match(/(?:src|href)="https?:\/\//, html)
      assert_no_match(/\/assets\//, html)
    end
  end

end
