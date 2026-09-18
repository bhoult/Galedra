# frozen_string_literal: true

# The topic vocabulary (Stage 15): config/topics.yml read once, with lookups
# by path, the audit/reputation domain each path maps to, a keyword guess for
# the Analyze form, and a claim's current topics at a seq.
module Topics
  PATH = Rails.root.join("config/topics.yml")
  MAX_PER_CLAIM = 5

  Node = Struct.new(:path, :slug, :label, :scope, :domain, :parent, :children, keyword_init: true) do
    def top? = parent.nil?
  end

  module_function

  def tree
    @tree ||= YAML.safe_load_file(PATH).fetch("topics").map do |t|
      top = Node.new(path: t["slug"], slug: t["slug"], label: t["label"], scope: t["scope"], domain: t["domain"], parent: nil, children: [])
      top.children = Array(t["children"]).map do |c|
        Node.new(path: "#{top.slug}/#{c['slug']}", slug: c["slug"], label: c["label"], scope: c["scope"], domain: c["domain"] || top.domain, parent: top, children: [])
      end
      top
    end.freeze
  end

  def index
    @index ||= tree.flat_map { |t| [ t, *t.children ] }.to_h { |n| [ n.path, n ] }.freeze
  end

  def all = index.keys
  def valid?(path) = index.key?(path.to_s)
  def find(path) = index[path.to_s]
  def label(path) = find(path)&.label || path.to_s
  def domain_for(path) = find(path)&.domain
  def domains = index.values.map(&:domain).uniq.freeze
  def top_level(path) = path.to_s.split("/").first

  # The paths a claim carries at a seq: current tags from every principal.
  def for_claim(claim, seq)
    ClaimTopic.current_at(seq).where(claim_id: claim.id).order(:created_seq).pluck(:topic).uniq
  end

  def domain_for_claim(claim, seq)
    first = for_claim(claim, seq).first
    first && domain_for(first)
  end

  # Counts by assessment state for a topic and everything under it, rolled up.
  def paths_under(path)
    node = find(path)
    node ? [ node.path, *node.children.map(&:path) ] : []
  end

  # Surface cues for the Analyze form: proposals only, a person edits them.
  CUES = {
    "science/biology" => /\b(cell|gene|dna|species|evolution|organism|protein)s?\b/i,
    "science/medicine" => /\b(doctor|patient|disease|treatment|drug|clinical|hospital|cancer|symptom)s?\b/i,
    "science/neuroscience" => /\b(brain|neuron|cortex|neural)s?\b/i,
    "science/psychology" => /\b(psycholog|behaviou?r|cognitive|memory|iq)\w*/i,
    "science/physics" => /\b(quantum|gravity|particle|energy|light-year|relativity)\w*/i,
    "science/earth" => /\b(earthquake|volcano|geolog|ocean|glacier)\w*/i,
    "science/space" => /\b(space|orbit|astronaut|planet|moon|mars|nasa|telescope|satellite|galaxy)s?\b/i,
    "mathematics/statistics" => /\b(\d+(\.\d+)?%|percent|survey|sample|average|median|statistic)\w*/i,
    "technology/ai" => /\b(ai|artificial intelligence|chatgpt|llm|neural network|machine learning)\b/i,
    "technology/software" => /\b(software|app|website|code|bug|open[- ]source)\w*/i,
    "technology/security" => /\b(hack|breach|malware|encrypt|password)\w*/i,
    "health/vaccines" => /\b(vaccin|immuni[sz]|mrna|jab)\w*/i,
    "health/nutrition" => /\b(diet|calorie|sugar|vitamin|nutrient|obesity)\w*/i,
    "health/public-health" => /\b(pandemic|outbreak|mortality|public health|life expectancy)\w*/i,
    "environment/climate" => /\b(climate|warming|carbon|emission|co2|sea level)\w*/i,
    "environment/energy" => /\b(solar|wind power|nuclear|oil|gas|coal|renewable)\w*/i,
    "environment/wildlife" => /\b(wildlife|endangered|extinct|habitat|deforest)\w*/i,
    "politics/elections" => /\b(election|ballot|vote[rs]?|poll|candidate|turnout)\w*/i,
    "politics/policy" => /\b(policy|bill|tax|regulation|budget|subsid)\w*/i,
    "politics/government" => /\b(president|prime minister|mayor|governor|congress|parliament|senate|minister)\w*/i,
    "politics/geopolitics" => /\b(war|treaty|nato|sanction|border|military|invasion)\w*/i,
    "economics/markets" => /\b(stock market|stocks?|shares|investors?|bonds?|crypto|bitcoin|wall street)\b/i,
    "economics/employment" => /\b(jobs?|unemployment|wages?|workers?|remote work|productivity)\b/i,
    "economics/prices" => /\b(inflation|prices?|cost of living|cpi)\b/i,
    "economics/business" => /\b(company|companies|ceo|revenue|profit|startup|merger)\w*/i,
    "law/courts" => /\b(court|judge|ruling|lawsuit|verdict|supreme)\w*/i,
    "law/legislation" => /\b(laws?|statutes?|legal|illegal|banned|bans?|prohibits?|prohibited|prohibition)\b/i,
    "history/ancient" => /\b(ancient|bc|bce|pharaoh|roman|greek|babylon|sumer|watchers?|enoch)\w*/i,
    "history/modern" => /\b(1[6-9]\d\d|century|world war|cold war)\b/i,
    "history/archaeology" => /\b(archaeolog|excavat|artifact|tomb|ruins?)\w*/i,
    "religion/theology" => /\b(god|theolog|doctrine|salvation|divine)\w*/i,
    "religion/scripture" => /\b(bible|scripture|gospel|torah|quran|verse|genesis|psalm)\w*/i,
    "religion/church-history" => /\b(church|pope|reformation|council of)\w*/i,
    "society/media" => /\b(media|journalist|newspaper|broadcast|social media|viral)\w*/i,
    "society/education" => /\b(school|student|teacher|university|literacy)\w*/i,
    "society/crime" => /\b(crime|murder|theft|police|arrest|prison)\w*/i,
    "society/immigration" => /\b(immigra|migrant|refugee|asylum|visa)\w*/i,
    "culture/memes" => /\b(meme|hoax|urban legend|went viral)\w*/i,
    "culture/entertainment" => /\b(film|movie|album|celebrity|netflix|game)\w*/i,
    "culture/sports" => /\b(match|league|olympic|championship|goal|team)\w*/i
  }.freeze

  def guess(text, limit: 2)
    CUES.select { |_, pattern| pattern.match?(text.to_s) }.keys.first(limit)
  end

  def reset!
    @tree = nil
    @index = nil
  end
end
