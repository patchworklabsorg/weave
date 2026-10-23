# frozen_string_literal: true

# Break-glass access to stored ID images (see BreakGlassRecord, issue #92).
#
# Normal operations never decrypt a stored image. Outside pre-review, the only
# way is:
#
# 1. An identity team member requests access with a written reason. Their
#    browser makes a one-time X25519 key pair (WebCrypto). The private key
#    stays in the browser as a non-extractable CryptoKey (IndexedDB). Only
#    the public key comes with the request (requester_public_key).
# 2. Two different key holders approve. An approval is the submission of the
#    holder's share of the master key, unwrapped in their browser by their
#    hardware key, with a WebAuthn assertion for this one request (see
#    KeyCustody). The requester may approve their own request when they are
#    a key holder. The second share rebuilds the master key in memory,
#    which opens the data key of this one image. Weave seals that data key
#    to the requester's public key (the sealed handoff) and stores only the
#    sealed blob. Then the shares, the master key and the data key are
#    wiped. The second approver does not see the image.
# 3. The requester opens it (open!), once, within handoff_minutes (30).
#    Their browser gets the sealed data key and the encrypted image, opens
#    the data key with its private key and decrypts the image. Weave deletes
#    the sealed blob at the open, and the sweeper deletes an expired one.
#    A database and Lockbox leak can't open the image: only the requester's
#    browser holds the key. To see the image again, ask again.
# 4. Each decryption climbs the notice ladder (BreakGlassNotice): the other
#    key holder and the identity team lead at once, the member after a
#    configured window, and the board in its report. A fraud investigation
#    can hold back the member notice: one identity team member asks with a
#    reason, an owner or the identity team lead (never the requester) signs
#    it off, and the hold ends after at most max_fraud_delay_days.
#
# Quiet use is not possible: open! writes the decryption and its notices in
# one transaction, and it returns the sealed key and the image only after
# that transaction commits.
# DeliverBreakGlassNoticesJob sends each notice that is due.
module BreakGlass
  Result = Data.define(:record, :errors) do
    def success? = errors.empty?
  end

  # What the requester's browser needs to open the image (see open!): the
  # data key sealed to its one-time key, the encrypted image, and the aad of
  # each.
  Handoff = Data.define(:sealed_key, :ciphertext, :content_type, :image_aad, :handoff_aad)

  # The outcome of an approval. granted is true when this share was the one
  # that unlocked the request and sealed the data key to the requester.
  Approval = Data.define(:error, :granted) do
    def success? = error.nil?
  end

  class NotPermitted < StandardError; end

  class << self
    # Why the attempt is not open to break-glass now, or nil when it is.
    # Break-glass is only for after a decision (a pass, a fail or an
    # escalation): a fraud review, an appeal or a blacklist check. Before the
    # decision, the pre-reviewer and the call do the checks.
    def request_blocker(verification)
      return nil if verification.decided?

      "Break-glass is only for an attempt that passed, failed or was escalated (a fraud review, an appeal or a " \
        "blacklist check). This attempt is #{verification.status.humanize.downcase}."
    end

    # requester_public_key: the X25519 public key (Base64, 32 bytes) of the
    # one-time key pair that the requester's browser made for this request.
    def request(verification, by:, reason:, requester_public_key: nil)
      record = verification.break_glass_records.new(user_id: verification.user_id, requested_by: by, reason: reason.to_s.strip,
                                                    requester_public_key: requester_public_key.to_s.strip.presence)
      unless by&.identity_team && by.id != verification.user_id
        return Result.new(record:, errors: { base: "Only an identity team member who is not the member can ask." })
      end
      if (blocker = request_blocker(verification))
        return Result.new(record:, errors: { base: blocker })
      end
      unless verification.document_sealed?
        return Result.new(record:, errors: { base: "There is no sealed image to open. An image waiting for pre-review is opened by its pre-reviewer." })
      end

      BreakGlassRecord.transaction do
        record.save || raise(ActiveRecord::Rollback)
        VerificationEvent.record!(verification, :break_glass_requested, actor: by, break_glass_record_id: record.id,
                                                                        reason: record.reason)
      end
      return Result.new(record:, errors: record.errors.to_hash.transform_values(&:first)) unless record.persisted?

      User.identity_key_holders.where.not(id: [by.id, verification.user_id]).find_each do |holder|
        next if lead_verifier_for_member?(holder, record)

        BreakGlassMailer.approval_needed(record, holder).deliver_later
      end
      Result.new(record:, errors: {})
    end

    # A key holder approves by submitting their share with a hardware key.
    #
    # - credential: the WebAuthn assertion (JSON) for the challenge of this
    #   request (KeyCustody::Assertions, purpose "break_glass").
    # - share: the holder's share, Base64url, unwrapped in their browser.
    #
    # The share must match the digest on record. It then waits, encrypted,
    # in KeyCustody::PendingShares. When a threshold of holders have a share
    # waiting, Weave rebuilds the master key, checks it against the public
    # key, opens the data key of this image and seals it to the requester's
    # one-time public key (the sealed handoff). Then the shares, the master
    # key and the data key are wiped. by does not see the image: the
    # requester gets an email and opens it (open!).
    def approve(record, by:, credential:, share:)
      share_bytes = KeyCustody.decode_share(share)
      return refused("Only a key holder who may approve this request can approve it.") unless may_approve?(by, record)

      verification = record.verification
      return refused("There is no sealed image to open.") unless verification.document_sealed?
      return refused("The account of the person who asked no longer exists.") if record.requested_by.nil?
      return refused("The request has no browser key of the person who asked. They must ask again.") if record.requester_public_key_bytes.nil?

      key_set = verification.sealed_document.key_set
      holder_share = key_set.share_for(by)
      return refused("You hold no share of the key set #{key_set.public_id}.") if holder_share.nil?

      hardware_key, = KeyCustody::Assertions.verify!(credential, user: by, purpose: "break_glass", subject: record.public_id,
                                                                 keys: KeyCustody::Recovery.keys_for(holder_share))
      return refused("This is not your share of the key set #{key_set.public_id}.") unless holder_share.matches?(share_bytes)

      granted = false
      record.with_lock do
        return refused("This request is not pending.") unless record.pending?

        memory_key = pending_key(record, key_set)
        lapse_missing_shares!(record, memory_key)
        lapse_ineligible_approvals!(record, memory_key)
        return refused("You already approved this request.") if record.live_approvals.exists?(approver_id: by.id)

        record.approvals.create!(approver: by, hardware_key:)
        VerificationEvent.record!(verification, :break_glass_approved, actor: by, break_glass_record_id: record.id,
                                                                       hardware_key_id: hardware_key.public_id)
        KeyCustody::PendingShares.put(memory_key, by.id, share_bytes)
        granted = seal_handoff_if_unlocked!(record, key_set, memory_key)
      end
      BreakGlassMailer.handoff_ready(record).deliver_later if granted && record.requested_by
      Approval.new(error: nil, granted:)
    rescue KeyCustody::UnlockFailed => e
      # The transaction rolled back the approval. The failure is logged
      # after it, and the board is told.
      KeyCustody.notify_board(KeyCustodyEvent.record!(:unlock_failed, actor: by, key_set: e.key_set, reason: e.message,
                                                                      break_glass_record_id: record.public_id))
      Approval.new(error: e.message, granted: false)
    rescue KeyCustody::Refused => e
      Approval.new(error: e.message, granted: false)
    ensure
      KeyCustody::Crypto.wipe(share_bytes)
    end

    # The options for an approval: a challenge for this one request, the
    # holder's hardware keys that open their share of the image's key set,
    # with each key's seal salt (PRF) and the sealed copies. Nil when the user may not
    # approve.
    def approval_options(record, by:)
      return nil unless record.pending? && may_approve?(by, record) && record.verification.document_sealed?

      key_set = record.verification.sealed_document.key_set
      share = key_set.share_for(by)
      keys = KeyCustody::Recovery.keys_for(share)
      return nil if keys.empty?

      challenge = KeyCustody::Assertions.issue!(user: by, purpose: "break_glass", subject: record.public_id)
      wrapped = share.wrapped_shares.includes(:hardware_key).index_by { |item| item.hardware_key.external_id }
      {
        key_set_id: key_set.public_id,
        public_key: key_set.public_key,
        digest: share.digest,
        request: KeyCustody::Assertions.request_options(challenge, keys:, prf: keys.to_h { |key| [key.external_id, { first: key.seal_salt }] }),
        wrapped: keys.to_h { |key| [key.external_id, wrapped[key.external_id].blob] }
      }
    end

    # The requester opens a granted image, once, within handoff_minutes.
    # Returns a Handoff: the data key sealed to the requester's one-time key
    # and the encrypted image. Only the requester's browser can open them.
    # The decryption row (viewer: the requester), its notices and the audit
    # row commit first, and the sealed key is deleted in the same
    # transaction. Raises NotPermitted when the open is not allowed.
    def open!(record, by:, ip: nil, user_agent: nil)
      handoff = nil
      record.with_lock do
        raise NotPermitted, "Only the person who asked can open this image." unless by&.identity_team && record.requested_by_id == by.id
        raise NotPermitted, "This request is not granted." unless record.granted?
        raise NotPermitted, "The image was already opened. To see it again, ask again." if record.opened_at
        unless record.handoff_open?
          raise NotPermitted, "The #{VerificationSettings.break_glass_handoff_ttl.inspect} to open the image passed. Ask again."
        end

        verification = record.verification
        raise NotPermitted, "There is no stored image to open." unless verification.document_sealed?

        handoff = Handoff.new(sealed_key: record.handoff_sealed_key, ciphertext: verification.sealed_document.ciphertext.download,
                              content_type: verification.sealed_document.content_type,
                              image_aad: IdDocumentVault.aad_for(verification), handoff_aad: handoff_aad(record))
        decryption = record.decryptions.create!(viewer: by, ip:, user_agent: user_agent.to_s.truncate(255))
        create_notices!(decryption, record, by)
        VerificationEvent.record!(verification, :document_decrypted, actor: by, break_glass_record_id: record.id,
                                                                     break_glass_decryption_id: decryption.id)
        record.update!(opened_at: Time.current, handoff_sealed_key: nil)
      end
      DeliverBreakGlassNoticesJob.perform_later
      handoff
    end

    # Deletes each sealed handoff that the requester did not open in time.
    # Returns the count.
    def sweep_expired_handoffs!
      count = 0
      BreakGlassRecord.where.not(handoff_sealed_key: nil).where(handoff_expires_at: ..Time.current).find_each do |record|
        record.with_lock do
          next if record.handoff_sealed_key.nil? || record.handoff_open?

          record.update!(handoff_sealed_key: nil)
          VerificationEvent.record!(record.verification, :break_glass_handoff_expired, break_glass_record_id: record.id)
          count += 1
        end
      end
      count
    end

    # Binds a sealed handoff to its request and its requester, so a blob
    # moved to another request or person does not open.
    def handoff_aad(record) = "break_glass_handoff|#{record.public_id}|#{record.requested_by&.p_id}"

    def deny(record, by:, reason:)
      return false unless may_approve?(by, record) && reason.present?

      record.with_lock do
        return false unless record.pending?

        record.update!(denied_at: Time.current, denied_by: by, denial_reason: reason)
        KeyCustody::PendingShares.discard_prefix(pending_key(record))
        VerificationEvent.record!(record.verification, :break_glass_denied, actor: by, break_glass_record_id: record.id,
                                                                            reason:)
      end
      true
    end

    # The holders whose share for this request waits now.
    def pending_share_holder_ids(record)
      key_set = record.verification.sealed_document&.key_set
      key_set ? KeyCustody::PendingShares.holder_ids(pending_key(record, key_set)) : []
    end

    # An active fraud investigation asks to hold back the member's notice. The
    # reason is required, the lead hears about it, and the board report lists
    # it. The delay holds the notice only after an owner or the identity team
    # lead signs it off (see .sign_off_delay), and for at most max_fraud_delay_days
    # after the notice was first due.
    def delay_member_notice(notice, by:, reason:)
      record = notice.break_glass_record
      return false unless by&.identity_team && by.id != record.user_id && reason.present?

      notice.with_lock do
        return false unless notice.member? && !notice.sent? && !notice.delayed?

        notice.update!(delayed_at: Time.current, delayed_by: by, delay_reason: reason, delay_lifted_at: nil,
                       delay_lifted_by: nil, delay_signed_off_at: nil, delay_signed_off_by: nil)
        VerificationEvent.record!(record.verification, :member_notice_delayed, actor: by, break_glass_notice_id: notice.id,
                                                                               reason:)
      end
      User.identity_leads.where.not(id: [by.id, record.user_id]).find_each do |lead|
        BreakGlassMailer.notice_delayed(notice, lead).deliver_later
      end
      true
    end

    # An owner or an identity team lead signs off the delay (see
    # .may_sign_off_delay?). Until then the delay holds nothing: the notice
    # goes out when it is due.
    def sign_off_delay(notice, by:)
      record = notice.break_glass_record
      return false unless may_sign_off_delay?(by, notice)

      notice.with_lock do
        return false unless notice.delayed? && !notice.delay_signed_off? && !notice.sent?

        notice.update!(delay_signed_off_at: Time.current, delay_signed_off_by: by)
        VerificationEvent.record!(record.verification, :member_notice_delay_signed_off,
                                  actor: by, break_glass_notice_id: notice.id, ends_at: notice.delay_ends_at.iso8601)
      end
      true
    end

    # The investigation no longer needs the delay: the notice goes out now,
    # or when it was first due if that is later.
    def lift_delay(notice, by:)
      record = notice.break_glass_record
      return false unless by&.identity_team && by.id != record.user_id

      notice.with_lock do
        return false unless notice.delayed?

        notice.update!(delay_lifted_at: Time.current, delay_lifted_by: by)
        VerificationEvent.record!(record.verification, :member_notice_delay_lifted, actor: by,
                                                                                    break_glass_notice_id: notice.id)
      end
      DeliverBreakGlassNoticesJob.perform_later
      true
    end

    # Only an owner or an identity team lead may sign off a fraud delay of the
    # member notice. Never the person who asked for the delay, never the
    # person who asked for the break-glass access, and never the member.
    def may_sign_off_delay?(by, notice)
      record = notice.break_glass_record
      return false if by.nil? || [notice.delayed_by_id, record.requested_by_id, record.user_id].include?(by.id)

      by.owner? || (by.identity_team && by.identity_lead)
    end

    # A key holder may approve or deny a request, unless the request is for
    # their own account, or they were the lead verifier (the one who recorded
    # the decision) on one of that member's calls.
    def may_approve?(by, record)
      key_holder?(by, record) && !lead_verifier_for_member?(by, record)
    end

    def lead_verifier_for_member?(by, record)
      return false if record.user_id.nil?

      Verification.where(user_id: record.user_id, verifier_id: by.id).exists?
    end

    private

    def refused(message) = Approval.new(error: message, granted: false)

    # The memory key holds the key set, so a share of an old set can't mix
    # with a share of the set that a rotation made.
    def pending_key(record, key_set = nil) = "break_glass:#{record.id}:#{key_set&.id}"

    # An approval whose share no longer waits (it expired) lapses. The holder
    # submits again.
    def lapse_missing_shares!(record, memory_key)
      in_memory = KeyCustody::PendingShares.holder_ids(memory_key)
      missing = record.live_approvals.where.not(approver_id: in_memory).to_a
      return if missing.empty?

      BreakGlassApproval.lapse!(missing.map(&:id))
      missing.each do |approval|
        VerificationEvent.record!(record.verification, :break_glass_approval_lapsed, actor: approval.approver,
                                                                                     break_glass_record_id: record.id)
      end
    end

    # An approver who may no longer approve (removed from the key holders,
    # or now the lead verifier on the member's calls) loses their approval,
    # and their share leaves memory. So a grant counts only the shares of
    # holders who may approve at the moment of the grant.
    def lapse_ineligible_approvals!(record, memory_key)
      ineligible = record.live_approvals.includes(:approver).reject do |approval|
        approval.approver && may_approve?(approval.approver, record)
      end
      return if ineligible.empty?

      BreakGlassApproval.lapse!(ineligible.map(&:id))
      ineligible.each do |approval|
        KeyCustody::PendingShares.remove(memory_key, approval.approver_id)
        VerificationEvent.record!(record.verification, :break_glass_approval_lapsed, actor: approval.approver,
                                                                                     break_glass_record_id: record.id,
                                                                                     reason: "no_longer_eligible")
      end
    end

    # Combines only the shares of holders with a live approval. Any other
    # waiting share for this request is deleted. When the shares unlock the
    # key, it opens the data key of this one image and seals it to the
    # requester's one-time public key (the sealed handoff), and writes the
    # grant. Nobody sees the image here: the requester opens it (open!).
    # Returns true when it granted, false while shares are missing.
    def seal_handoff_if_unlocked!(record, key_set, memory_key)
      eligible = record.live_approvals.pluck(:approver_id) & KeyCustody::PendingShares.holder_ids(memory_key)
      return false if eligible.size < key_set.threshold

      taken = KeyCustody::PendingShares.take(memory_key)
      KeyCustody::Crypto.wipe(*taken.except(*eligible).values)
      shares = taken.slice(*eligible).values
      return false if shares.size < key_set.threshold

      sealed = nil
      KeyCustody::Unlock.with_master_key(key_set, shares) do |private_key|
        data_key = IdDocumentVault.open_data_key(record.verification, private_key)
        sealed = KeyCustody::Crypto.seal(data_key, public_key: record.requester_public_key_bytes, aad: handoff_aad(record),
                                                   info: KeyCustody::Crypto::HANDOFF_SEAL_INFO)
      ensure
        KeyCustody::Crypto.wipe(data_key)
      end
      now = Time.current
      ends_at = now + VerificationSettings.break_glass_handoff_ttl
      record.update!(granted_at: now, expires_at: ends_at, handoff_expires_at: ends_at, key_set:,
                     handoff_sealed_key: Base64.strict_encode64(sealed))
      VerificationEvent.record!(record.verification, :break_glass_granted, break_glass_record_id: record.id,
                                                                           handoff_expires_at: ends_at.iso8601)
      true
    rescue KeyCustody::Refused, KeyCustody::Crypto::Error => e
      raise KeyCustody::UnlockFailed.new("The shares did not unlock the image: #{e.message}", key_set:)
    end

    def key_holder?(by, record) = by&.identity_team && by.identity_key_holder && by.id != record.user_id

    def create_notices!(decryption, record, viewer)
      now = Time.current
      staff = {}
      record.approvers.where.not(id: viewer.id).find_each { |holder| staff[holder.id] ||= [holder, "key_holder"] }
      User.identity_leads.where.not(id: [viewer.id, record.user_id].compact).find_each { |lead| staff[lead.id] ||= [lead, "lead"] }

      staff.each_value do |recipient, kind|
        decryption.notices.create!(recipient:, recipient_kind: kind, due_at: now)
      end
      return if record.user.nil?

      decryption.notices.create!(recipient: record.user, recipient_kind: "member",
                                 due_at: now + VerificationSettings.member_notice_delay)
    end

  end
end
