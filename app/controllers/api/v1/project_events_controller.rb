# frozen_string_literal: true

# POST /api/v1/thread_count/project_events
#
# A service (Krater or another) reports the review outcome of a member's
# project. The outcome feeds the member's Thread Count (see ThreadCount).
#
# Auth: the service's API key in X-Api-Key, and the service's name must be in
# `project_event_services` in config/thread_count.yml.
#
# Params: sub (the member's Weave ID), project_ref (the service's own project
# ID), outcome (approved, exceptional, denied or blacklisted), and optional
# reason and evidence_url. A retry with the same project_ref and outcome is
# recorded once.
#
# Write only. The response never holds the score or a weight.
module Api
  module V1
    class ProjectEventsController < BaseController
      before_action :require_project_event_service

      def create
        user = User.find_by(p_id: params[:sub].to_s.upcase)
        return render json: { error: "not_found" }, status: :not_found unless user

        result = ::ThreadCount::Ledger.record_project_event(
          subject: user, service: current_service, outcome: params[:outcome], project_ref: params[:project_ref],
          reason: params[:reason], evidence_url: params[:evidence_url]
        )

        if result.success?
          render json: ThreadCountProjectEventSerializer.new(result.entry).as_json, status: :created
        else
          render json: { error: "invalid_request", error_description: result.errors.to_sentence }, status: :unprocessable_content
        end
      end

      private

      # The body ties a member to a project outcome, which is Thread Count
      # data. The usage row keeps only the path, the status and the timing.
      def log_bodies? = false

      def require_project_event_service
        return if ::ThreadCount.config.project_event_services.include?(current_service.name)

        render json: { error: "forbidden", error_description: "This service may not send project events" }, status: :forbidden
      end

    end
  end
end
