# frozen_string_literal: true

# The JSON answer for the secure ID image viewer (see
# app/javascript/lib/secure_viewer.js and docs/KYC.md).
#
# The image bytes go out only as Base64 in JSON, to a POST from the viewer
# script, never as a URL that a browser can open as an image. The answer is
# never cached and is an attachment, so a browser that opens it does not
# render it.
module SecureImageResponse
  extend ActiveSupport::Concern

  private

  def no_store_headers!
    # Rails reduces this to "private, no-store": no-store is the stronger.
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, private, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Disposition"] = 'attachment; filename="id-image.json"'
  end

  # subject_id is the public id of the verification or the request, for the
  # watermark.
  def render_secure_image(data:, content_type:, subject_id:)
    no_store_headers!
    render json: {
      data: Base64.strict_encode64(data),
      content_type:,
      watermark: secure_image_watermark(subject_id)
    }
  end

  def render_secure_image_error(message, status: :forbidden)
    no_store_headers!
    render json: { error: message }, status:
  end

  def secure_image_watermark(subject_id)
    { name: current_user.full_name, pId: current_user.p_id, subjectId: subject_id, time: Time.current.utc.iso8601 }
  end

end
