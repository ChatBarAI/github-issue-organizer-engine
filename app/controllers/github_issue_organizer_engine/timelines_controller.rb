module GithubIssueOrganizerEngine
  class TimelinesController < ApplicationController
    before_action :set_timeline, only: [ :show, :edit, :edit_copy, :update, :destroy, :make_current, :fill_gaps ]

    def index
      @timelines = Timeline.includes(:created_by, :edited_by, :source_timeline, :items)
        .order(Arel.sql(<<~SQL.squish), created_at: :desc)
          CASE github_issue_organizer_engine_timelines.status
          WHEN 'current' THEN 0
          WHEN 'draft' THEN 1
          ELSE 2 END
        SQL
      @timeline_rows = TimelineRevisionList.new(@timelines).call
      @issue_snapshots = IssueSnapshot.order(:captured_at, :id).to_a
    end

    def show
    end

    def edit
      @extra_past_days = params[:extra_past_days].to_i.clamp(0, 365)
      @unavailability = TimelineUnavailability.new
      @unavailability.unavailable_on = Date.current
      @unavailability.unavailable_at_time = "09:00"
    end

    def edit_copy
      copy = TimelineCopy.new(timeline: @timeline, editor_id: current_host_user_id).call
      redirect_to edit_timeline_path(copy), notice: "Draft edit created from timeline ##{@timeline.id}."
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      redirect_to timeline_path(@timeline), alert: error.message
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

    def fill_gaps
      TimelineGapFiller.new(timeline: @timeline, from_date: params[:from_date]).call
      redirect_to edit_timeline_path(@timeline, extra_past_days: params[:extra_past_days].to_i.clamp(0, 365)),
        notice: "Time gaps filled from #{params[:from_date]}."
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      redirect_to edit_timeline_path(@timeline), alert: error.message
    end

    def destroy
      @timeline.destroy!
      redirect_to timelines_path, notice: "Timeline deleted."
    end

    def destroy_drafts
      deleted_count = Timeline.draft.destroy_all.size
      noun = deleted_count == 1 ? "draft timeline" : "draft timelines"
      redirect_to timelines_path, notice: "#{deleted_count} #{noun} deleted."
    end

    def make_current
      @timeline.make_current!(github_client: github_client, repositories: configured_repositories)
      redirect_to timelines_path, notice: "Timeline ##{@timeline.id} is now current."
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ArgumentError, Github::Client::Error => error
      redirect_to timelines_path, alert: error.message
    end

    private

    def set_timeline
      @timeline = Timeline.includes(:items, :unavailabilities, :created_by, :edited_by, :source_timeline).find(params[:id])
    end

    def timeline_params
      params.require(:timeline).permit(:starts_on)
    end
  end
end
