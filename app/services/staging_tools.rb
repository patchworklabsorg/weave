# frozen_string_literal: true

# Who can use the staging-only admin tools: the test states on the user page
# (StagingTestStates) and the mail allowlist page
# (StagingMailAllowlistEntry). An owner, and only on staging.
module StagingTools
  module_function

  def allowed?(actor) = Weave.staging? && actor.present? && actor.owner?
end
