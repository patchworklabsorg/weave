# frozen_string_literal: true

# Strict lookup for a public id taken from a URL or a form. It accepts the
# bare hashid (what `to_param` returns) or the prefixed public id. A numeric
# primary key never resolves. Use these instead of `find` in controllers:
# `find` falls back to the numeric id.
module PublicParamLookup
  extend ActiveSupport::Concern

  class_methods do
    def find_by_public_param(param)
      param = param.to_s
      if param.include?(EncodedIds.configuration.separator)
        find_by_public_id(param)
      else
        find_by_hashid(param)
      end
    end

    def find_by_public_param!(param)
      find_by_public_param(param) || raise(ActiveRecord::RecordNotFound.new("Couldn't find #{name}", name))
    end
  end
end
