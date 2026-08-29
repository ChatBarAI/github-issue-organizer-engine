class CreateGithubIssueOrganizerEngine < ActiveRecord::Migration[7.2]
  def change
    create_table :github_issue_organizer_engine_github_identities do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.bigint :github_user_id, null: false
      t.string :github_login, null: false
      t.datetime :verified_at, null: false

      t.timestamps
    end

    add_index :github_issue_organizer_engine_github_identities, :github_user_id, unique: true
    add_index :github_issue_organizer_engine_github_identities,
      "lower(github_login)",
      unique: true,
      name: "idx_github_issue_organizer_engine_github_identities_login"

    create_table :github_issue_organizer_engine_timelines do |t|
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.date :starts_on, null: false
      t.jsonb :query, null: false, default: {}
      t.integer :developer_count, null: false, default: 1
      t.jsonb :developer_ids, null: false, default: []
      t.jsonb :in_review_issues, null: false, default: []
      t.jsonb :blocked_issues, null: false, default: []
      t.string :status, null: false, default: "draft"

      t.timestamps
    end

    add_check_constraint :github_issue_organizer_engine_timelines,
      "status IN ('draft', 'current', 'obsolete')",
      name: "github_issue_organizer_engine_timelines_status"
    add_index :github_issue_organizer_engine_timelines,
      :status,
      unique: true,
      where: "status = 'current'",
      name: "idx_github_issue_organizer_engine_one_current_timeline"

    create_table :github_issue_organizer_engine_timeline_items do |t|
      t.references :timeline,
        null: false,
        foreign_key: { to_table: :github_issue_organizer_engine_timelines }
      t.bigint :github_issue_id
      t.string :repository, null: false
      t.integer :issue_number, null: false
      t.string :title, null: false
      t.string :url, null: false
      t.string :priority, null: false
      t.integer :effort_hours, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :position, null: false
      t.integer :developer_position, null: false, default: 1
      t.string :developer_id, null: false
      t.jsonb :work_segments, null: false, default: []
      t.string :github_assignee_id
      t.string :github_assignee_login
      t.boolean :manually_assigned, null: false, default: false

      t.timestamps
    end

    add_index :github_issue_organizer_engine_timeline_items,
      [ :timeline_id, :position ],
      unique: true,
      name: "idx_github_issue_organizer_engine_timeline_items_position"

    create_table :github_issue_organizer_engine_settings do |t|
      t.jsonb :repositories, null: false, default: []
      t.jsonb :developer_ids, null: false, default: []

      t.timestamps
    end

    create_table :github_issue_organizer_engine_timeline_unavailabilities do |t|
      t.references :timeline,
        null: false,
        foreign_key: { to_table: :github_issue_organizer_engine_timelines },
        index: { name: "idx_github_issue_organizer_engine_unavailability_timeline" }
      t.string :developer_id, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.text :reason

      t.timestamps
    end

    add_index :github_issue_organizer_engine_timeline_unavailabilities,
      [ :timeline_id, :developer_id, :starts_at ],
      name: "idx_github_issue_organizer_engine_unavailability_lookup"
  end
end
