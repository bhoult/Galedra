# frozen_string_literal: true

module Claims
  # The second pass of search_claims (Stage 42 §8), when no claim holds every
  # word of the query.
  #
  # plainto_tsquery joins its terms with AND, so one word a claim does not use
  # empties the result: "Trump ban CNN Politico MS NOW White House press" found
  # 1 of the 5 claims about that event, because none says "ban" or "press",
  # while three of its words found all of them (bug report 91bee9ac). This ranks
  # by how many of the query's terms a claim holds, and keeps only those holding
  # at least half — so a long query still finds its subject, and a query that
  # shares one common word with a claim does not pretend to have found it.
  module Search
    module_function

    def most_terms(scope, query, limit:)
      lexemes = ActiveRecord::Base.connection.select_value(ActiveRecord::Base.sanitize_sql([ "SELECT plainto_tsquery('english', ?)::text", query ])).to_s
                                  .scan(/'([^']+)'/).flatten.uniq.grep(/\A[[:alnum:]_-]+\z/)
      return Claim.none if lexemes.size < 2

      floor = lexemes.size <= 2 ? lexemes.size : (lexemes.size / 2.0).ceil
      vector = "to_tsvector('english', canonical_text)"
      hits = lexemes.map { |l| ActiveRecord::Base.sanitize_sql([ "(#{vector} @@ ?::tsquery)::int", "'#{l}'" ]) }.join(" + ")
      any = ActiveRecord::Base.sanitize_sql([ "#{vector} @@ ?::tsquery", lexemes.map { |l| "'#{l}'" }.join(" | ") ])
      scope.where(any).where("(#{hits}) >= ?", floor)
           .reorder(Arel.sql("(#{hits}) DESC, created_seq DESC")).limit(limit)
    end
  end
end
