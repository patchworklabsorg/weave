# frozen_string_literal: true

require "rails_helper"

# The key custody pages (/identity/key_custody): hardware keys, the
# ceremony, activation, recovery and the log. The browser parts are played
# with webauthn's fake client and a stubbed PRF (see KeyCustodyHelpers).
RSpec.describe "Key custody pages", type: :request do
  include ActiveJob::TestHelper

  describe "access" do
    it "turns away an admin who is not on the identity team or the board" do
      sign_in_via_magic_link(create(:user, :admin, :verified))

      get identity_key_custody_path

      expect(response).to redirect_to(root_path)
    end

    it "shows the page to a board member and the identity team, with the warning before the ceremony" do
      sign_in_via_magic_link(create(:user, :verified, is_board: true))

      get identity_key_custody_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Key custody is not set up", %(href="#{identity_key_custody_path}"))
    end

    it "refuses the JSON actions to a person outside the rules" do
      sign_in_via_magic_link(create(:user, :identity_team, :verified))

      post options_identity_hardware_keys_path, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("key holder")
    end
  end

  describe "who can do what" do
    let(:keys) { key_holders_with_keys }
    let(:pending) { run_ceremony(operator: keys.keys.first, keys:).key_set }

    it "turns a plain member away from every JSON action" do
      sign_in_via_magic_link(create(:user, :verified))

      post start_identity_key_ceremony_path, as: :json
      expect(response).to have_http_status(:forbidden)
      post activation_options_identity_key_set_path(pending), as: :json
      expect(response).to have_http_status(:forbidden)
      post options_identity_hardware_keys_path, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "turns an admin without the identity flags away from the key custody and break-glass actions" do
      sign_in_via_magic_link(create(:user, :admin, :verified))

      post start_identity_key_ceremony_path, as: :json
      expect(response).to have_http_status(:forbidden)
      post activate_identity_key_set_path(pending), as: :json
      expect(response).to have_http_status(:forbidden)
      get identity_break_glass_records_path
      expect(response).to redirect_to(root_path)
    end

    it "lets a board member look, but not run the ceremony, enroll or activate" do
      sign_in_via_magic_link(create(:user, :verified, is_board: true))

      post start_identity_key_ceremony_path, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("key holder with a hardware key")
      post options_identity_hardware_keys_path, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      post activation_options_identity_key_set_path(pending), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "does not let an owner who is not a key holder run the ceremony or give a share" do
      keys
      sign_in_via_magic_link(create(:user, :owner, :verified))

      post start_identity_key_ceremony_path, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      post activation_options_identity_key_set_path(pending), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      post activate_identity_key_set_path(pending), params: { new_share: b64url(SecureRandom.random_bytes(33)) }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(pending.reload).to be_pending
    end
  end

  describe "enrolling a hardware key" do
    let(:holder) { create(:user, :key_holder, :verified) }

    it "registers the key, then its seal public key, from the holder's own browser" do # rubocop:disable RSpec/ExampleLength
      sign_in_via_magic_link(holder)
      post options_identity_hardware_keys_path, as: :json
      fake = KeyCustodyHelpers::FakeKey.new
      credential = fake.client.create(challenge: response.parsed_body["challenge"], user_verified: true)
      credential["clientExtensionResults"] = { "prf" => { "enabled" => true } }

      post identity_hardware_keys_path, params: { credential:, role: "primary", nickname: "Blue" }, as: :json

      expect(response).to have_http_status(:ok)
      key = holder.identity_hardware_keys.sole
      expect(key).to have_attributes(role: "primary", nickname: "Blue", seal_public_key: nil)
      fake.record = key
      seal = response.parsed_body["seal"]
      expect(seal.dig("extensions", "prf", "evalByCredential", key.external_id, "first")).to eq(key.seal_salt)

      post response.parsed_body["seal_url"],
           params: { credential: fake.assert(seal["challenge"]), seal_public_key: Base64.strict_encode64(fake.seal_public_key) }, as: :json

      expect(response).to have_http_status(:ok)
      expect(key.reload.seal_public_key_bytes).to eq(fake.seal_public_key)
      expect(KeyCustodyEvent.where(kind: "seal_key_registered", subject: holder)).to exist
    end

    it "registers the key and its seal key in one request when the key gave PRF at creation" do
      sign_in_via_magic_link(holder)
      post options_identity_hardware_keys_path, as: :json
      options = response.parsed_body
      expect(options.dig("extensions", "prf", "eval", "first")).to eq(options["seal_salt"])
      fake = KeyCustodyHelpers::FakeKey.new
      credential = fake.client.create(challenge: options["challenge"], user_verified: true)
      credential["clientExtensionResults"] = { "prf" => { "enabled" => true } }
      seal_public_key = Base64.strict_encode64(fake.seal_public_key_for(options["seal_salt"]))

      post identity_hardware_keys_path, params: { credential:, role: "primary", seal_public_key: }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("one_touch" => true)
      expect(response.parsed_body).not_to have_key("seal")
      key = holder.identity_hardware_keys.sole
      expect(key).to have_attributes(seal_salt: options["seal_salt"], seal_public_key:)
      get identity_key_custody_path
      expect(response.body).not_to include("Set up the seal key")
    end

    it "falls back to a second touch when the key gave no PRF output, and shows the set-up button meanwhile" do
      sign_in_via_magic_link(holder)
      post options_identity_hardware_keys_path, as: :json
      fake = KeyCustodyHelpers::FakeKey.new
      credential = fake.client.create(challenge: response.parsed_body["challenge"], user_verified: true)
      credential["clientExtensionResults"] = { "prf" => { "enabled" => true } }

      post identity_hardware_keys_path, params: { credential:, role: "primary" }, as: :json

      expect(response.parsed_body).to include("one_touch" => false)
      expect(response.parsed_body["seal"]).to be_present
      get identity_key_custody_path
      expect(response.body).to include("Set up the seal key")
    end

    it "refuses a seal key without an assertion of that key" do
      sign_in_via_magic_link(holder)
      fake = enroll_fake_key(holder, role: "primary", seal: false)
      other = enroll_fake_key(holder, role: "backup")
      post seal_key_options_identity_hardware_key_path(fake.record), as: :json

      post seal_key_identity_hardware_key_path(fake.record),
           params: { credential: other.assert(response.parsed_body["challenge"]), seal_public_key: Base64.strict_encode64(fake.seal_public_key) }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(fake.record.reload.seal_public_key).to be_nil
    end

    it "shows the enroll form to a key holder" do
      sign_in_via_magic_link(holder)

      get identity_key_custody_path

      expect(response.body).to include("Enroll a hardware key", options_identity_hardware_keys_path)
    end
  end

  describe "the ceremony and activation" do
    let!(:keys) { key_holders_with_keys }
    let(:holders) { keys.keys }

    it "makes a pending key set from the browser's public key and sealed shares, with one touch of the operator's key" do # rubocop:disable RSpec/ExampleLength
      operator = holders.first
      operator.update!(email_confirmed_at: Time.current)
      sign_in_via_magic_link(operator)
      get new_identity_key_ceremony_path
      expect(response.body).to include("Start the ceremony", "Where the private key exists")

      post start_identity_key_ceremony_path, as: :json
      options = response.parsed_body
      private_key, public_key = KeyCustody::Crypto.generate_key_pair
      split = KeyCustody::Shamir.split(private_key, share_count: 3, threshold: 2)
      public_b64 = Base64.strict_encode64(public_key)
      shares = options["holders"].each_with_index.map do |holder_options, index|
        holder = holders.find { |candidate| candidate.public_id == holder_options["id"] }
        {
          holder_id: holder.public_id, x: split[index].getbyte(-1), digest: KeyCustody::Crypto.share_digest(split[index], public_key:),
          wrapped: keys[holder].map do |fake|
            seal_key = holder_options["keys"].find { |key| key["id"] == fake.external_id }["seal_public_key"]
            expect(Base64.strict_decode64(seal_key)).to eq(fake.seal_public_key)
            { credential_id: fake.external_id, sealed: seal_for(fake, split[index], key_set_public_key_b64: public_b64, holder:) }
          end
        }
      end

      signer = keys[operator].first
      expect(options.dig("request", "extensions", "prf", "evalByCredential", signer.external_id, "first")).to eq(signer.record.seal_salt)
      operator_share = open_own_sealed_share(signer, shares, operator, public_b64, split[options["holders"].index { |item| item["id"] == operator.public_id }])
      post identity_key_ceremony_path, params: { ceremony: options["ceremony"], public_key: public_b64, shares:,
                                                 credential: signer.assert(options.dig("request", "challenge")),
                                                 operator_share: b64url(operator_share) }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to include("Your share is given")
      key_set = KeyCustodyKeySet.sole
      expect(KeyCustody::Activation.waiting_holder_ids(key_set)).to eq([operator.id])
      expect(key_set).to be_pending
      expect(key_set.wrapped_shares.count).to eq(6)
      # The sealed share opens in the holder's "browser" with the same aad
      # that Weave sends back later.
      holder = holders.first
      expect(open_share(keys[holder].first, key_set)).to eq(split[options["holders"].index { |item| item["id"] == holder.public_id }])
    end

    it "activates a pending set through the JSON action" do
      key_set = run_ceremony(operator: holders.first, keys:).key_set
      submit_activation(holders.first, keys[holders.first].first, key_set)
      submit_activation(holders.third, keys[holders.third].first, key_set)
      holder = holders.second
      sign_in_via_magic_link(holder)

      post activation_options_identity_key_set_path(key_set), as: :json
      options = response.parsed_body
      fake = keys[holder].first
      expect(options.dig("request", "extensions", "prf", "evalByCredential", fake.external_id, "first")).to eq(fake.record.seal_salt)
      share = fake.open(options.dig("wrapped", fake.external_id, "new"))
      post activate_identity_key_set_path(key_set), params: { credential: fake.assert(options.dig("request", "challenge")),
                                                              new_share: b64url(share)
}, as: :json

      expect(response).to have_http_status(:ok)
      expect(key_set.reload).to be_active
    end

    it "shows each holder's activation status, and hides the activate button from a holder who gave their share" do
      key_set = run_ceremony(operator: holders.first, keys:).key_set
      submit_activation(holders.first, keys[holders.first].first, key_set)
      expect(KeyCustody::Activation.waiting_holder_ids(key_set)).to eq([holders.first.id])

      sign_in_via_magic_link(holders.first)
      get identity_key_custody_path
      expect(response.body).to match(/#{holders.first.full_name}:\s+share given/)
      expect(response.body).to match(/#{holders.second.full_name}:\s+not yet/)
      expect(response.body).to include("You gave your share. The key set goes live when every holder has given theirs.")
      expect(response.body).not_to include("key-custody#activate")

      sign_in_via_magic_link(holders.second)
      get identity_key_custody_path
      expect(response.body).to include("key-custody#activate")
      expect(response.body).not_to include("You gave your share")
    end

    it "hides the ceremony button and shows the blocker while a set waits for activation" do
      run_ceremony(operator: holders.first, keys:)
      sign_in_via_magic_link(holders.first)

      get identity_key_custody_path

      expect(response.body).to include("waits for activation. Activate it or discard it first.")
      expect(response.body).not_to include(new_identity_key_ceremony_path)
    end

    it "shows the ceremony button when nothing blocks it" do
      sign_in_via_magic_link(holders.first)

      get identity_key_custody_path

      expect(response.body).to include(new_identity_key_ceremony_path, "Run the key ceremony")
    end

    it "discards a pending set through the form, and the board is told" do
      board = create(:user, :verified, is_board: true)
      key_set = run_ceremony(operator: holders.first, keys:).key_set
      sign_in_via_magic_link(holders.first)
      expect { patch discard_identity_key_set_path(key_set), params: { reason: "Wrong holders in the room" } }
        .to have_enqueued_mail(KeyCustodyMailer, :event).with(anything, board)
      expect(KeyCustodyEvent.find_by!(kind: "key_set_discarded").data).to include("reason" => "Wrong holders in the room")
    end

    it "discards a pending set through the form" do
      key_set = run_ceremony(operator: holders.first, keys:).key_set
      sign_in_via_magic_link(holders.first)

      patch discard_identity_key_set_path(key_set), params: { reason: "Wrong holders in the room" }

      expect(key_set.reload).to be_retired
    end
  end

  describe "recovery" do
    let!(:custody) { setup_key_custody }
    let(:keys) { custody.last }
    let(:holder) { keys.keys.first }

    it "finds a hardware key by its public id and not by its database id" do
      key = keys[holder].first.record
      sign_in_via_magic_link(holder)

      expect(revoke_identity_hardware_key_path(key)).to eq("/identity/hardware_keys/#{key.hashid}/revoke")
      patch "/identity/hardware_keys/#{key.id}/revoke", params: { reason: "Lost on the train" }

      expect(response).to have_http_status(:not_found)
      expect(key.reload).to be_active
    end

    it "revokes a lost key and seals the share for a new key, with no touch of the new key" do # rubocop:disable RSpec/ExampleLength
      sign_in_via_magic_link(holder)
      patch revoke_identity_hardware_key_path(keys[holder].first.record), params: { reason: "Lost on the train" }
      expect(flash[:notice]).to include("board is told")

      new_fake = enroll_fake_key(holder, role: "primary")
      post rewrap_options_identity_hardware_key_path(new_fake.record), as: :json
      options = response.parsed_body
      remaining = keys[holder].last
      share = remaining.open(options.dig("old", "wrapped", remaining.external_id))
      sealed = b64url(KeyCustody::Crypto.seal_share(share, public_key: Base64.strict_decode64(options.dig("new", "seal_public_key")),
                                                           aad: options.dig("new", "aad")))
      post rewrap_identity_hardware_key_path(new_fake.record),
           params: { old_credential: remaining.assert(options.dig("old", "challenge")), sealed: }, as: :json

      expect(response).to have_http_status(:ok)
      expect(open_share(new_fake, custody.first.key_set)).to eq(custody.first.shares[holder])
    end
  end

  describe "pre-review before the ceremony" do
    it "tells the team that key custody is not set up" do
      verifier = create(:user, :identity_team, :verified)
      verification = create(:verification)
      VerificationFlow.start_pre_review(verification, by: verifier)
      sign_in_via_magic_link(verifier)

      patch approve_document_identity_verification_path(verification)

      expect(flash[:alert]).to include("Key custody is not set up")
      expect(verification.reload).to be_pre_review
    end
  end
end
