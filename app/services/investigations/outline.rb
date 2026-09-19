# frozen_string_literal: true

module Investigations
  # Stage 21: a large source (a transcript, a speech, a long article) recorded
  # as structure first. One call records the source by link, an anchor
  # location per leaf, the whole tree as one CREATE_SECTION, and one
  # CLAIM_EXTRACTION task per leaf, so other volunteers' assistants can take
  # the work in pieces. The transcript is never stored: an anchor is at most
  # ANCHOR_MAX quoted characters, enough to find the place in the source.
  module Outline
    ANCHOR_MAX = 300
    LOCATOR_TYPES = %w[TIME_RANGE CHAR_RANGE PAGE LINE_RANGE SECTION].freeze
    NEXT = "Tell the person the outline is recorded with %<sections>d sections and %<tasks>d open extraction tasks at %<url>s, and ask whether they want you to start on the research yourself now. If yes, work leaf by leaf: read the leaf in the source, record its claims and evidence with record_investigation giving each claim its section id, say which leaf is done, and stop when the person says so or your daily cap nears. Anyone else can help by telling their assistant \"work the open tasks in Galedra on %<url>s\"."

    module_function

    def call(token, bundle, base_url:)
      Validate.call(bundle)
      ids = {}
      readings = {}
      handles = {}
      root = nil
      count = 0
      Contribution.transaction do
        parent = bundle["parent_section_id"] && Section.find(bundle["parent_section_id"])
        source_id = parent ? parent.source_id : write(token, "CREATE_SOURCE", source_payload(bundle["source"]), "source", Source).id
        count += 1 unless parent
        leaves(bundle["sections"]).each do |leaf|
          next if leaf["anchor"].blank?

          locator = (leaf["locator"] || {}).dup
          type = locator.delete("type") || "SECTION"
          payload = { "source_id" => source_id, "locator_type" => type, "locator" => locator, "excerpt" => leaf["anchor"].to_s.strip[0, ANCHOR_MAX] }
          payload["excerpt_hash"] = Crypto::Hashing.bytes(payload["excerpt"])
          ids[leaf["handle"]] = write(token, "CREATE_SOURCE_LOCATION", payload, "location", SourceLocation).id
          count += 1

          reading = leaf["reading"].to_s.strip
          next if reading.blank?

          reading = reading[0, READING_MAX]
          reading_payload = { "source_id" => source_id, "locator_type" => "TRANSCRIPTION", "locator" => locator,
                              "excerpt" => reading, "excerpt_hash" => Crypto::Hashing.bytes(reading) }
          readings[leaf["handle"]] = write(token, "CREATE_SOURCE_LOCATION", reading_payload, "location", SourceLocation).id
          count += 1
        end
        nodes = payload_nodes(bundle["sections"], ids, readings)
        section_payload = parent ? { "parent_section_id" => parent.id, "sections" => nodes } : { "source_id" => source_id, "sections" => nodes }
        result = Assistants::Write.call(token, "CREATE_SECTION", section_payload)
        count += 1
        n = -1
        walk(bundle["sections"]) { |node| handles[node["handle"]] = Ledger::Ids.derive(result.contribution.id, "section", n += 1) }
        root = parent ? parent.root : Section.find(handles[bundle["sections"].first["handle"]])
      end
      tasks = bundle.fetch("open_tasks", true) ? open_extraction_tasks(token, bundle, handles, ids) : 0
      seq = Contribution.maximum(:seq)
      investigation = Investigation.create!(id: SecureRandom.uuid_v7, assistant_token: token, statement: bundle["statement"].presence, claim_ids: [], snapshot_seq: seq, section_id: root.id)
      url = "#{base_url}/sections/#{root.id}"
      { recorded: true, snapshot_seq: seq, contributions: count, root_id: root.id, root_url: url, sections: handles.transform_values { |id| { id: id, url: "#{base_url}/sections/#{id}" } },
        locations: ids, readings: readings, tasks_opened: tasks, share_line: Record.outline_share_line(root, seq, url), investigation_url: "#{base_url}/investigations/#{investigation.id}",
        attribution: Record.attribution(token, base_url),
        next: format(NEXT, sections: handles.size, tasks: tasks, url: url) }
    end

    def write(token, action, payload, kind, model)
      result = Assistants::Write.call(token, action, payload)
      model.find(Ledger::Ids.derive(result.contribution.id, kind))
    end

    def source_payload(s)
      { "source_type" => s["type"], "title" => s["title"], "canonical_uri" => s["url"], "content_hash" => s["content_hash"], "retrieved_at" => s["retrieved_at"],
        "publisher" => s["publisher"], "creator" => s["creator"], "publication_date" => s["publication_date"] }.compact
    end

    def payload_nodes(nodes, ids, readings = {})
      nodes.map do |n|
        out = { "heading" => n["heading"] }
        out["location_id"] = ids[n["handle"]] if ids[n["handle"]]
        out["reading_location_id"] = readings[n["handle"]] if readings[n["handle"]]
        children = n.fetch("sections", [])
        out["sections"] = payload_nodes(children, ids, readings) if children.any?
        out
      end
    end

    def walk(nodes, &block)
      nodes.each do |n|
        block.call(n)
        walk(n.fetch("sections", []), &block)
      end
    end

    def leaves(nodes)
      nodes.flat_map { |n| n.fetch("sections", []).any? ? leaves(n["sections"]) : [ n ] }
    end

    # One extraction task per leaf with an anchor: the volunteer reads the range in
    # the source itself (the packet carries the locator, the heading, and the anchor).
    def open_extraction_tasks(token, bundle, handles, ids)
      factor = token.anonymous? ? Record::ANONYMOUS_PRIORITY_FACTOR : "1"
      leaves(bundle["sections"]).count do |leaf|
        location_id = ids[leaf["handle"]]
        next false if location_id.nil?

        section = Section.find(handles[leaf["handle"]])
        next false if Task.where(task_type: "CLAIM_EXTRACTION", section_id: section.id, status: %w[OPEN LEASED COMPLETE]).exists? # the same outline again opens nothing
        domain = Audits::Policy.default_domain
        Tasks::Create.call(task_type: "CLAIM_EXTRACTION", target: section.source, domain: domain, location: SourceLocation.find(location_id),
                           created_by: token.agent, priority_factor: factor, section_id: section.id)
        true
      end
    end

    module Validate
      module_function

      def call(bundle)
        errors = []
        add = ->(path, detail) { errors << { code: "SCHEMA_INVALID", path: path, detail: detail } }
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$", detail: "expected an object" } ]) unless bundle.is_a?(Hash)
        statement = bundle["statement"]
        add.call("$.statement", "the title and link of what is being checked, at most #{Investigation::MAX_STATEMENT_CHARS} characters") unless statement.nil? || (statement.is_a?(String) && statement.length <= Investigation::MAX_STATEMENT_CHARS)
        if bundle["parent_section_id"]
          add.call("$.parent_section_id", "no such section") unless Section.live.exists?(id: bundle["parent_section_id"].to_s)
        else
          s = bundle["source"]
          if s.is_a?(Hash)
            add.call("$.source.type", "expected one of #{Source::TYPES.join(', ')}") unless Source::TYPES.include?(s["type"])
            add.call("$.source.title", "required") unless s["title"].is_a?(String) && s["title"].present?
            add.call("$.source.url", "required: the link to the transcript, recording, or text") unless s["url"].is_a?(String) && s["url"].present?
            add.call("$.source.retrieved_at", "required: RFC 3339 time the source was read") unless (Time.iso8601(s["retrieved_at"].to_s) rescue nil)
          else
            add.call("$.source", "required: {type, title, url, retrieved_at}")
          end
        end
        nodes = bundle["sections"]
        if nodes.is_a?(Array) && nodes.any?
          handles = {}
          check_nodes(nodes, "$.sections", 0, handles, add)
          add.call("$.sections", "at most #{Section::MAX_PER_CONTRIBUTION} sections") if handles.size > Section::MAX_PER_CONTRIBUTION
          add.call("$.sections", "one root: give a single top-level section for a new outline") if bundle["parent_section_id"].nil? && nodes.size != 1
        else
          add.call("$.sections", "expected a non-empty array of {handle, heading, locator?, anchor?, sections?}")
        end
        raise Ledger::Rejected.new(errors) if errors.any?

        true
      end

      def check_nodes(nodes, at, depth, handles, add)
        add.call(at, "deeper than #{Section::MAX_DEPTH} levels") if depth >= Section::MAX_DEPTH
        nodes.each_with_index do |n, i|
          here = "#{at}[#{i}]"
          add.call(here, "expected an object") && next unless n.is_a?(Hash)
          h = n["handle"]
          add.call("#{here}.handle", "expected a unique string handle") if !h.is_a?(String) || h.empty? || handles.key?(h)
          handles[h] = true if h.is_a?(String)
          add.call("#{here}.heading", "expected a non-empty string of at most #{Section::MAX_HEADING} characters") unless n["heading"].is_a?(String) && n["heading"].strip.present? && n["heading"].length <= Section::MAX_HEADING
          add.call("#{here}.anchor", "at most #{ANCHOR_MAX} quoted characters; the passage itself is never stored") if n["anchor"].is_a?(String) && n["anchor"].length > ANCHOR_MAX
          if n["locator"]
            add.call("#{here}.locator", "expected an object") && next unless n["locator"].is_a?(Hash)
            type = n["locator"]["type"] || "SECTION"
            add.call("#{here}.locator.type", "expected one of #{LOCATOR_TYPES.join(', ')}") unless LOCATOR_TYPES.include?(type)
          end
          children = n.fetch("sections", [])
          add.call("#{here}.sections", "expected an array") && next unless children.is_a?(Array)
          check_nodes(children, "#{here}.sections", depth + 1, handles, add) if children.any?
        end
      end
    end
  end
end
