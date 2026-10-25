# frozen_string_literal: true

require "rails_helper"

# A patch app reads a member's shipping address when it ships, and must not
# store it. Each read is audited.
RSpec.describe "Shipping address API", type: :request do
  let(:application) do
    Doorkeeper::Application.create!(name: "Hardware Patch", redirect_uri: "https://hardware.example.com/cb",
                                    scopes: "openid profile fulfillment")
  end
  let(:member) { create(:user, :verified, :accepted_code_of_conduct, first_name: "Ada", last_name: "Lovelace") }
  let(:path) { api_v1_directory_user_shipping_address_path(member.p_id) }

  def app_token(app = application, scopes: "fulfillment")
    Doorkeeper::AccessToken.create!(application: app, scopes: scopes).plaintext_token
  end

  def shipping_get(path, token: app_token)
    get path, headers: { "Authorization" => "Bearer #{token}" }
    response.parsed_body
  end

  def add_address(user = member, **attributes)
    create(:shipping_address, addressable: user, line1: "1 Main St", line2: "Apt 2", city: "Boston", state: "MA",
                              postal_code: "02115", country: "US", latitude: 42.34, longitude: -71.09,
                              contact_email: nil, shipping_notes: "Leave at the door", **attributes)
  end

  describe "GET /api/v1/directory/users/:sub/shipping_address" do
    it "returns the fields a label needs" do
      address = add_address(contact_name: "A. Lovelace", contact_phone_number: "+1 617 555 0123")

      body = shipping_get(path)

      expect(response).to have_http_status(:ok)
      expect(body).to eq(
        "sub" => member.p_id, "name" => "A. Lovelace", "phone" => "+16175550123", "id" => address.public_id,
        "line1" => "1 Main St", "line2" => "Apt 2", "line3" => nil, "city" => "Boston", "state" => "MA",
        "postal_code" => "02115", "country" => "US"
      )
    end

    it "uses the member's preferred name when the address has no contact name" do
      add_address

      expect(shipping_get(path)).to include("name" => "Ada Lovelace", "phone" => nil)
    end

    it "gives a null name when Weave has no name for the member" do
      member.update_columns(first_name: "", last_name: "") # rubocop:disable Rails/SkipsModelValidations
      add_address

      expect(shipping_get(path)).to include("name" => nil)
    end

    it "leaves out the coordinates, the delivery notes and the contact email" do
      add_address(contact_name: "Grace H.", contact_first_name: "Grace", contact_last_name: "Hopper",
                  contact_email: "grace@example.com")

      body = shipping_get(path)

      expect(body.keys).not_to include("latitude", "longitude", "shipping_notes", "contact_email", "address_type")
      expect(body.to_json).not_to include("42.34", "Leave at the door", "grace@example.com")
      expect(body["name"]).to eq("Grace Hopper")
    end

    it "tells caches not to keep the response" do
      add_address

      shipping_get(path)

      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    it "writes an audit row for each read" do
      add_address

      expect { 2.times { shipping_get(path) } }.to change(LockboxAudit.shipping_address_reads, :count).by(2)

      audit = LockboxAudit.shipping_address_reads.last
      expect(audit).to have_attributes(subject: member, viewer: application, ip: "127.0.0.1")
      expect(audit.data).to include("sub" => member.p_id)
      expect(audit.created_at).to be_within(1.minute).of(Time.current)
    end

    it "is not found for a user with no shipping address, and writes no audit row" do
      expect { shipping_get(path) }.not_to change(LockboxAudit, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "is not found for an address that can't go on a label" do
      add_address(line1: nil, postal_code: nil, allow_partial_address: true)

      shipping_get(path)

      expect(response).to have_http_status(:not_found)
    end

    it "is not found for an unknown sub" do
      shipping_get(api_v1_directory_user_shipping_address_path("PWL0000000000"))

      expect(response).to have_http_status(:not_found)
    end

    it "is not found for a user the app may not serve" do
      application.update!(access_policy: "restricted")
      add_address

      expect { shipping_get(path) }.not_to change(LockboxAudit, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "authentication" do
    before { add_address }

    it "refuses a request without a token" do
      get path

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a token without the fulfillment scope" do
      application.update!(scopes: "openid profile directory fulfillment")

      shipping_get(path, token: app_token(scopes: "directory"))

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a user's token, even with the fulfillment scope" do
      token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: member.id, scopes: "fulfillment")

      shipping_get(path, token: token.plaintext_token)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an app that is not allowed the fulfillment scope" do
      other = Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.com/cb", scopes: "openid directory")

      shipping_get(path, token: app_token(other))

      expect(response).to have_http_status(:forbidden)
    end

    it "does not let a fulfillment token call the rest of the directory" do
      shipping_get(api_v1_directory_user_path(member.p_id))

      expect(response).to have_http_status(:forbidden)
    end

    it "issues a fulfillment token through client_credentials" do
      post oauth_token_path, params: { grant_type: "client_credentials", scope: "fulfillment" },
                             headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(application.uid, application.plaintext_secret) }
      token = response.parsed_body.fetch("access_token")

      shipping_get(path, token: token)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "the admin user page" do
    it "lists the apps that read the address" do
      add_address
      shipping_get(path)
      sign_in_via_magic_link(create(:user, :admin, :verified))

      get admin_user_path(member)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Shipping address reads", "Hardware Patch")
    end
  end

  describe "rate limit" do
    it "throttles more than 30 reads a minute from one IP" do
      add_address
      token = app_token

      31.times { shipping_get(path, token: token) }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "counts the path with a trailing or doubled slash" do
      add_address
      token = app_token

      15.times { shipping_get("#{path}/", token: token) }
      15.times { shipping_get(path.sub("/shipping_address", "//shipping_address"), token: token) }
      expect(response).to have_http_status(:ok)

      shipping_get(path, token: token)

      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles one token used from many IPs" do
      add_address
      token = app_token

      30.times { |n| get path, headers: { "Authorization" => "Bearer #{token}", "REMOTE_ADDR" => "10.0.0.#{n + 1}" } }
      expect(response).to have_http_status(:ok)

      get path, headers: { "Authorization" => "Bearer #{token}", "REMOTE_ADDR" => "10.0.1.1" }

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
