class AddMilestonesToGithubIssueOrganizerEngineTimelines < ActiveRecord::Migration[7.2]
  def change
    add_column :github_issue_organizer_engine_timelines, :milestones, :jsonb, null: false, default: []
  end
end
