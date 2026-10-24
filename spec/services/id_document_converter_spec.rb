# frozen_string_literal: true

require "rails_helper"

# The upload conversion of ID images (see IdDocumentConverter). The fixtures
# are small files made with libvips (JPEG with EXIF and GPS, HEIC, WebP), a
# two-page PDF written by hand (page 1 red, page 2 blue, with a title and an
# author), and a broken JPEG.
RSpec.describe IdDocumentConverter do
  def fixture(name) = File.open(Rails.root.join("spec/fixtures/files", name))

  def decode(converted) = Vips::Image.new_from_buffer(converted.data, "")

  def metadata_fields(image) = image.get_fields.grep(/exif|xmp|icc|iptc|orientation/)

  # HEIC needs libvips with libheif and an HEVC decoder. A CI image without
  # them can't decode the fixture, so those examples skip.
  heic_ready = begin
    Vips::Image.new_from_buffer(Rails.root.join("spec/fixtures/files/id_document.heic").binread, "").avg
    true
  rescue Vips::Error
    false
  end
  # PDF needs poppler's pdftoppm on the PATH.
  pdf_ready = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "pdftoppm")) }

  it "re-encodes a JPEG without EXIF or GPS, upright" do
    converted = described_class.convert(fixture("id_document_exif.jpg"))
    image = decode(converted)

    expect(converted).to have_attributes(content_type: "image/jpeg", extension: ".jpg", filename: "id_document.jpg")
    expect(metadata_fields(image)).to be_empty
    expect(converted.data).not_to include("WEAVE-SECRET")
    # The source is 64 x 40 with orientation 6: the pixels are turned.
    expect([image.width, image.height]).to eq([40, 64])
  end

  it "re-encodes a PNG without metadata" do
    converted = described_class.convert(fixture("id_document.png"))

    expect(converted.content_type).to eq("image/png")
    expect(metadata_fields(decode(converted))).to be_empty
  end

  it "turns HEIC into JPEG without metadata", skip: (heic_ready ? false : "libvips here can't decode HEIC (libheif with an HEVC decoder is missing)") do
    converted = described_class.convert(fixture("id_document.heic"))
    image = decode(converted)

    expect(converted.content_type).to eq("image/jpeg")
    expect(metadata_fields(image)).to be_empty
    expect(converted.data).not_to include("WEAVE-SECRET")
    expect(image.getpoint(5, 5).map(&:round)).to all(be_between(0, 255))
  end

  it "turns only the first page of a PDF into PNG, without its title or author", skip: (pdf_ready ? false : "pdftoppm (poppler-utils) is not installed here") do
    converted = described_class.convert(fixture("id_document.pdf"))
    image = decode(converted)

    expect(converted.content_type).to eq("image/png")
    red, green, blue = image.getpoint(5, 5)
    expect([red, green, blue]).to eq([255.0, 0.0, 0.0])
    expect(converted.data).not_to include("WEAVE-SECRET", "Jane Doe")
  end

  it "refuses a PDF that does not render", skip: (pdf_ready ? false : "pdftoppm (poppler-utils) is not installed here") do
    broken = StringIO.new("%PDF-1.4\nnot really a pdf\n%%EOF\n")

    expect { described_class.convert(broken) }.to raise_error(described_class::Refused)
  end

  it "refuses a type it does not accept, by its bytes and not its name" do
    expect { described_class.convert(fixture("id_document.webp")) }.to raise_error(described_class::Refused, %r{image/webp})
    expect { described_class.convert(fixture("not_an_image.txt")) }.to raise_error(described_class::Refused)
  end

  it "refuses a file that fails to convert" do
    expect { described_class.convert(fixture("broken_image.jpg")) }.to raise_error(described_class::Refused, /does not convert/)
  end

  it "refuses an empty file" do
    expect { described_class.convert(StringIO.new("")) }.to raise_error(described_class::Refused, /empty/)
  end
end
