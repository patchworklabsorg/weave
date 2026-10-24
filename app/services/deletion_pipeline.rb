# frozen_string_literal: true

# The deletion pipeline (proposal v0.8 section 06, "The deletion pipeline, in
# order"). Exactly four steps, in this order:
#
#   1. fold_aggregates    Fold the member's generalized bands into the
#                         delete-time aggregates, and park the demographics
#                         envelope for the next reporting run.
#   2. write_knot_record  Write the Knot's record (the blacklist flag and the
#                         program grants received) and detach the Knot.
#   3. sever_identity     Sever the identity and destroy the readable
#                         records. Keep the verification audit records and the
#                         financial records only under their named obligation.
#   4. send_receipt       Generate and send the deletion receipt.
#
# Every step depends on the identity still being intact, so severing it is
# the second-to-last thing that happens. Steps 1 to 3 run in one database
# transaction: a failure before step 3 finishes rolls everything back, and
# the identity stays intact. Step 4 runs after the commit. A retry after a
# failed step 4 only sends the receipt again.
#
# Every run is a DeletionRun row with each step and its result. What happens
# to each kind of data comes from DataCategories.
module DeletionPipeline
  STEPS = %w[fold_aggregates write_knot_record sever_identity send_receipt].freeze

  class NotRunnable < StandardError; end

  # Records of the member that were deleted before (an old email address,
  # a signed-out session, a revoked grant) are gone from the tables, but
  # their PaperTrail rows still hold the values and the account id. They
  # are found by the account id in the stored object, and every row of that
  # record goes (also the "create" row, which has no object).
  OWNED_VERSION_KEYS = {
    "EmailAddress"              => { "user_id" => :id },
    "Group::Membership"         => { "user_id" => :id },
    "User::Session"             => { "user_id" => :id },
    "User::Passkey"             => { "user_id" => :id },
    "GuardianConsent"           => { "user_id" => :id },
    "ApplicationAccessGrant"    => { "grantee_type" => "User", "grantee_id" => :id },
    "ApplicationRoleAssignment" => { "assignee_type" => "User", "assignee_id" => :id }
  }.freeze

  Result = Data.define(:run, :error) do
    def success? = error.nil?
  end

  class << self
    # Runs the pipeline for an approved (or failed) request. Returns a Result.
    def run!(request)
      request.with_lock do
        raise NotRunnable, "Deletion request #{request.public_id} is #{request.status}" unless request.approved? || request.failed?

        request.start_run!
      end
      run = request.runs.create!(started_at: Time.current)
      log = []

      begin
        if request.user
          ActiveRecord::Base.transaction do
            user = request.user
            knot_record = nil
            step(log, "fold_aggregates") { fold_aggregates!(user) }
            step(log, "write_knot_record") { knot_record = KnotLinker.write_record_and_detach!(user) }
            step(log, "sever_identity") { request.update!(receipt: sever_identity!(user, knot_record, request)) }
          end
        else
          # Steps 1 to 3 committed in an earlier run.
          STEPS.first(3).each { |name| log << { "step" => name, "status" => "done_earlier", "at" => Time.current.iso8601 } }
        end
        step(log, "send_receipt") { send_receipt!(request) }
      rescue => e
        finish_failed(request, run, log, e)
        return Result.new(run:, error: e)
      end

      run.update!(outcome: "completed", steps: log, finished_at: Time.current)
      request.update!(completed_at: Time.current)
      request.complete!
      Result.new(run:, error: nil)
    end

    private

    def step(log, name)
      entry = { "step" => name, "status" => "running", "at" => Time.current.iso8601 }
      log << entry
      yield
      entry["status"] = "done"
    rescue
      entry["status"] = "failed"
      raise
    end

    def finish_failed(request, run, log, error)
      # The transaction rolled back the steps before send_receipt.
      unless log.any? { |entry| entry["step"] == "send_receipt" }
        log.each { |entry| entry["status"] = "rolled_back" if entry["status"] == "done" }
      end
      run.update!(outcome: "failed", steps: log, finished_at: Time.current, error_class: error.class.name,
                  error_message: error_summary(error))
      request.reload.mark_failed!
      Rails.logger.error("[DeletionPipeline] Run #{run.id} for #{request.public_id} failed: #{error.class}")
    end

    # The run log stays after the account is gone, so it keeps only the
    # first line of the error. A database error puts the row values on the
    # next lines (for example "DETAIL: Key (email)=(...)").
    def error_summary(error) = error.message.to_s.lines.first.to_s.strip.truncate(500)

    # Step 1. Participation rows that a funder contract keeps are not folded
    # now: they fold when their window closes (DataRetention::Sweeps).
    def fold_aggregates!(user)
      participations = ProgramParticipation.where(user_id: user.id).to_a
      participations.each do |participation|
        next if participation.individual_record_window

        DeleteTimeAggregates.add!(DeleteTimeAggregates.bands_for(participation, user:))
      end
      cohorts = [Date.current.year.to_s] + participations.map { |participation| "#{participation.program}-#{participation.year}" }
      DemographicsVault.fold!(user, cohorts:)
    end

    # Step 3. Real deletion of the readable records: no soft delete. Returns
    # the receipt (categories only, no values).
    def sever_identity!(user, knot_record, request)
      now = Time.current
      versions = version_items(user)
      retained = []

      retained << "verification_audit" if keep_verification_audit!(user, now)
      GuardianConsent.where(user_id: user.id).delete_all
      retained << "funder_records" if detach_participations!(user, now)
      retained << "financial" if GrantDisbursement.where(user_id: user.id).update_all(user_id: nil, detached_at: now).positive? # rubocop:disable Rails/SkipsModelValidations
      retained << "knot" if knot_record

      TakeoutRequest.where(user_id: user.id).find_each(&:destroy!)
      # Earlier requests (rejected or cancelled) still hold the address.
      DeletionRequest.where(user_id: user.id).where.not(id: request.id).update_all(receipt_email_ciphertext: nil) # rubocop:disable Rails/SkipsModelValidations
      Ahoy::Message.where(user_type: "User", user_id: user.id).delete_all
      # Events can sit on a visit that started before the sign-in, so the
      # visits of the user do not hold all of them.
      Ahoy::Event.where(user_id: user.id).delete_all
      LockboxAudit.where(subject_type: "User", subject_id: user.id).delete_all
      # A session this member opened while impersonating someone points at
      # them without a delete rule.
      User::Session.where(impersonated_by_id: user.id).update_all(impersonated_by_id: nil) # rubocop:disable Rails/SkipsModelValidations
      # An identity team member leaves the team first: logged, the board is
      # told, and a key holder starts a key rotation.
      IdentityGovernance.account_deleted!(user)

      PaperTrail.request(enabled: false) { user.destroy! }
      scrub_versions!(versions, user.id)

      receipt(retained)
    end

    # The audit records stay under their obligation, already without a link
    # to the account (the foreign keys empty user_id). The window starts now.
    # A stored ID image goes at once.
    def keep_verification_audit!(user, now)
      verifications = Verification.where(user_id: user.id)
      verifications.where(document_purged_at: nil).find_each do |verification|
        next unless IdDocumentVault.purge!(verification, later: true)

        verification.update_columns(document_purged_at: now) # rubocop:disable Rails/SkipsModelValidations
        VerificationEvent.record!(verification, :document_purged, reason: "account_deleted")
      end
      verifications.update_all(account_deleted_at: now).positive? # rubocop:disable Rails/SkipsModelValidations
    end

    # Rows a funder contract keeps stay with their bands and no link. The
    # rest were folded in step 1 and go now.
    def detach_participations!(user, now)
      kept = false
      ProgramParticipation.where(user_id: user.id).find_each do |participation|
        retained_until = participation.individual_record_until(now)
        if retained_until.nil?
          participation.delete
          next
        end

        bands = DeleteTimeAggregates.bands_for(participation, user:)
        participation.update!(user: nil, detached_at: now, retained_until:, age_band: bands.age_band,
                              region: bands.region, amount_band: bands.amount_band, funder: participation.funder_key)
        kept = true
      end
      kept
    end

    # The PaperTrail rows of the user and of each record that belongs to
    # them. Read before the records go.
    def version_items(user)
      {
        "User"                      => [user.id],
        "EmailAddress"              => user.email_addresses.ids,
        "Group::Membership"         => user.group_memberships.ids,
        "User::Session"             => user.user_sessions.ids,
        "User::Passkey"             => user.passkeys.ids,
        "ApplicationAccessGrant"    => user.application_access_grants.ids,
        "ApplicationRoleAssignment" => user.application_role_assignments.ids,
        "GuardianConsent"           => GuardianConsent.where(user_id: user.id).ids
      }
    end

    def scrub_versions!(items, user_id)
      items.each do |item_type, ids|
        PaperTrail::Version.where(item_type:, item_id: ids).delete_all if ids.any?
      end
      OWNED_VERSION_KEYS.each do |item_type, keys|
        conditions = keys.transform_values { |value| value == :id ? user_id : value }
        versions = PaperTrail::Version.where(item_type:)
        ids = versions.where_object(**conditions.symbolize_keys).distinct.pluck(:item_id)
        versions.where(item_id: ids).delete_all if ids.any?
      end
      PaperTrail::Version.where(whodunnit: user_id.to_s).update_all(whodunnit: nil) # rubocop:disable Rails/SkipsModelValidations
    end

    def receipt(retained)
      {
        "generated_at" => Time.current.iso8601,
        "removed"      => DataCategories.all.reject(&:retained?).map(&:key),
        "retained"     => DataCategories.all.select { |category| category.retained? && retained.include?(category.key) }.map(&:key),
        "none_held"    => DataCategories.all.select { |category| category.retained? && retained.exclude?(category.key) }.map(&:key)
      }
    end

    # Step 4. The address is emptied once the receipt is sent.
    def send_receipt!(request)
      return if request.receipt_sent_at.present?

      DataHandlingMailer.deletion_receipt(request).deliver_now if request.receipt_email.present?
      request.update!(receipt_sent_at: Time.current, receipt_email: nil)
    end

  end
end
