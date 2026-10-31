# frozen_string_literal: true

# A member's shipping address as a patch app gets it to print one label (see
# Api::V1::Directory::ShippingAddressesController). Only the fields a label
# needs: no coordinates, no email, no delivery notes.
class ShippingLabelSerializer
  def initialize(user, address)
    @user = user
    @address = address
  end

  def as_json(*)
    {
      sub: @user.p_id,
      name: recipient_name,
      # Carriers ask for a phone number on most international labels.
      phone: @address.contact_phone_number.presence,
      **AddressSerializer.new(@address).as_json.except(:address_type, :latitude, :longitude)
    }
  end

  private

  # The contact name on the address, or the member's first and last name. Nil
  # when Weave has neither.
  def recipient_name
    [@address.contact_first_name, @address.contact_last_name].compact_blank.join(" ").presence ||
      @address.contact_name.presence ||
      @user.full_name.presence
  end

end
