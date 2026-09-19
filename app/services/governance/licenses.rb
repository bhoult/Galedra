# frozen_string_literal: true

module Governance
  # The licences that apply to Galedra's parts (docs/LICENSE-POLICY.md), with
  # the full text of each so the Help menu can show them all. The code licence
  # in force is whatever LICENSE says; the policy's recommendations are shown
  # as recommendations until the owner adopts them. Texts are the SPDX
  # canonical files under LICENSES/.
  module Licenses
    POLICY = Rails.root.join("docs/LICENSE-POLICY.md")
    CODE_LICENSE = Rails.root.join("LICENSE")
    DIR = Rails.root.join("LICENSES")

    # Component, the SPDX id the policy recommends, and what is in force. The
    # owner adopted the recommended stack on 2026-09-19 (NOTICE); the code
    # licence is still read from LICENSE and the data licence from the node.
    STACK = [
      { component: "Reference node software (this application)", recommended: "AGPL-3.0-or-later", in_force: :code },
      { component: "Federation protocol, schemas, OpenAPI, test vectors, SDKs", recommended: "Apache-2.0", in_force: "Apache-2.0" },
      { component: "Public federated database as a whole", recommended: "ODbL-1.0", in_force: :data },
      { component: "Individual project-authored factual records", recommended: "CC0-1.0", in_force: "CC0-1.0 where legally possible" },
      { component: "Project-authored prose and documentation", recommended: "CC-BY-4.0", in_force: "CC-BY-4.0" },
      { component: "Imported third-party material", recommended: nil, in_force: :third_party }
    ].freeze

    module_function

    def policy_html
      markdown = File.read(POLICY).gsub(/^```(\w*)\s*$/) { "~~~#{$1}" }
      Kramdown::Document.new(markdown, auto_ids: true).to_html.html_safe
    end

    # The licence LICENSE grants today: its SPDX id when the text is a known
    # one under LICENSES/, else its first line.
    def code_license_name
      return "none" unless File.exist?(CODE_LICENSE)

      text = File.read(CODE_LICENSE)
      match = texts.find { |t| t[:text].strip == text.strip }
      match ? match[:id] : File.readlines(CODE_LICENSE).first.to_s.strip
    end

    def code_license_text
      File.exist?(CODE_LICENSE) ? File.read(CODE_LICENSE) : ""
    end

    def data_license
      Ledger::Node.data_license
    end

    # [{id:, text:}] for every full text held under LICENSES/, sorted.
    def texts
      Dir.glob(DIR.join("*.txt")).sort.map { |path| { id: File.basename(path, ".txt"), text: File.read(path) } }
    end

    def rows
      STACK.map do |row|
        in_force = case row[:in_force]
        when :code then code_license_name
        when :data then data_license
        when :third_party then "the original source's terms"
        else row[:in_force]
        end
        row.merge(in_force: in_force)
      end
    end
  end
end
