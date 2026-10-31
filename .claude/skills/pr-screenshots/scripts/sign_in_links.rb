# frozen_string_literal: true

# Prints a one-time sign-in link for each email in EMAILS (comma-separated).
#
#   EMAILS=a@example.com,b@example.com DATABASE_URL=... RAILS_ENV=test \
#     bin/rails runner .claude/skills/pr-screenshots/scripts/sign_in_links.rb
#
# Each link works once. A failed sign-in uses it up, so print new links before
# each run.
port = ENV.fetch("PORT", "3077")
ENV.fetch("EMAILS").split(",").map(&:strip).each do |email|
  link = User::MagicLink.issue!(User.find_by!(email:))
  puts "#{email} http://127.0.0.1:#{port}/auth/magic_link/#{link.token}"
end
