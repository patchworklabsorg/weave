# frozen_string_literal: true

require "rails_helper"

RSpec.describe KnotHasher do
  def identifiers(**overrides)
    defaults = {
      document_type: "passport",
      issuing_country: "DE",
      document_number: "C01X00T47",
      national_id: nil,
      legal_name: "Erika Mustermann",
      date_of_birth: Date.new(1990, 8, 12)
    }
    VerificationIdentifiers.new(**defaults, **overrides)
  end

  def soft(name, date = Date.new(1990, 8, 12)) = described_class.soft_digest(name, date).digest

  describe ".digests" do
    it "gives a document digest and a soft digest, as hex HMACs" do
      digests = described_class.digests(identifiers)

      expect(digests.map(&:kind)).to eq(%w[document soft])
      expect(digests.map(&:digest)).to all(match(/\A\h{64}\z/))
    end

    it "adds a national ID digest when there is a national ID" do
      expect(described_class.digests(identifiers(national_id: "12345678901")).map(&:kind))
        .to eq(%w[document national_id soft])
    end

    it "never contains a plain value" do
      text = described_class.digests(identifiers(national_id: "12345678901")).map(&:digest).join

      expect(text).not_to include("C01X00T47", "Mustermann", "12345678901", "1990")
    end

    it "is keyed: a plain SHA-256 of the same text is different" do
      plain = OpenSSL::Digest::SHA256.hexdigest(["document", "passport", "DE", "C01X00T47"].join(described_class::SEPARATOR))

      expect(described_class.digests(identifiers).first.digest).not_to eq(plain)
    end

    it "changes with the pepper" do
      before = described_class.digests(identifiers).first.digest
      allow(described_class).to receive(:pepper).and_return("another pepper")

      expect(described_class.digests(identifiers).first.digest).not_to eq(before)
    end

    it "separates the document type and the country" do
      passport = described_class.digests(identifiers).first.digest

      expect(described_class.digests(identifiers(document_type: "national_id_card")).first.digest).not_to eq(passport)
      expect(described_class.digests(identifiers(issuing_country: "AT")).first.digest).not_to eq(passport)
    end
  end

  describe "document numbers" do
    it "ignores case, spaces, dashes and full-width digits" do
      expect(described_class.normalize_number("c01 x00-t47")).to eq("C01X00T47")
      expect(described_class.normalize_number("Ｃ０１Ｘ００Ｔ４７")).to eq("C01X00T47")
      expect(described_class.digests(identifiers(document_number: " c01x00 t47 ")).first)
        .to eq(described_class.digests(identifiers).first)
    end
  end

  describe "legal names" do
    it "ignores case" do
      expect(soft("ERIKA MUSTERMANN")).to eq(soft("erika mustermann"))
    end

    it "ignores extra whitespace, also non-breaking and tab" do
      expect(soft("  Erika \tMustermann ")).to eq(soft("Erika Mustermann"))
    end

    it "ignores diacritics, in composed and decomposed form" do
      composed = "Zoë Ångström"
      decomposed = "Zoë Ångström"

      expect(soft(composed)).to eq(soft("Zoe Angstrom"))
      expect(soft(decomposed)).to eq(soft(composed))
    end

    it "folds letters that have no combining mark" do
      expect(described_class.normalize_name("Søren Łukasz Æsir Straße")).to eq("aesir lukasz soren strasse")
    end

    it "ignores hyphens, apostrophes and the order of the words" do
      expect(soft("O'Brien-Smith, Seán")).to eq(soft("Sean O Brien Smith"))
      expect(soft("Mustermann Erika")).to eq(soft("Erika Mustermann"))
    end

    it "keeps other scripts as they are" do
      expect(described_class.normalize_name("Иван Петров")).to eq("иван петров")
      expect(soft("Иван Петров")).not_to eq(soft("Ivan Petrov"))
    end

    it "depends on the birth date" do
      expect(soft("Erika Mustermann", Date.new(1990, 8, 13))).not_to eq(soft("Erika Mustermann"))
    end

    it "gives no soft digest for an empty name" do
      expect(described_class.soft_digest(" -- ", Date.new(1990, 8, 12))).to be_nil
    end
  end

  describe ".pepper" do
    it "uses knot.pepper from the credentials when it is set" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:knot, :pepper).and_return("from credentials")

      expect(described_class.pepper).to eq("from credentials")
    end

    it "refuses to run in production without the credential" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:knot, :pepper).and_return(nil)
      allow(Rails.env).to receive(:production?).and_return(true)

      expect { described_class.pepper }.to raise_error(KnotHasher::MissingPepper)
    end
  end
end
