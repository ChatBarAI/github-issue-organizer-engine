module GithubIssueOrganizerEngine
  class TimelinesController < ApplicationController
    before_action :set_timeline, only: [ :show, :edit, :edit_copy, :update, :destroy, :make_current, :fill_gaps, :milestones, :update_milestones ]

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

    def current
      @timeline = Timeline.current.includes(:items, :unavailabilities, :created_by, :edited_by, :source_timeline).first
      render :show if @timeline
    end

    def show
    end

    def edit
      @extra_past_days = params[:extra_past_days].to_i.clamp(0, 365)
      @unavailability = TimelineUnavailability.new
      @unavailability.unavailable_on = Date.current
      @unavailability.unavailable_at_time = "09:00"
    end

    def milestones
      @available_milestones = available_milestones
      render partial: "milestone_picker"
    rescue Github::Client::Error, ArgumentError => error
      render plain: error.message, status: :bad_gateway
    end

    def update_milestones
      ids = Array(params.permit(milestone_ids: [])[:milestone_ids]).reject(&:blank?).uniq
      available = ids.empty? ? [] : available_milestones
      selected = available.select { |milestone| ids.include?(milestone.fetch("id")) }
      if selected.size != ids.size || selected.any? { |milestone| milestone["due_on"].blank? }
        raise ArgumentError, "Some selected milestones are unavailable, undated, or outside the display window. Reopen Milestones and try again."
      end

      selected = MilestoneGroups.call(available)
        .select { |group| group.any? { |milestone| ids.include?(milestone.fetch("id")) } }.flatten(1)
      unless selected.empty?
        client = github_client
        checked_at = Time.current.iso8601
        selected = selected.map do |milestone|
          milestone.merge(
            "issues" => client.milestone_issues(repository: milestone.fetch("repository"), milestone_number: milestone.fetch("number")),
            "issues_checked_at" => checked_at
          )
        end
      end
      @timeline.update!(milestones: selected)
      redirect_to milestone_return_path, notice: "Milestones saved."
    rescue Github::Client::Error, ActiveRecord::RecordInvalid, ArgumentError => error
      redirect_to milestone_return_path, alert: error.message
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

    def available_milestones
      MilestoneWindow.call(github_client.milestones, starts_on: @timeline.starts_on)
    end

    def milestone_return_path
      params[:return_view] == "edit" ? edit_timeline_path(@timeline) : timeline_path(@timeline)
    end

    def timeline_params
      params.require(:timeline).permit(:starts_on)
    end
  end
end
