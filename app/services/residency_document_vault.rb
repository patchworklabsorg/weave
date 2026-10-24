# frozen_string_literal: true

# Stored residency proof documents, with the same rules as ID images (see
# IdDocumentVault):
#
#   upload -> Lockbox copy (pre-review only) -> sealed copy -> purged
#
# seal! encrypts the document with a fresh data key, seals the data key to
# the master public key, and destroys the Lockbox copy. Break-glass does not
# open residency documents: after pre-review nobody can read them, and they
# are purged on the ID image schedule. A key rotation re-wraps them, so a
# later break-glass path stays possible.
module ResidencyDocumentVault
  class << self
    # The Lockbox copy, for the pre-reviewer only (ResidencyFlow checks who).
    def pre_review_read(check)
      return nil unless check.document.attached? && check.document_purged_at.nil?

      check.document.download
    end

    # Seals the document to the current key set and destroys the Lockbox
    # copy. Call it inside the transaction that ends pre-review. Raises
    # KeyCustody::NotSetUp when no key set is active.
    def seal!(check)
      return false unless check.document.attached? && check.document_purged_at.nil?
      return false if check.sealed_document.present?

      key_set = KeyCustody.current_key_set
      raise KeyCustody::NotSetUp, "Key custody is not set up: run the key ceremony first." if key_set.nil?

      key_set = KeyCustodyKeySet.lock("FOR SHARE").find(key_set.id)
      raise KeyCustody::NotSetUp, "The key set changed during the seal. Try again." unless key_set.current?

      attachment = check.document
      plaintext = attachment.download
      data_key = KeyCustody::Crypto.random_key
      sealed = check.build_sealed_document(key_set:, content_type: attachment.content_type,
                                           extension: File.extname(attachment.filename.to_s).presence,
                                           sealed_at: Time.current)
      ciphertext = KeyCustody::Crypto.encrypt(plaintext, key: data_key, aad: aad(check))
      sealed.sealed_data_key = Base64.strict_encode64(
        KeyCustody::Crypto.seal(data_key, public_key: key_set.public_key_bytes, aad: aad(check))
      )
      sealed.ciphertext.attach(io: StringIO.new(ciphertext), filename: "sealed", content_type: "application/octet-stream",
                               identify: false)
      sealed.save!
      attachment.purge
      true
    ensure
      KeyCustody::Crypto.wipe(plaintext, data_key)
    end

    # Re-wraps every document sealed to old_key_set (see
    # IdDocumentVault.rewrap_all!). Returns the count.
    def rewrap_all!(old_key_set, old_private_key, new_key_set)
      count = 0
      old_key_set.sealed_residency_documents.includes(:residency_check).find_each do |sealed|
        check = sealed.residency_check
        data_key = KeyCustody::Crypto.open_sealed(sealed.sealed_data_key_bytes, private_key: old_private_key, aad: aad(check))
        sealed.update!(key_set: new_key_set, sealed_data_key: Base64.strict_encode64(
          KeyCustody::Crypto.seal(data_key, public_key: new_key_set.public_key_bytes, aad: aad(check))
        ))
        count += 1
      ensure
        KeyCustody::Crypto.wipe(data_key)
      end
      count
    end

    # Destroys every stored copy. The check stays. later: true purges the
    # files in a job.
    def purge!(check, later: false)
      purged = false
      if check.document.attached?
        later ? check.document.purge_later : check.document.purge
        purged = true
      end
      if (sealed = check.sealed_document)
        sealed.ciphertext.purge unless later
        sealed.destroy!
        check.association(:sealed_document).reset
        purged = true
      end
      purged
    end

    private

    def aad(check) = "residency_check:#{check.id}"

  end
end
