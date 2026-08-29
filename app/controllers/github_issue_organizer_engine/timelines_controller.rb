module GithubIssueOrganizerEngine
  class TimelinesController < ApplicationController
    before_action :set_timeline, only: [ :show, :edit, :update, :destroy, :make_current ]

    def index
      @timelines = Timeline.includes(:created_by, :items)
        .order(Arel.sql(<<~SQL.squish), created_at: :desc)
          CASE github_issue_organizer_engine_timelines.status
          WHEN 'current' THEN 0
          WHEN 'draft' THEN 1
          ELSE 2 END
        SQL
    end

    def show
    end

    def edit
      @unavailability = TimelineUnavailability.new
      @unavailability.unavailable_on = Date.current
      @unavailability.unavailable_at_time = "09:00"
    end

    def update
      TimelineRescheduler.new(
        timeline: @timeline,
        starts_on: timeline_params.fetch(:starts_on)
      ).call
      redirect_to edit_timeline_path(@timeline), notice: "Timeline updated and rescheduled."
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      redirect_to edit_timeline_path(@timeline), alert: error.message
    end

    def destroy
      @timeline.destroy!
      redirect_to timelines_path, notice: "Timeline deleted."
    end

    def make_current
      @timeline.make_current!
      redirect_to timelines_path, notice: "Timeline ##{@timeline.id} is now current."
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ArgumentError => error
      redirect_to timelines_path, alert: error.message
    end

    private

    def set_timeline
      @timeline = Timeline.includes(:items, :unavailabilities, :created_by).find(params[:id])
    end

    def timeline_params
      params.require(:timeline).permit(:starts_on)
    end
  end
end
