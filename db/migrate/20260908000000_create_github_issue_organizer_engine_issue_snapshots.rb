class CreateGithubIssueOrganizerEngineIssueSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :github_issue_organizer_engine_issue_snapshots do |t|
      t.references :timeline,
        foreign_key: { to_table: :github_issue_organizer_engine_timelines, on_delete: :nullify },
        index: { unique: true, name: "idx_gio_issue_snapshots_timeline" }
      t.datetime :captured_at, null: false
      t.jsonb :repositories, null: false, default: []
      t.jsonb :priority_counts, null: false, default: {}
      t.timestamps
    end
    add_index :github_issue_organizer_engine_issue_snapshots, :captured_at
  end
end
