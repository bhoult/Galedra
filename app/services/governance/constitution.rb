# frozen_string_literal: true

module Governance
  # The constitution (CONSTITUTION.md, a verbatim copy of the spec's
  # 12-constitution.md) and its integrity hash, published by GET /api/v1/meta
  # so anyone can check which principles a running ledger claims to follow.
  # The landing page renders the same bytes, parsed into sections, so what a
  # visitor reads is what the hash covers.
  class Constitution
    PATH = Rails.root.join("CONSTITUTION.md")
    VERSION_PATTERN = /^\| Version \| (\d+\.\d+\.\d+)/
    ARTICLE_PATTERN = /\A## Article ([IVXL]+) — (.+)\z/

    Section = Struct.new(:kind, :numeral, :title, :markdown, keyword_init: true) do
      def html = Kramdown::Document.new(markdown, auto_ids: false).to_html.html_safe
      def article? = kind == :article
    end

    def self.call = new.to_h

    def bytes
      @bytes ||= File.binread(PATH)
    end

    # Through Crypto::Hashing, which owns the prefix and its validator: this is
    # the one hash an outside auditor checks a running ledger against.
    def digest
      Crypto::Hashing.bytes(bytes)
    end

    def version
      bytes[VERSION_PATTERN, 1]
    end

    def to_h
      { version: version, hash: digest }
    end

    # Every "## Article", plus the Preamble, the Constitutional Test, and the
    # Foundational Statement, in file order. Front matter (the version table and
    # reading notes) is not a section.
    def sections
      @sections ||= split(bytes.force_encoding("UTF-8"))
    end

    def articles = sections.select(&:article?)
    def preamble = sections.find { |s| s.kind == :preamble }
    def test = sections.find { |s| s.kind == :test }
    def foundational_statement = sections.find { |s| s.kind == :statement }

    private

    def split(text)
      sections = []
      current = nil
      text.each_line(chomp: true) do |line|
        heading = heading_for(line)
        if heading
          sections << current if current
          current = heading
        elsif current && line != "---"
          current.markdown << line << "\n"
        end
      end
      sections << current if current
      sections.each { |s| s.markdown.strip! }
    end

    def heading_for(line)
      case line
      when ARTICLE_PATTERN then Section.new(kind: :article, numeral: $1, title: $2, markdown: +"")
      when "## Preamble" then Section.new(kind: :preamble, title: "Preamble", markdown: +"")
      when "# Constitutional Test" then Section.new(kind: :test, title: "Constitutional Test", markdown: +"")
      when "# Foundational Statement" then Section.new(kind: :statement, title: "Foundational Statement", markdown: +"")
      end
    end
  end
end
