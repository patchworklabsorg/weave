# frozen_string_literal: true

# Numbers entered without a country code (e.g. "(802) 555-0123") are parsed
# as US numbers; international numbers in +E.164 format still work as-is.
Phonelib.default_country = "US"
