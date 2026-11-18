# frozen_string_literal: true

# A raw link token (magic link, guardian consent) on its way to a job.
#
# A job argument is stored as plain text in the queue table until the row is
# deleted, and /admin/jobs shows it. A token wrapped in LinkToken is stored
# encrypted, so a queue row never holds a usable link. A failed job can thus
# stay for a retry with no time limit.
#
# Wrap the token where the job or the mail is enqueued:
#
#   MagicLinkJob.perform_later(user, LinkToken.new(token))
#   GuardianConsentMailer.receipt(consent, LinkToken.new(token)).deliver_later
#
# A URL helper reads it through to_param, like a String, so a mailer takes
# both. Jobs that were queued before this class existed hold a String.
class LinkToken
  attr_reader :raw

  def initialize(raw)
    @raw = raw.is_a?(LinkToken) ? raw.raw : raw.to_s
    raise ArgumentError, "a link token cannot be blank" if @raw.empty?
  end

  # A job that enqueues a token calls this in before_enqueue, so a caller
  # that forgets to wrap the token fails at once, not in the queue table.
  # A job that is already in the queue with a plain token still runs.
  def self.refuse_plain!(*values)
    return unless values.flatten.any?(String)

    raise ArgumentError, "pass a link token to a job as LinkToken.new(token), not as a String"
  end

  def to_param = raw

  def ==(other) = other.is_a?(LinkToken) && other.raw == raw
  alias eql? ==

  delegate :hash, to: :raw

  def inspect = "#<LinkToken [FILTERED]>"

  def as_json(*) = "[FILTERED]"

  # The key comes from secret_key_base. After a rotation of that secret, a
  # job that is still in the queue cannot be read and fails.
  def self.encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key("LinkToken job argument", ActiveSupport::MessageEncryptor.key_len)
    )
  end

  # Registered in config/application.rb.
  class Serializer < ActiveJob::Serializers::ObjectSerializer
    def serialize(token)
      super("value" => LinkToken.encryptor.encrypt_and_sign(token.raw))
    end

    def deserialize(hash)
      LinkToken.new(LinkToken.encryptor.decrypt_and_verify(hash["value"]))
    end

    def klass = LinkToken

  end

end
