# frozen_string_literal: true

module Ledger
  # Legally compelled removal (spec 02 §5). The TAKEDOWN payload carries a
  # redaction manifest: every projection row of the target contribution, the
  # fields removed from it, and the retained (non-sensitive) values. The
  # target's payload and envelope bytes are deleted; its hashes, entry hash,
  # and server signature stay so the chain still verifies. Replay rebuilds the
  # rows from the manifest with the removed fields nulled.
  module Redaction
    REDACTABLE = {
      "sources" => %w[title creator publisher canonical_uri external_ids content license lineage_key metadata],
      "source_locations" => %w[locator excerpt],
      "claims" => %w[canonical_text qualifiers extracted_from_source_id],
      "evidence_items" => %w[statement structured_value],
      "evidence_claim_links" => %w[note],
      "independence_groups" => %w[description],
      "claim_edges" => [],
      "independence_group_assignments" => [],
      "claim_merges" => [],
      "claim_evaluability_settings" => []
    }.freeze
    SYSTEM_COLUMNS = %w[id contribution_id created_seq invalidated_seq accepted_seq redacted_by_seq].freeze

    class ManifestError < StandardError
      attr_reader :code, :path

      def initialize(code, path, detail)
        @code = code
        @path = path
        super(detail)
      end
    end

    # The default manifest for a contribution: every redactable field removed.
    def self.manifest_for(contribution, removed: nil)
      contribution.projection_rows.map do |row|
        table = row.class.table_name
        fields = removed ? (removed[table] || []) & REDACTABLE.fetch(table) : REDACTABLE.fetch(table)
        { "table" => table, "id" => row.id, "removed" => fields, "retained" => retained_values(row, fields) }
      end
    end

    def self.retained_values(row, removed)
      row.attributes.except(*SYSTEM_COLUMNS, *removed).as_json
    end

    def self.redacted_value(model, column_name)
      column = model.columns_hash.fetch(column_name)
      column.null ? nil : model.column_defaults[column_name]
    end

    # Checks a manifest against the current projection rows.
    def self.validate!(contribution, manifest)
      raise ManifestError.new("SCHEMA_INVALID", "$.payload.redaction_manifest", "expected an array") unless manifest.is_a?(Array)

      rows = contribution.projection_rows.index_by(&:id)
      seen = []
      manifest.each_with_index do |entry, i|
        path = "$.payload.redaction_manifest[#{i}]"
        raise ManifestError.new("SCHEMA_INVALID", path, "expected an object") unless entry.is_a?(Hash)

        row = rows[entry["id"]]
        raise ManifestError.new("MANIFEST_MISMATCH", path, "row does not belong to the target contribution") if row.nil?
        raise ManifestError.new("MANIFEST_MISMATCH", path, "table does not match the row") unless entry["table"] == row.class.table_name

        removed = entry["removed"]
        allowed = REDACTABLE.fetch(row.class.table_name)
        unless removed.is_a?(Array) && removed.all?(String) && (removed - allowed).empty?
          raise ManifestError.new("MANIFEST_MISMATCH", "#{path}.removed", "removable fields for #{row.class.table_name}: #{allowed.join(', ')}")
        end
        unless entry["retained"] == retained_values(row, removed)
          raise ManifestError.new("MANIFEST_MISMATCH", "#{path}.retained", "retained values do not match the current row; rebuild the manifest")
        end
        seen << row.id
      end
      missing = rows.keys - seen
      raise ManifestError.new("MANIFEST_MISMATCH", "$.payload.redaction_manifest", "manifest omits rows: #{missing.join(', ')}") if missing.any?
    end

    # Applies a takedown that has just been appended: nulls the manifest's
    # fields on the live rows and deletes the target's bytes.
    def self.apply!(takedown)
      target = Contribution.find(takedown.payload["contribution_id"])
      takedown.payload["redaction_manifest"].each do |entry|
        model = entry["table"].classify.constantize
        row = model.find(entry["id"])
        values = entry["removed"].to_h { |field| [ field, redacted_value(model, field) ] }
        row.update!(values.merge("redacted_by_seq" => takedown.seq))
      end
      delete_bytes!(target, takedown.seq)
    end

    def self.delete_bytes!(target, takedown_seq)
      DatabaseRole.as_owner do
        Contribution.where(id: target.id).update_all(payload: nil, envelope: nil, redacted_by_seq: takedown_seq)
      end
    end

    # Rebuilds a redacted contribution's rows during replay.
    def self.rebuild!(contribution)
      takedown = Contribution.find_by!(seq: contribution.redacted_by_seq, action_type: "TAKEDOWN")
      takedown.payload["redaction_manifest"].each do |entry|
        model = entry["table"].classify.constantize
        values = entry["retained"].merge(entry["removed"].to_h { |field| [ field, redacted_value(model, field) ] })
        model.create!(values.merge("id" => entry["id"], "contribution_id" => contribution.id,
                                   "created_seq" => contribution.seq, "redacted_by_seq" => takedown.seq))
      end
    end
  end
end
