# frozen_string_literal: true

require "openssl"

# Turns the identifiers on an ID (VerificationIdentifiers) into the one-way
# hashes of the Knot (see Knot and docs/KYC.md). The plain values are never
# stored. Only the digests leave this module.
#
# Each digest is a keyed HMAC-SHA256 with a secret pepper, never a plain hash.
# A plain hash of a passport number can be reversed by trying every number.
# Without the pepper, a copy of the database can't be reversed.
#
# Kinds:
# - "document" (strong): document type + issuing country + document number.
# - "national_id" (strong): issuing country + national identity number, where
#   the country issues one for life.
# - "soft": normalized legal name + date of birth. It collides, so it can only
#   route a pass to manual review. It can never deny anyone. A pass stores one
#   soft digest for the full name and one for each pair of its words, so a
#   middle name on one ID and not on another still gives a soft match.
#
# Normalization (tested in spec/services/knot_hasher_spec.rb):
# - Document and national ID numbers: Unicode NFKC (full-width digits become
#   ASCII), upper case, and every character that is not a letter or a digit
#   removed ("c01 x00-t47" = "C01X00T47").
# - Legal name: Unicode NFKD, combining marks (diacritics) removed, the
#   letters that NFKD does not split mapped by FOLD (for example "ø" -> "o",
#   "æ" -> "ae"), Unicode case folding ("ß" -> "ss"), each run of characters
#   that are not letters or digits made one space (hyphens, apostrophes,
#   dots, commas), then the words sorted, so the order of given name and
#   family name does not matter. "ü" becomes "u", not "ue". Other scripts
#   (Cyrillic, Arabic, CJK) stay in their own script: there is no
#   transliteration.
# - Date of birth: ISO 8601 (YYYY-MM-DD).
module KnotHasher
  STRONG_KINDS = %w[document national_id].freeze
  KINDS = (STRONG_KINDS + %w[soft]).freeze
  SEPARATOR = "\u001F" # The ASCII unit separator. No field contains it.
  PEPPER_SALT = "weave/knot pepper v1"
  # The soft pairs come from the first words of the normalized name only, so
  # a long name gives at most 28 pairs.
  MAX_SOFT_NAME_WORDS = 8

  # Letters that Unicode NFKD does not split into a base letter and a mark.
  FOLD = {
    "ø" => "o", "Ø" => "o", "ł" => "l", "Ł" => "l", "đ" => "d", "Đ" => "d", "ð" => "d", "Ð" => "d",
    "æ" => "ae", "Æ" => "ae", "œ" => "oe", "Œ" => "oe", "þ" => "th", "Þ" => "th", "ı" => "i",
    "ħ" => "h", "Ħ" => "h"
  }.freeze

  # One hash of a Knot. digest is the hex HMAC.
  Digest = Data.define(:kind, :digest) do
    def strong? = KnotHasher::STRONG_KINDS.include?(kind)

    def to_h = { "kind" => kind, "digest" => digest }
  end

  class MissingPepper < StandardError; end

  class << self
    # The digests for the identifiers: a document digest, a national ID
    # digest when there is a national ID, and a soft digest.
    def digests(identifiers)
      found = []
      if identifiers.document_type.present? && identifiers.document_number.present?
        found << digest("document", identifiers.document_type, country(identifiers.issuing_country),
                        normalize_number(identifiers.document_number))
      end
      if identifiers.national_id.present?
        found << digest("national_id", country(identifiers.issuing_country), normalize_number(identifiers.national_id))
      end
      found.concat(soft_digests(identifiers.legal_name, identifiers.date_of_birth))
      found.compact.uniq
    end

    # The soft digests: the full name, then each pair of its words (at most
    # MAX_SOFT_NAME_WORDS words). The pair of a two-word name is the full
    # name, so a pair digest also matches the soft digest of an older Knot.
    def soft_digests(legal_name, date_of_birth)
      full = soft_digest(legal_name, date_of_birth)
      return [] if full.nil?

      words = normalize_name(legal_name).split.uniq.first(MAX_SOFT_NAME_WORDS)
      pairs = words.combination(2).map { |pair| digest("soft", pair.sort.join(" "), date_of_birth.iso8601) }
      [full, *pairs].uniq
    end

    def soft_digest(legal_name, date_of_birth)
      return nil unless date_of_birth.is_a?(Date)

      digest("soft", normalize_name(legal_name), date_of_birth.iso8601)
    end

    def normalize_number(value)
      value.to_s.unicode_normalize(:nfkc).upcase.gsub(/[^\p{L}\p{N}]/, "")
    end

    def normalize_name(value)
      name = value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "")
      name = name.gsub(Regexp.union(FOLD.keys), FOLD)
      name.downcase(:fold).gsub(/[^\p{L}\p{N}]+/, " ").split.sort.join(" ")
    end

    # The secret key of every digest. Production must set knot.pepper in the
    # credentials. A new pepper orphans every stored digest, so set it once
    # and never rotate it.
    def pepper
      configured = Rails.application.credentials.dig(:knot, :pepper)
      return configured if configured.present?
      raise MissingPepper, "Set knot.pepper in the credentials before a verification can pass" if Rails.env.production?

      Rails.application.key_generator.generate_key(PEPPER_SALT, 32)
    end

    private

    def country(value) = value.to_s.strip.upcase

    def digest(kind, *parts)
      raise ArgumentError, "unknown kind #{kind}" unless KINDS.include?(kind)
      return nil if parts.any?(&:blank?)

      Digest.new(kind:, digest: OpenSSL::HMAC.hexdigest("SHA256", pepper, [kind, *parts].join(SEPARATOR)))
    end

  end
end
