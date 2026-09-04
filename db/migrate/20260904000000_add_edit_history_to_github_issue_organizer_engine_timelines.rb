class AddEditHistoryToGithubIssueOrganizerEngineTimelines < ActiveRecord::Migration[7.2]
  def change
    add_reference :github_issue_organizer_engine_timelines,
      :source_timeline,
      foreign_key: { to_table: :github_issue_organizer_engine_timelines, on_delete: :nullify },
      index: { name: "idx_github_issue_organizer_engine_timelines_source" }
    add_reference :github_issue_organizer_engine_timelines,
      :edited_by,
      foreign_key: { to_table: :users },
      index: { name: "idx_github_issue_organizer_engine_timelines_editor" }
    add_column :github_issue_organizer_engine_timelines,
      :needs_effort_issues,
      :jsonb,
      null: false,
      default: []
  end
end
