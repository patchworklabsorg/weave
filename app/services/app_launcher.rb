# frozen_string_literal: true

# The app launcher on the member dashboard (see OauthApplicationLauncher).
#
# - usable: launcher apps the member may use now (AppAccess).
# - requestable: launcher apps the member may ask for (AccessRequests).
# - pending: the member's open access requests, for any app they can't use yet.
module AppLauncher
  Launcher = Data.define(:usable, :requestable, :pending) do
    def empty? = usable.empty? && requestable.empty? && pending.empty?
  end

  def self.for(user)
    apps = Doorkeeper::Application.in_launcher.to_a
    usable, others = apps.partition { |application| AppAccess.permitted?(user, application) }

    # A request for an app the member can already use is moot: show the app.
    pending = user.access_requests.pending.where.not(application_id: usable.map(&:id))
                  .includes(:application).order(:created_at).to_a
    pending_ids = pending.map(&:application_id)

    requestable = others.reject { |application| pending_ids.include?(application.id) }
                        .select { |application| AccessRequests.requestable?(user, application) }

    Launcher.new(usable:, requestable:, pending:)
  end
end
