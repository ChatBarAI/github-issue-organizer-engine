require_relative "../../test_helper"

module GithubIssueOrganizerEngine
  class SearchQueryTest < Minitest::Test
    REPOSITORIES = [ "example/one", "example/two" ].freeze

    def test_builds_repository_specific_api_query
      query = SearchQuery.new(
        {
          "state" => "open",
          "label_match" => "all",
          "labels" => [ "Priority: High", "Effort: 1 day" ],
          "assignee" => "octocat",
          "sort" => "created-asc"
        },
        repositories: REPOSITORIES
      )

      assert_equal(
        'is:issue state:open assignee:octocat repo:example/one label:"Priority: High" label:"Effort: 1 day"',
        query.repository_query("example/one")
      )
      assert_includes query.web_query, "(repo:example/one OR repo:example/two)"
      assert_includes query.web_query, "sort:created-asc"
    end

    def test_rejects_invalid_usernames
      assert_raises(ArgumentError) do
        SearchQuery.new({ "assignee" => "not a user!" }, repositories: REPOSITORIES)
      end
    end

    def test_builds_pull_request_queries
      review_requested = SearchQuery.new(
        { "result_type" => "review_requested" },
        repositories: REPOSITORIES
      )
      pull_requests = SearchQuery.new(
        { "result_type" => "pull_requests" },
        repositories: REPOSITORIES
      )

      assert review_requested.web_query.start_with?("is:pr user-review-requested:@me state:open")
      assert pull_requests.web_query.start_with?("is:pr state:open")
    end

    def test_no_priority_removes_selected_priority_and_excludes_all_priority_labels
      query = SearchQuery.new(
        {
          "no_priority" => "1",
          "labels" => [ "Priority: High", "Team: Product" ]
        },
        repositories: REPOSITORIES
      )

      assert_includes query.web_query, 'label:"Team: Product"'
      refute_includes query.filters["labels"], "Priority: High"
      Scheduler::PRIORITY_RANKS.each_key do |label|
        assert_includes query.web_query, %(-label:"#{label}")
      end
    end
  end
end
