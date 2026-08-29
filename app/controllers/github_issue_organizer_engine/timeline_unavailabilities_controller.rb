module GithubIssueOrganizerEngine
  class TimelineUnavailabilitiesController < ApplicationController
    before_action :set_timeline

    def create
      unavailability = @timeline.unavailabilities.build(unavailability_params)

      @timeline.transaction do
        unavailability.save!
        TimelineRescheduler.new(
          timeline: @timeline,
          allow_reassignment: allow_reassignment?
        ).call
      end

      redirect_to edit_timeline_path(@timeline), notice: "Unavailable time added and timeline rescheduled."
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      redirect_to edit_timeline_path(@timeline), alert: error.message
    end

    def destroy
      unavailability = @timeline.unavailabilities.find(params[:id])

      @timeline.transaction do
        unavailability.destroy!
        TimelineRescheduler.new(timeline: @timeline).call
      end

      redirect_to edit_timeline_path(@timeline), notice: "Unavailable time removed and timeline rescheduled."
    end

    def update
      unavailability = @timeline.unavailabilities.find(params[:id])

      @timeline.transaction do
        unavailability.update!(unavailability_params)
        TimelineRescheduler.new(
          timeline: @timeline,
          allow_reassignment: allow_reassignment?
        ).call
      end

      redirect_to edit_timeline_path(@timeline), notice: "Unavailable time updated and timeline rescheduled."
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      redirect_to edit_timeline_path(@timeline), alert: error.message
    end

    private

    def set_timeline
      @timeline = Timeline.includes(:items, :unavailabilities).find(params[:timeline_id])
    end

    def unavailability_params
      params.require(:timeline_unavailability).permit(
        :allow_reassignment,
        :developer_id,
        :duration_amount,
        :duration_unit,
        :reason,
        :unavailable_at_time,
        :unavailable_on
      )
    end

    def allow_reassignment?
      value = params.dig(:timeline_unavailability, :allow_reassignment)
      return true if value.nil?

      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
