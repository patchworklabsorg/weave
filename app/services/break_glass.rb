# frozen_string_literal: true

# Break-glass access to stored ID images (see BreakGlassRecord, issue #92).
#
# Normal operations never decrypt a stored image. Outside pre-review, the only
# way is:
#
# 1. An identity team member requests access with a written reason.
# 2. Two different key holders approve. Then only the requester can decrypt,
#    for a configured number of minutes.
# 3. Each decryption climbs the notice ladder (BreakGlassNotice): the other
#    key holder and the identity team lead at once, the member after a
#    configured window, and the board in its report. A fraud investigation
#    can hold back the member notice: one identity team member asks with a
#    reason, an owner or the identity team lead (never the requester) signs
#    it off, and the hold ends after at most max_fraud_delay_days.
#
# Quiet use is not possible: decrypt! writes the decryption and its notices in
# one transaction, and it decrypts only after that transaction commits.
# DeliverBreakGlassNoticesJob sends each notice that is due.
module BreakGlass
  Result = Data.define(:record, :errors) do
    def success? = errors.empty?
  end

  Decrypted = Data.define(:data, :content_type, :filename)

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

    def request(verification, by:, reason:)
      record = verification.break_glass_records.new(user_id: verification.user_id, requested_by: by, reason: reason.to_s.strip)
      unless by&.identity_team && by.id != verification.user_id
        return Result.new(record:, errors: { base: "Only an identity team member who is not the member can ask." })
      end
      if (blocker = request_blocker(verification))
        return Result.new(record:, errors: { base: blocker })
      end
      return Result.new(record:, errors: { base: "There is no stored image to open." }) unless verification.document_stored?

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

    # A key holder approves. The request is granted when enough different key
    # holders approve.
    def approve(record, by:)
      return false unless may_approve?(by, record)

      record.with_lock do
        return false unless record.pending?
        return false if record.approvals.exists?(approver_id: by.id)

        record.approvals.create!(approver: by)
        VerificationEvent.record!(record.verification, :break_glass_approved, actor: by, break_glass_record_id: record.id)
        if record.approvals.count >= VerificationSettings.break_glass_approvals_required
          record.update!(granted_at: Time.current, expires_at: VerificationSettings.break_glass_access.from_now)
          VerificationEvent.record!(record.verification, :break_glass_granted, break_glass_record_id: record.id,
                                                                               expires_at: record.expires_at.iso8601)
        end
      end
      true
    end

    def deny(record, by:, reason:)
      return false unless may_approve?(by, record) && reason.present?

      record.with_lock do
        return false unless record.pending?

        record.update!(denied_at: Time.current, denied_by: by, denial_reason: reason)
        VerificationEvent.record!(record.verification, :break_glass_denied, actor: by, break_glass_record_id: record.id,
                                                                            reason:)
      end
      true
    end

    # Decrypts the image for the requester of a granted record. Raises
    # NotPermitted otherwise. The decryption row and its notices commit
    # before the image is read.
    def decrypt!(record, viewer:, ip: nil, user_agent: nil)
      BreakGlassRecord.transaction do
        record.lock!
        unless record.usable_by?(viewer) && viewer.identity_team
          raise NotPermitted, "This break-glass access is not granted to you, or it has expired"
        end
        raise NotPermitted, "There is no stored image to open" unless record.verification.document_stored?

        decryption = record.decryptions.create!(viewer:, ip:, user_agent: user_agent.to_s.truncate(255))
        create_notices!(decryption, record, viewer)
        VerificationEvent.record!(record.verification, :document_decrypted, actor: viewer,
                                                                            break_glass_record_id: record.id,
                                                                            break_glass_decryption_id: decryption.id)
      end
      DeliverBreakGlassNoticesJob.perform_later

      document = record.verification.id_document
      Decrypted.new(data: document.download, content_type: document.content_type, filename: document.filename.to_s)
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
