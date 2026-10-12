# frozen_string_literal: true

module FeatureFlags
  # Finds the user that an admin means by a value typed in the Flipper UI.
  #
  # Flipper matches a user only on the exact flipper_id, which is the p_id (for
  # example PWL1A2B3C4D5E). An admin usually has something else to hand, so this
  # accepts each of these, with extra spaces and any letter case:
  #
  # - a p_id: PWL1A2B3C4D5E, or pwl1a2b3c4d5e
  # - a public id: usr_k5qx9z
  # - an email: the primary email, a confirmed secondary email, or "Name <email>"
  # - a Slack member id: U012AB3CD
  module UserLookup
    PUBLIC_ID_PREFIX = /\Ausr_/i
    BRACKETED_EMAIL = /<([^<>@\s]+@[^<>\s]+)>/

    # Returns the user, or nil if the value matches no user.
    def self.call(value)
      value = value.to_s.strip
      return if value.empty?

      if value.include?("@")
        by_email(value)
      elsif value.match?(PUBLIC_ID_PREFIX)
        # The hash part of a public id is case sensitive, so fix only the prefix.
        User.find_by_public_id(value.sub(PUBLIC_ID_PREFIX, "usr_"))
      else
        User.find_by(p_id: value.upcase) || User.find_by(slack_id: value.upcase)
      end
    end

    def self.by_email(value)
      email = (value[BRACKETED_EMAIL, 1] || value).delete_prefix("mailto:").strip.downcase

      # An unconfirmed address is not proof that it belongs to that user.
      User.find_by(email:) ||
        EmailAddress.where.not(confirmed_at: nil).find_by(email:)&.user
    end
    private_class_method :by_email
  end
end
