# frozen_string_literal: true

# The receipt a service gets for a project event (see
# Api::V1::ProjectEventsController). It says only what was recorded. It never
# holds the member's score, a weight, or any other entry: Thread Count is
# internal (see ThreadCount).
class ThreadCountProjectEventSerializer
  def initialize(entry)
    @entry = entry
  end

  def as_json(*)
    {
      id: @entry.public_id,
      project_ref: @entry.project_ref,
      kind: @entry.kind,
      created_at: @entry.created_at
    }
  end

end
