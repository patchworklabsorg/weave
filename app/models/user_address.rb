# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
#
# STI subclass for user-specific addresses
# Inherits all functionality from Address with user-specific validations and methods
#
class UserAddress < Address
  # Additional validations specific to user addresses
  validates :addressable_type, inclusion: { in: ["User"] }

  # We could add more restrictive address type validation here if needed
  # For now, relying on the base Address model's enum validation

  # User-specific methods
  def user
    addressable
  end

  # Override to provide user-specific validation messages
  def self.human_attribute_name(attr, options = {})
    case attr.to_s
    when "addressable"
      "User"
    else
      super
    end
  end

end
