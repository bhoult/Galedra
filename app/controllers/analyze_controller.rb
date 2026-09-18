# Analyze text (spec 06 §5): paste → source → proposals → claims → tasks.
class AnalyzeController < ApplicationController
  def new
  end

  def create
    text = params[:text].to_s.strip
    return redirect_to new_analyze_path, alert: "Paste some text first." if text.empty?

    payload = { "source_type" => params.fetch(:source_type, "OTHER"), "title" => params[:title].presence || "Pasted text #{Time.now.utc.iso8601}",
                "content" => text, "content_hash" => Crypto::Hashing.bytes(text) }
    result = Ui::Write.call(Current.user, "CREATE_SOURCE", payload)
    source = Source.find(Ledger::Ids.derive(result.contribution.id, "source"))
    Ui::Write.call(Current.user, "CREATE_SOURCE_LOCATION",
                   { "source_id" => source.id, "locator_type" => "CHAR_RANGE", "locator" => { "start" => 0, "end" => source.content_length },
                     "excerpt" => source.content, "excerpt_hash" => Crypto::Hashing.bytes(source.content) })
    redirect_to analyze_source_path(source)
  end
end
