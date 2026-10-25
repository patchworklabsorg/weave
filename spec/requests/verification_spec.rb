# frozen_string_literal: true

require "rails_helper"

# The member's side of identity verification.
RSpec.describe "Identity verification", type: :request do
  let(:member) { create(:user, :verified) }
  let(:image) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.png"), "image/png") }
  let(:params) { { document_type: "passport", id_document: image, data_notice_read: "1" } }

  # ID checks open only after the key ceremony (VerificationFlow.submission_blocker).
  before { active_key_set_without_holders }


  it "needs a signed-in member" do
    get verification_path

    expect(response).to redirect_to("/login")
  end

  it "shows the steps, the status and the data page link" do
    sign_in_via_magic_link(member)

    get verification_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("verification.page.title"), I18n.t("verification.statuses.needs_submission"),
                                     Weave.data_page_url)
  end

  it "links the profile page to the verification page and the data page" do
    sign_in_via_magic_link(member)

    get profile_path

    expect(response.body).to include(verification_path, Weave.data_page_url)
  end

  it "takes an upload and starts an attempt" do
    sign_in_via_magic_link(member)

    expect { post verification_path, params: }.to change(Verification, :count).by(1)

    expect(response).to redirect_to(verification_path)
    expect(member.reload.verification_status).to eq("pending")
    expect(member.latest_verification.id_document).to be_attached
  end

  it "needs the member to confirm they read the data page" do
    sign_in_via_magic_link(member)

    expect { post verification_path, params: params.merge(data_notice_read: "0") }.not_to change(Verification, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("verification.errors.data_notice"))
  end

  it "refuses a file that is not an image" do
    sign_in_via_magic_link(member)
    text = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/not_an_image.txt"), "text/plain")

    expect { post verification_path, params: params.merge(id_document: text) }.not_to change(Verification, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(CGI.escapeHTML(I18n.t("verification.errors.document_unsupported")))
  end

  it "refuses a WebP and a broken image with the member message, and stores nothing" do
    sign_in_via_magic_link(member)

    %w[id_document.webp broken_image.jpg].each do |name|
      file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files", name), "image/jpeg")
      expect { post verification_path, params: params.merge(id_document: file) }.not_to change(ActiveStorage::Blob, :count)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("verification.errors.document_unsupported")))
    end
  end

  it "stores only the converted JPEG, with no EXIF or GPS and a neutral name" do
    sign_in_via_magic_link(member)
    photo = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document_exif.jpg"), "image/jpeg", original_filename: "jane_doe_passport.jpg")

    post verification_path, params: params.merge(id_document: photo)

    document = Verification.last.id_document
    expect(document.filename.to_s).to eq("id_document.jpg")
    expect(document.content_type).to eq("image/jpeg")
    stored = document.download
    expect(stored).not_to include("WEAVE-SECRET")
    expect(Vips::Image.new_from_buffer(stored, "").get_fields.grep(/exif|xmp|icc|orientation/)).to be_empty
  end

  it "stores the first page of a PDF as PNG", skip: (ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "pdftoppm")) } ? false : "pdftoppm (poppler-utils) is not installed here") do
    sign_in_via_magic_link(member)
    pdf = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.pdf"), "application/pdf")

    post verification_path, params: params.merge(id_document: pdf)

    document = Verification.last.id_document
    expect(document).to have_attributes(content_type: "image/png")
    expect(document.filename.to_s).to eq("id_document.png")
    expect(document.download).not_to include("WEAVE-SECRET")
  end

  it "says the document is OK and that the team will agree a call time" do
    create(:verification, :awaiting_call, user: member)
    sign_in_via_magic_link(member)

    get verification_path

    expect(response.body).to include(CGI.escapeHTML(I18n.t("verification.page.awaiting_call")),
                                     I18n.t("verification.statuses.pending"))
  end

  it "shows the note after a document problem, and takes a new upload" do
    create(:verification, user: member, status: "needs_resubmission", resubmission_note: "The photo is blurry.")
    sign_in_via_magic_link(member)

    get verification_path
    expect(response.body).to include("The photo is blurry.", I18n.t("verification.page.resubmit"))

    expect { post verification_path, params: }.to change(Verification, :count).by(1)
  end

  it "shows the retry date during the cooldown and takes no upload" do
    failed = create(:verification, :failed, user: member, decided_at: 1.day.ago)
    sign_in_via_magic_link(member)

    get verification_path
    expect(response.body).to include(failed.retry_available_at.to_date.strftime(TimeHelper::FORMATS[:date]))

    expect { post verification_path, params: }.not_to change(Verification, :count)
  end

  it "does not let an impersonating admin upload for the member" do
    sign_in_via_magic_link(create(:user, :owner, :verified))
    post impersonate_admin_user_path(member)
    expect(session[:admin_id]).to be_present

    expect { post verification_path, params: }.not_to change(Verification, :count)
  end
end
