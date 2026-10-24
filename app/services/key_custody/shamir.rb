# frozen_string_literal: true

# Shamir's Secret Sharing over GF(2^8), for the image master key (see
# KeyCustody and docs/KYC.md, "Key custody").
#
# The browser splits the master key with the audited JavaScript library
# "shamir-secret-sharing" (Privy, audited by Cure53 and Zellic). No Ruby
# library of that standard exists, so this module is a small port of the
# same algorithm. It uses the same share format, so a share made in the
# browser combines here:
#
#   share = y bytes (one for each secret byte) followed by one x byte
#
# The field is GF(2^8) with the AES polynomial x^8 + x^4 + x^3 + x + 1
# (0x11b), the same field as the library and HashiCorp Vault. The specs
# check the module against vectors from the library and check every 2-of-3
# subset.
#
# Combine gives a wrong value, not an error, for a wrong share. The caller
# must check the result (KeyCustody checks the rebuilt key against the
# stored master public key).
#
# Ruby gives no constant-time guarantee. The arithmetic below has no branch
# or table lookup on a secret value, to keep the timing as flat as Ruby
# allows.
module KeyCustody
  module Shamir
    class Error < StandardError; end

    POLYNOMIAL = 0x11b

    module_function

    # Splits secret (a binary String) into share_count shares. Any threshold
    # of them rebuild it. The x values are random, distinct and not zero,
    # like the library.
    def split(secret, share_count:, threshold:)
      # Not blank?: a binary secret of space bytes is not empty.
      raise Error, "The secret is empty" if secret.nil? || secret.empty? # rubocop:disable Rails/Blank
      raise Error, "Shares must be 2 to 255" unless (2..255).cover?(share_count)
      raise Error, "The threshold must be 2 to 255" unless (2..255).cover?(threshold)
      raise Error, "There can't be fewer shares than the threshold" if share_count < threshold

      xs = (1..255).to_a.shuffle(random: SecureRandom)[0, share_count]
      bytes = secret.bytes
      shares = xs.map { |_x| Array.new(bytes.length + 1, 0) }
      shares.each_with_index { |share, index| share[bytes.length] = xs[index] }

      bytes.each_with_index do |byte, position|
        coefficients = [byte] + SecureRandom.random_bytes(threshold - 1).bytes
        xs.each_with_index do |x, index|
          shares[index][position] = evaluate(coefficients, x)
        end
        coefficients.fill(0)
      end
      bytes.fill(0)

      shares.map { |share| share.pack("C*").tap { share.fill(0) } }
    end

    # Rebuilds the secret from at least two shares of the same length with
    # distinct x values.
    def combine(shares)
      raise Error, "At least 2 shares are needed" unless shares.is_a?(Array) && shares.length >= 2
      raise Error, "At most 255 shares" if shares.length > 255

      length = shares.first.bytesize
      raise Error, "Each share must be at least 2 bytes" if length < 2
      raise Error, "All shares must have the same length" unless shares.all? { |share| share.bytesize == length }

      xs = shares.map { |share| share.getbyte(length - 1) }
      raise Error, "A share has the x value 0" if xs.include?(0)
      raise Error, "Two shares have the same x value" if xs.uniq.length != xs.length

      secret = Array.new(length - 1) do |position|
        ys = shares.map { |share| share.getbyte(position) }
        interpolate_at_zero(xs, ys)
      end
      secret.pack("C*").tap { secret.fill(0) }
    end

    # Horner's rule: coefficients[0] is the secret byte.
    def evaluate(coefficients, x)
      raise Error, "x must not be 0" if x.zero?

      result = 0
      coefficients.reverse_each { |coefficient| result = multiply(result, x) ^ coefficient }
      result
    end

    # Lagrange interpolation at x = 0. In GF(2^8), subtraction is XOR, so
    # (0 - xj) / (xi - xj) is xj / (xi ^ xj).
    def interpolate_at_zero(xs, ys)
      result = 0
      xs.each_with_index do |xi, i|
        basis = 1
        xs.each_with_index do |xj, j|
          next if i == j

          basis = multiply(basis, divide(xj, xi ^ xj))
        end
        result ^= multiply(ys[i], basis)
      end
      result
    end

    # Carry-less multiplication modulo the AES polynomial, eight rounds for
    # every input.
    def multiply(a, b)
      product = 0
      8.times do
        product ^= -(b & 1) & a
        high = -((a >> 7) & 1)
        a = ((a << 1) ^ (high & POLYNOMIAL)) & 0xff
        b >>= 1
      end
      product
    end

    # a / b = a * b^254 (b^255 = 1 for each b that is not 0).
    def divide(a, b)
      raise Error, "Division by zero" if b.zero?

      multiply(a, inverse(b))
    end

    def inverse(value)
      result = 1
      base = value
      exponent = 254
      8.times do
        result = multiply(result, base) if exponent.odd?
        base = multiply(base, base)
        exponent >>= 1
      end
      result
    end
  end
end
