# frozen_string_literal: true

# Rack::Attack's throttle counters live in a process-wide MemoryStore in test
# (see config/initializers/rack_attack.rb), so without this they accumulate
# across examples: a spec that legitimately makes a handful of requests each
# starts getting 429s partway through the file purely because of what earlier
# examples did. Reset between examples so each one starts from a clean quota.
#
# This does not disable throttling — a single example can still exhaust a limit
# and assert on the 429, which is what a spec covering rate limiting wants.
RSpec.configure do |config|
  config.before { Rack::Attack.reset! }
end
