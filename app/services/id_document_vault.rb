# frozen_string_literal: true

# The one interface to stored ID images (see KeyCustody and docs/KYC.md).
#
#   upload -> Lockbox copy (pre-review only) -> sealed copy -> purged
#
# - While an attempt waits for pre-review, the image is an Active Storage
#   attachment under Lockbox (the server key), so the pre-reviewer can see
#   it before any key holder is involved.
# - When pre-review ends ("Document OK", or the member must submit again),
#   seal! encrypts the image with a fresh data key, seals the data key to the
#   master public key, and destroys the Lockbox copy. After that only
#   break-glass opens it.
# - A break-glass approval with the second share opens the data key in
#   memory, and decrypt reads the image with it in that same request
#   (BreakGlass.approve). Nothing is kept after the request.
module IdDocumentVault
  Decrypted = Data.define(:data, :content_type, :filename)

  class << self
    def stored?(verification) = verification.document_stored?

    def sealed?(verification) = verification.document_sealed?

    # The Lockbox copy, for the pre-reviewer only (VerificationFlow checks
    # who). Nil after the image is sealed.
    def pre_review_read(verification)
      return nil unless verification.id_document.attached? && verification.document_purged_at.nil?

      verification.id_document.download
    end

    # Seals the image to the current key set and destroys the Lockbox copy.
    # Call it inside the transaction that ends pre-review. Raises
    # KeyCustody::NotSetUp when no key set is active. Does nothing for an
    # attempt with no image, or an image that is already sealed.
    def seal!(verification)
      return false unless verification.id_document.attached? && verification.document_purged_at.nil?
      return false if verification.sealed_document.present?

      key_set = lock_current_key_set!

      attachment = verification.id_document
      plaintext = attachment.download
      data_key = KeyCustody::Crypto.random_key
      sealed = verification.build_sealed_document(key_set:, content_type: attachment.content_type,
                                                  extension: File.extname(attachment.filename.to_s).presence,
                                                  sealed_at: Time.current)
      ciphertext = KeyCustody::Crypto.encrypt(plaintext, key: data_key, aad: sealed_aad(verification))
      sealed.sealed_data_key = Base64.strict_encode64(
        KeyCustody::Crypto.seal(data_key, public_key: key_set.public_key_bytes, aad: sealed_aad(verification))
      )
      sealed.ciphertext.attach(io: StringIO.new(ciphertext), filename: "sealed", content_type: "application/octet-stream",
                               identify: false)
      sealed.save!
      attachment.purge
      VerificationEvent.record!(verification, :document_sealed, key_set_id: key_set.public_id)
      true
    ensure
      KeyCustody::Crypto.wipe(plaintext, data_key)
    end

    # Opens the sealed data key with a rebuilt master private key. The
    # caller wipes the result.
    def open_data_key(verification, private_key)
      sealed = verification.sealed_document
      KeyCustody::Crypto.open_sealed(sealed.sealed_data_key_bytes, private_key:, aad: sealed_aad(verification))
    end

    # Decrypts the sealed image with its data key (opened by
    # open_data_key in BreakGlass.approve). The caller wipes the data key
    # and the result after use.
    def decrypt(verification, data_key)
      sealed = verification.sealed_document
      raise BreakGlass::NotPermitted, "There is no stored image to open" if sealed.nil? || verification.document_purged_at

      data = KeyCustody::Crypto.decrypt(sealed.ciphertext.download, key: data_key, aad: sealed_aad(verification))
      Decrypted.new(data:, content_type: sealed.content_type, filename: "id_document#{sealed.extension}")
    end

    # Re-wraps every image sealed to old_key_set: opens each data key with
    # the old master key and seals it to the new public key. A rotation
    # calls it with the old key rebuilt in memory. Returns the count.
    def rewrap_all!(old_key_set, old_private_key, new_key_set)
      count = 0
      old_key_set.sealed_documents.includes(:verification).find_each do |sealed|
        data_key = open_data_key(sealed.verification, old_private_key)
        sealed.update!(key_set: new_key_set, sealed_data_key: Base64.strict_encode64(
          KeyCustody::Crypto.seal(data_key, public_key: new_key_set.public_key_bytes, aad: sealed_aad(sealed.verification))
        ))
        count += 1
      ensure
        KeyCustody::Crypto.wipe(data_key)
      end
      count
    end

    # Destroys every stored copy: the Lockbox copy and the sealed copy. The
    # verification and its audit rows stay. later: true purges the files in
    # a job.
    def purge!(verification, later: false)
      purged = false
      if verification.id_document.attached?
        later ? verification.id_document.purge_later : verification.id_document.purge
        purged = true
      end
      if (sealed = verification.sealed_document)
        # Destroying the row purges the ciphertext in a job.
        sealed.ciphertext.purge unless later
        sealed.destroy!
        verification.association(:sealed_document).reset
        purged = true
      end
      purged
    end

    # The aad of an image's ciphertext and sealed data key. The requester's
    # browser needs it to decrypt the image (BreakGlass.open!).
    def aad_for(verification) = sealed_aad(verification)

    private

    # The current key set, with a shared row lock. A rotation takes an
    # exclusive lock on the old set while it re-wraps, so no image is sealed
    # to the old set after the re-wrap has read the list.
    def lock_current_key_set!
      2.times do
        key_set = KeyCustody.current_key_set
        raise KeyCustody::NotSetUp, "Key custody is not set up: run the key ceremony first." if key_set.nil?

        key_set = KeyCustodyKeySet.lock("FOR SHARE").find(key_set.id)
        return key_set if key_set.current?
      end
      raise KeyCustody::NotSetUp, "The key set changed during the seal. Try again."
    end

    def sealed_aad(verification) = "verification:#{verification.id}"

  end
end
