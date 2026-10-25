# frozen_string_literal: true

# GET /api/v1/directory/users/:sub/shipping_address
#
# A patch app reads a member's shipping address when it ships, to print the
# label. The app must not store the address: it asks again for each shipment,
# so a change or a deletion in Weave applies at once.
#
# The token needs the `fulfillment` app scope. An unknown user, a user the app
# may not serve and a user with no complete shipping address all give 404.
# Each read writes a LockboxAudit row, which the user's admin page shows.
module Api
  module V1
    module Directory
      class ShippingAddressesController < BaseController
        self.app_scope = "fulfillment"

        def show
          response.headers["Cache-Control"] = "no-store"

          user = User.find_by(p_id: params[:user_sub])
          return render_not_found unless user && AppAccess.permitted?(user, current_application)

          address = user.shipping_address
          return render_not_found unless address&.complete?

          LockboxAudit.create!(subject: user, viewer: current_application, context: LockboxAudit::SHIPPING_ADDRESS_READ,
                               data: { sub: user.p_id, address_id: address.public_id }, ip: request.remote_ip)

          render json: ShippingLabelSerializer.new(user, address).as_json
        end

      end
    end
  end
end
