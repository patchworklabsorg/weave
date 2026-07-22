# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::BaseController, type: :controller do
  subject(:controller_instance) { described_class.new }

  describe "#filter_sensitive_headers" do
    it "redacts sensitive headers given as raw Rack env keys" do
      headers = {
        "HTTP_AUTHORIZATION" => "Bearer super-secret-token",
        "HTTP_X_API_KEY" => "sk_live_deadbeef",
        "HTTP_COOKIE" => "session=abc123",
        "HTTP_X_FORWARDED_FOR" => "203.0.113.10",
        "HTTP_ACCEPT" => "application/json"
      }

      filtered = controller_instance.send(:filter_sensitive_headers, headers)

      expect(filtered).not_to have_key("HTTP_AUTHORIZATION")
      expect(filtered).not_to have_key("HTTP_X_API_KEY")
      expect(filtered).not_to have_key("HTTP_COOKIE")
      expect(filtered).not_to have_key("HTTP_X_FORWARDED_FOR")
      expect(filtered).to have_key("HTTP_ACCEPT")
    end

    it "redacts sensitive headers given as normalized hyphenated names" do
      headers = {
        "authorization" => "Bearer secret",
        "X-Api-Key" => "sk_live_x",
        "Accept" => "application/json"
      }

      filtered = controller_instance.send(:filter_sensitive_headers, headers)

      expect(filtered).not_to have_key("authorization")
      expect(filtered).not_to have_key("X-Api-Key")
      expect(filtered).to have_key("Accept")
    end
  end
end
