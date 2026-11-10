# frozen_string_literal: true

# Every job runs in UTC. ActiveJob saves Time.zone when a job is enqueued and
# runs the job in it, so without this a job would take the zone of the
# request that enqueued it. Mailers set the recipient's zone themselves
# (ApplicationMailer#mail); pages set the viewer's zone only while they
# render (ViewerTimeZone).
ActiveSupport.on_load(:active_job) do
  around_perform { |_job, block| Time.use_zone("UTC", &block) }
end
