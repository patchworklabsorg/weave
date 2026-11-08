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
#   A US driving licence adds the state ("US-CA"), because each state numbers
#   its own licences.
# - "national_id" (strong): issuing country + national identity number, where
#   the country issues one for life.
# - "soft": normalized legal name + date of birth. It collides, so it can only
#   route a pass to manual review. It can never deny anyone. A pass stores one
#   soft digest for the full name and one for each pair of its words, so a
#   middle name on one ID and not on another still gives a soft match.
# - "birth" (medium): the full name, and the full name with one word left
#   out, each with the birth date and the country of birth. Not every pair:
#   two people can share two names, but rarely all but one. These together
#   almost never belong to two people, so a birth match counts as the same
#   person unless the verifiers record that it is not (see KnotLinker). Many
#   Knots can share one.
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
  KINDS = (STRONG_KINDS + %w[birth soft]).freeze
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
    # digest when there is a national ID, the birth digests when there is a
    # country of birth, and the soft digests.
    def digests(identifiers)
      found = []
      if identifiers.document_type.present? && identifiers.document_number.present?
        found << digest("document", identifiers.document_type, document_country(identifiers),
                        normalize_number(identifiers.document_number))
      end
      if identifiers.national_id.present?
        found << digest("national_id", country(identifiers.issuing_country), normalize_number(identifiers.national_id))
      end
      found.concat(birth_digests(identifiers.legal_name, identifiers.date_of_birth, identifiers.country_of_birth))
      found.concat(soft_digests(identifiers.legal_name, identifiers.date_of_birth))
      found.compact.uniq
    end

    # Digests that Weave only looks up and never stores. Before 2026-11-08 a
    # US driving licence was hashed without its state. Two states can give
    # the same number, so a match to that older digest only counts as soft
    # (see KnotLinker.match).
    def legacy_digests(identifiers)
      return [] unless identifiers.us_driving_licence? && identifiers.document_number.present?

      [digest("document", identifiers.document_type, "US", normalize_number(identifiers.document_number))].compact
    end

    # The birth digests: the full name, and each form with one word left out
    # (only when at least two words stay), with the birth date and the
    # country of birth. "Adam Józef Sidwa" gives "adam jozef sidwa", "adam
    # sidwa", "jozef sidwa" and "adam jozef", so a passport without the
    # middle name still matches.
    def birth_digests(legal_name, date_of_birth, country_of_birth)
      return [] if country_of_birth.blank? || !date_of_birth.is_a?(Date)

      birth_name_forms(legal_name).map { |name| digest("birth", name, date_of_birth.iso8601, country(country_of_birth)) }.compact.uniq
    end

    def birth_name_forms(legal_name)
      full = normalize_name(legal_name)
      return [] if full.blank?

      words = full.split.first(MAX_SOFT_NAME_WORDS)
      shorter = words.size > 2 ? words.combination(words.size - 1).map { |form| form.sort.join(" ") } : []
      [full, *shorter].uniq
    end

    # The soft digests: the full name, then each pair of its words (at most
    # MAX_SOFT_NAME_WORDS words). The pair of a two-word name is the full
    # name, so a pair digest also matches the soft digest of an older Knot.
    def soft_digests(legal_name, date_of_birth)
      return [] unless date_of_birth.is_a?(Date)

      name_forms(legal_name).map { |name| digest("soft", name, date_of_birth.iso8601) }.compact.uniq
    end

    # The normalized full name, then each pair of its words (from the first
    # MAX_SOFT_NAME_WORDS words). Empty for an empty name.
    def name_forms(legal_name)
      full = normalize_name(legal_name)
      return [] if full.blank?

      words = full.split.uniq.first(MAX_SOFT_NAME_WORDS)
      [full, *words.combination(2).map { |pair| pair.sort.join(" ") }].uniq
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

    def document_country(identifiers)
      return country(identifiers.issuing_country) unless identifiers.us_driving_licence?

      "US-#{country(identifiers.issuing_region)}"
    end

    def digest(kind, *parts)
      raise ArgumentError, "unknown kind #{kind}" unless KINDS.include?(kind)
      return nil if parts.any?(&:blank?)

      Digest.new(kind:, digest: OpenSSL::HMAC.hexdigest("SHA256", pepper, [kind, *parts].join(SEPARATOR)))
    end

  end
end
