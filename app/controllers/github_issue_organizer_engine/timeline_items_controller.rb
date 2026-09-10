module GithubIssueOrganizerEngine
  class TimelineItemsController < ApplicationController
    before_action :set_timeline

    def update
      item = @timeline.items.find(params[:id])
      original_schedule = schedule_snapshot
      TimelineItemMover.new(
        timeline: @timeline,
        item: item,
        developer_id: item_params.fetch(:developer_id),
        before_item_id: item_params[:before_item_id],
        starts_at: item_params[:starts_at]
      ).call

      @timeline.items.reload
      changed = original_schedule != schedule_snapshot
      render json: {
        changed: changed,
        message: changed ? "Issue moved." : "Already at the earliest available time in this position. Drop before or after another issue to reorder.",
        timeline_url: edit_timeline_path(@timeline)
      }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => error
      render json: { error: error.message }, status: :unprocessable_entity
    end

    def destroy
      item = @timeline.items.find(params[:id])
      unless item.starts_on < @timeline.starts_on
        raise ArgumentError, "Only issues with past work can be removed here"
      end

      item.destroy!
      redirect_to edit_timeline_path(@timeline, extra_past_days: params[:extra_past_days].to_i.clamp(0, 365)),
        notice: "Issue removed from this timeline."
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotDestroyed, ArgumentError => error
      redirect_to edit_timeline_path(@timeline), alert: error.message
    end

    private

    def schedule_snapshot
      @timeline.items.map do |entry|
        entry.attributes.slice("id", "developer_id", "starts_on", "ends_on", "work_segments")
      end.sort_by { |entry| entry.fetch("id") }
    end

    def set_timeline
      @timeline = Timeline.includes(:items, :unavailabilities).find(params[:timeline_id])
    end

    def item_params
      params.require(:timeline_item).permit(:developer_id, :before_item_id, :starts_at)
    end
  end
end
