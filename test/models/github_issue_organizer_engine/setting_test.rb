require_relative "../../test_helper"
require "active_record"
require_relative "../../../app/models/github_issue_organizer_engine/application_record"
require_relative "../../../app/models/github_issue_organizer_engine/setting"

module GithubIssueOrganizerEngine
  class SettingTest < Minitest::Test
    def test_normalizes_repository_input
      repositories = Setting.normalize_repository_names(
        [ " Example/One", "example/two", "example/one " ]
      )

      assert_equal [ "Example/One", "example/two" ], repositories
    end

    def test_normalizes_developer_ids
      developer_ids = Setting.normalize_developer_ids(
        [ " developer-123", "developer-456", "DEVELOPER-123 " ]
      )

      assert_equal [ "developer-123", "developer-456" ], developer_ids
    end
  end
end
