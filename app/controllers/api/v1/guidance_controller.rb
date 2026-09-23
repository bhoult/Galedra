# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/guidance (Stage 31): the operational rules for an assistant
    # working in Galedra, served live.
    #
    # An assistant on MCP gets these attached to every tool result and never
    # needs this endpoint. It exists for the hosts that speak the REST API
    # instead, where there is nowhere else for a rule to travel: they read it at
    # the start of a Galedra task, and so pick up a change without anyone
    # reinstalling anything.
    class GuidanceController < BaseController
      def show
        topic = params[:topic].presence&.to_sym
        if topic && !Guidance::TOPICS.include?(topic)
          return render json: { error: "UNKNOWN_TOPIC", topics: Guidance::TOPICS }, status: :not_found
        end

        render json: { version: Guidance::VERSION, purpose: Guidance::PURPOSE,
                       topics: topic ? { topic => Guidance.for(topic) } : Guidance.all }
      end

      # GET /api/v1/connector (Stage 42 §4): the text to paste into a client's
      # connector form, the one place a directory-style client looks before it
      # fetches any tool.
      def connector
        render json: { version: Guidance::VERSION, description: Guidance::CONNECTOR,
                       how: "Paste description into the description field of your client's connector form. It is frozen once pasted; the rules it names are also served live on every tool result." }
      end
    end
  end
end
