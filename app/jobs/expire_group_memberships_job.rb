# frozen_string_literal: true

# Removes group memberships whose `expires_at` has passed.
#
# An expired membership already grants nothing, because every access check
# uses Group::Membership.active. This job removes the rows so member lists stay
# accurate, and so that each removal leaves a PaperTrail version that records
# who lost access and when. Running it twice removes nothing new.
class ExpireGroupMembershipsJob < ApplicationJob
  queue_as :default

  def perform
    PaperTrail.request(whodunnit: "ExpireGroupMembershipsJob") do
      Group::Membership.expired.includes(:group, :user).find_each do |membership|
        membership.destroy!
        Rails.logger.info(
          "Expired group membership: user=#{membership.user.p_id} group=#{membership.group&.slug}"
        )
      end
    end
  end

end
