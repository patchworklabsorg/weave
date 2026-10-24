# frozen_string_literal: true

# Checks the funder profiles in config/kyc/data_retention.yml at boot (see
# FunderProfiles). An unknown key or a bad value stops the app with a clear
# error, so a typo can't change a retention window or a funder report.
Rails.application.config.after_initialize do
  FunderProfiles.validate!
end
