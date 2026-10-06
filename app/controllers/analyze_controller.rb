# Analyze text (spec 06 §5, Stage 46): paste → source → extraction tasks; the
# claims come from an assistant or a person, never from the server.
class AnalyzeController < ApplicationController
  def new
  end

  def create
    text = params[:text].to_s.strip
    return redirect_to new_analyze_path, alert: "Paste some text first." if text.empty?

    source = Sources::Paste.call(Current.user, text: text, title: params[:title], source_type: params.fetch(:source_type, "OTHER"))
    redirect_to analyze_source_path(source)
  rescue Sources::Paste::TooLong => e
    @text = text
    @too_long = e.words
    render :new, status: :unprocessable_content
  end
end
