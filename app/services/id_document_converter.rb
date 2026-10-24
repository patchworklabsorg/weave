# frozen_string_literal: true

require "open3"

# Turns an uploaded ID into the one image Weave stores (see VerificationFlow
# and docs/KYC.md, "Upload conversion"). It runs at upload, in memory, before
# anything is stored or sealed, so only the converted image is ever kept.
#
#   JPEG      -> JPEG (re-encoded)
#   PNG       -> PNG (re-encoded)
#   HEIC/HEIF -> JPEG
#   PDF       -> PNG of the FIRST page only
#
# Every output is re-encoded without metadata: no EXIF, no GPS, no XMP, no
# ICC profile, no PDF title or author. The EXIF orientation is applied to the
# pixels first, so the image stays upright. The type comes from the file's
# bytes (Marcel), not from its name or the browser's content type. Any other
# type, and any file that does not convert, raises Refused.
#
# HEIC and the images load in libvips (heifload, with libheif). A PDF is
# rendered by poppler's pdftoppm in a child process, with a timeout, from
# stdin to stdout: Weave blocks libvips's untrusted loaders below (the PDF
# loader is one of them, see Vips.block_untrusted), and a separate
# process keeps a bad PDF away from the web process. The PNG it gives then
# goes through libvips like any other upload. The Docker image installs
# poppler-utils and the libheif HEVC decoder (see the Dockerfile and
# docs/KYC_ROLLOUT.md).
module IdDocumentConverter
  # What a member may upload.
  ACCEPTED_TYPES = %w[image/jpeg image/png image/heic image/heif application/pdf].freeze
  # What Weave stores after the conversion.
  STORED_TYPES = %w[image/jpeg image/png].freeze
  # The first page of a PDF is rendered at this resolution.
  PDF_DPI = 200
  # A guard against an image that decompresses to a huge size.
  MAX_PIXELS = 50_000_000
  JPEG_QUALITY = 90
  # Seconds pdftoppm may take for one page.
  PDF_TIMEOUT = 20

  Converted = Data.define(:data, :content_type, :extension) do
    def io = StringIO.new(data)

    def filename = "id_document#{extension}"
  end

  class Refused < StandardError; end

  module_function

  # libvips loads on the first conversion, not at boot, so the app (and
  # zeitwerk:check in CI) boots on a machine without libvips. Active Storage
  # makes no variants (config/application.rb), so it does not block the
  # untrusted loaders for Weave. Block them here.
  def load_vips!
    return if defined?(@vips_loaded)

    require "vips"
    Vips.block_untrusted(true)
    @vips_loaded = true
  end

  # upload: an uploaded file (or any IO). Returns a Converted.
  def convert(upload)
    load_vips!
    data = read(upload)
    raise Refused, "The file is empty." if data.empty?

    type = Marcel::MimeType.for(StringIO.new(data))
    raise Refused, "The file type #{type} is not accepted." unless ACCEPTED_TYPES.include?(type)

    image = load(data, type)
    raise Refused, "The image is too large." if image.width * image.height > MAX_PIXELS

    # pdftoppm renders the page on white, with no orientation tag.
    image = image.autorot unless type == "application/pdf"
    image = image.colourspace(:srgb) unless image.interpretation == :srgb || image.bands < 3
    if %w[image/png application/pdf].include?(type)
      Converted.new(data: image.write_to_buffer(".png", strip: true), content_type: "image/png", extension: ".png")
    else
      image = image.flatten(background: [255, 255, 255]) if image.has_alpha?
      Converted.new(data: image.write_to_buffer(".jpg", strip: true, Q: JPEG_QUALITY), content_type: "image/jpeg", extension: ".jpg")
    end
  rescue Vips::Error => e
    raise Refused, "The file does not convert: #{e.message.lines.first.to_s.strip}"
  end

  def read(upload)
    io = upload.respond_to?(:tempfile) ? upload.tempfile : upload
    io.rewind if io.respond_to?(:rewind)
    data = io.read.to_s.b
    io.rewind if io.respond_to?(:rewind)
    data
  end

  # libvips reads lazily from the Ruby string. The rendered PDF page is a
  # local string here, so it is decoded at once (copy_memory) before the
  # string can go away.
  def load(data, type)
    return Vips::Image.new_from_buffer(data, "", fail: true) unless type == "application/pdf"

    Vips::Image.new_from_buffer(render_first_pdf_page(data), "", fail: true).copy_memory
  end

  # The first page of the PDF as PNG bytes, from pdftoppm (stdin to stdout,
  # nothing on disk).
  def render_first_pdf_page(data)
    command = ["pdftoppm", "-png", "-r", PDF_DPI.to_s, "-f", "1", "-l", "1", "-singlefile", "-"]
    Open3.popen3(*command) do |stdin, stdout, stderr, wait|
      writer = Thread.new do
        stdin.binmode.write(data)
      rescue Errno::EPIPE
        nil
      ensure
        stdin.close
      end
      reader = Thread.new { stdout.binmode.read }
      errors = Thread.new { stderr.read }
      unless wait.join(PDF_TIMEOUT)
        Process.kill("KILL", wait.pid)
        raise Refused, "The PDF took too long to convert."
      end
      writer.join
      png = reader.value
      errors.value
      raise Refused, "The PDF does not convert." unless wait.value.success? && png.to_s.start_with?("\x89PNG".b)

      png
    end
  rescue Errno::ENOENT
    raise Refused, "PDF conversion is not available (pdftoppm is missing)."
  end
end
