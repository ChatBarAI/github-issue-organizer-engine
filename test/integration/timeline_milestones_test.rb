ENV["RAILS_ENV"] ||= "test"
require_relative "../dummy/config/environment"
require "rails/test_help"
require "minitest/mock"

class TimelineMilestonesTest < ActionDispatch::IntegrationTest
  setup do
    @milestone = { "id" => "101", "repository" => "example/one", "number" => 1,
      "title" => "Release <one>", "due_on" => "2026-11-21", "state" => "open",
      "url" => "https://github.com/example/one/milestone/1" }
    @timeline = Object.new
    { id: 42, to_param: "42", status: "current", draft?: false,
      starts_on: Date.new(2026, 11, 17), ends_on: nil, developer_ids: ["dev"],
      created_by: nil, created_by_id: 1, created_at: Time.current, original_created_at: Time.current,
      edited_by_id: nil, source_timeline_id: nil, items: [], unavailabilities: [],
      milestones: [@milestone], in_review_issues: [], blocked_issues: [], needs_effort_issues: []
    }.each { |name, value| @timeline.define_singleton_method(name) { value } }
    @saved = nil
    test = self
    @timeline.define_singleton_method(:update!) { |attributes| test.instance_variable_set(:@saved, attributes) }
    @client = Object.new
    available = [@milestone, @milestone.merge("id" => "102", "due_on" => nil)]
    @client.define_singleton_method(:milestones) { available }
    @client.define_singleton_method(:milestone_issues) { |**| [] }
  end

  test "picker groups repositories and hides undated milestones" do
    with_timeline { get "/admin/github-issues/timelines/42/milestones" }
    assert_response :success, request.env["action_dispatch.exception"]&.full_message
    assert_select "fieldset legend", text: "example/one"
    assert_select "input#milestone-101[checked]:not([disabled])"
    assert_select "input#milestone-102", count: 0
    assert_select "label[for='milestone-101']", text: /Release <one>/
    assert_select "p", text: /Undated/, count: 0
  end

  test "saving uses trusted GitHub data and accepts duplicate checkbox values" do
    with_timeline do
      patch "/admin/github-issues/timelines/42/update_milestones",
        params: { milestone_ids: ["", "101", "101"], milestones: [{ title: "Forged" }] }
    end
    assert_redirected_to "/admin/github-issues/timelines/42"
    saved = @saved.fetch(:milestones).sole
    assert_equal @milestone, saved.except("issues", "issues_checked_at")
    assert_equal [], saved.fetch("issues")
    assert saved.fetch("issues_checked_at").present?
  end

  test "unknown and undated selections leave saved milestones untouched" do
    ["unknown", "102"].each do |id|
      with_timeline do
        patch "/admin/github-issues/timelines/42/update_milestones", params: { milestone_ids: [id] }
      end
      assert_redirected_to "/admin/github-issues/timelines/42"
      assert_nil @saved
      assert_match /unavailable, undated/, flash[:alert]
    end
  end

  test "clear all does not require GitHub access" do
    @client.define_singleton_method(:milestones) { raise "Must not fetch" }
    with_timeline do
      patch "/admin/github-issues/timelines/42/update_milestones", params: { milestone_ids: [""] }
    end
    assert_redirected_to "/admin/github-issues/timelines/42"
    assert_equal({ milestones: [] }, @saved)
  end

  test "GitHub failure preserves selections and offers a retry" do
    @client.define_singleton_method(:milestones) do
      raise GithubIssueOrganizerEngine::Github::Client::RateLimitError, "Rate limit reached"
    end
    with_timeline do
      patch "/admin/github-issues/timelines/42/update_milestones", params: { milestone_ids: ["101"] }
    end
    assert_nil @saved
    assert_redirected_to "/admin/github-issues/timelines/42"
    assert_equal "Rate limit reached", flash[:alert]
  end

  test "saved markers render without GitHub even without scheduled issues" do
    @client.define_singleton_method(:milestones) { raise "Must not fetch" }
    with_timeline { get "/admin/github-issues/timelines/42" }
    assert_response :success, request.env["action_dispatch.exception"]&.full_message
    assert_select ".tif-milestone-label[style*='grid-column: 5'] button[data-open-milestone-details]", text: "◆ Release <one>"
    assert_select ".tif-milestone-line[style*='grid-column: 33']", count: 1
    assert_select ".tif-timeline-tick", count: 5
    assert_select ".tif-timeline-display-options input[data-compact-weekends-toggle]"
    assert_select ".tif-heading-links form + button[data-open-milestones]", text: "Milestones"
    assert_select "dialog#tif-milestones-dialog[aria-labelledby='tif-milestones-title']"
    assert_select "dialog [data-milestones-content]"
    assert_select "dialog fieldset", count: 0
    assert_select "a[href='https://github.com/example/one/milestone/1']"
  end

  test "picker excludes milestones older than one calendar month including saved markers" do
    boundary = @milestone.merge("id" => "103", "due_on" => "2026-10-17")
    old = @milestone.merge("id" => "104", "due_on" => "2026-10-16")
    @client.define_singleton_method(:milestones) { [boundary, old] }
    @timeline.define_singleton_method(:milestones) { [old] }
    with_timeline { get "/admin/github-issues/timelines/42/milestones" }
    assert_response :success
    assert_select "input#milestone-103"
    assert_select "input#milestone-104", count: 0
    with_timeline { get "/admin/github-issues/timelines/42" }
    assert_response :success
    assert_select ".tif-milestone-label", count: 0
    assert_select ".tif-timeline-chart", count: 0
    with_timeline do
      patch "/admin/github-issues/timelines/42/update_milestones", params: { milestone_ids: ["104"] }
    end
    assert_nil @saved
    assert_match /outside the display window/, flash[:alert]
  end

  test "saving from editor returns to editor" do
    with_timeline do
      patch "/admin/github-issues/timelines/42/update_milestones",
        params: { milestone_ids: ["101"], return_view: "edit" }
    end
    assert_redirected_to "/admin/github-issues/timelines/42/edit"
  end

  test "picker load failure returns an error without navigating away" do
    @client.define_singleton_method(:milestones) do
      raise GithubIssueOrganizerEngine::Github::Client::RateLimitError, "Rate limit reached"
    end
    with_timeline { get "/admin/github-issues/timelines/42/milestones" }
    assert_response :bad_gateway
    assert_equal "Rate limit reached", response.body
  end

  test "shared milestones have one switch and retain links to both repositories" do
    shared = @milestone.merge("id" => "201", "repository" => "example/two", "url" => "https://github.com/example/two/milestone/1")
    available = [shared, @milestone]
    @client.define_singleton_method(:milestones) { available }
    @timeline.define_singleton_method(:milestones) { [shared] }
    with_timeline { get "/admin/github-issues/timelines/42/milestones" }
    assert_response :success, request.env["action_dispatch.exception"]&.full_message
    assert_select "fieldset legend", text: "example/one · example/two"
    assert_select "input[type=checkbox]", count: 1
    assert_select "input#milestone-101[checked][role=switch]"
    assert_select ".tif-milestone-sources a", count: 2
    assert_select ".tif-milestone-sources a[href='https://github.com/example/two/milestone/1']"

    with_timeline do
      patch "/admin/github-issues/timelines/42/update_milestones", params: { milestone_ids: ["101"] }
    end
    assert_redirected_to "/admin/github-issues/timelines/42"
    assert_equal ["101", "201"], @saved.fetch(:milestones).map { |milestone| milestone.fetch("id") }

    saved = @saved.fetch(:milestones)
    @timeline.define_singleton_method(:milestones) { saved }
    with_timeline { get "/admin/github-issues/timelines/42" }
    assert_response :success
    assert_select ".tif-milestone-group", count: 1
    assert_select ".tif-milestone-group > button", text: "◆ Release <one>", count: 1
    assert_select ".tif-milestone-group > .tif-milestone-sources", count: 0
    assert_select ".tif-milestone-group > button[aria-haspopup='dialog'][aria-controls='tif-milestone-details-42-101']"
    assert_select "dialog#tif-milestone-details-42-101" do
      assert_select "h2", text: "Release <one>"
      assert_select ".tif-milestone-sources a", count: 2
      assert_select ".tif-milestone-details-summary nav[aria-label='Milestones on GitHub'] a.tif-milestone-github-link[target='_blank']", count: 2
      assert_select "a[href='https://github.com/example/two/milestone/1'][title='Open example/two milestone on GitHub']", text: /two/
    end
    assert_select ".tif-milestone-line", count: 1
  end

  test "same title on different dates remains independently selectable" do
    later = @milestone.merge("id" => "201", "repository" => "example/two", "due_on" => "2026-11-22")
    available = [@milestone, later]
    @client.define_singleton_method(:milestones) { available }
    with_timeline { get "/admin/github-issues/timelines/42/milestones" }
    assert_response :success
    assert_select "input[type=checkbox]", count: 2
    with_timeline do
      patch "/admin/github-issues/timelines/42/update_milestones", params: { milestone_ids: ["101"] }
    end
    assert_equal [@milestone], @saved.fetch(:milestones).map { |milestone| milestone.except("issues", "issues_checked_at") }
  end

  test "labels extend into free date columns while marker lines stay on their due dates" do
    milestones = [@milestone,
      @milestone.merge("id" => "201", "title" => "Next milestone", "due_on" => "2026-11-23"),
      @milestone.merge("id" => "301", "title" => "Last milestone", "due_on" => "2026-11-30")]
    @timeline.define_singleton_method(:milestones) { milestones }
    with_timeline { get "/admin/github-issues/timelines/42" }
    assert_response :success
    assert_select ".tif-milestone-label[style*='grid-column: 5 / span 2'] button[data-open-milestone-details]", text: "◆ Release <one>"
    assert_select ".tif-milestone-label[style*='grid-column: 7 / span 4'] button[data-open-milestone-details]", text: "◆ Next milestone"
    assert_select ".tif-milestone-label[style*='grid-column: 14 / span 1'] button[data-open-milestone-details]", text: "◆ Last milestone"
    assert_select ".tif-milestone-line[style*='grid-column: 33 / span 8']"
    assert_select ".tif-milestone-line[style*='grid-column: 49 / span 8']"
  end

  test "snapshot failure in a later repository does not overwrite saved selections" do
    shared = @milestone.merge("id" => "201", "repository" => "example/two")
    available = [@milestone, shared]
    @client.define_singleton_method(:milestones) { available }
    @client.define_singleton_method(:milestone_issues) do |repository:, **|
      raise GithubIssueOrganizerEngine::Github::Client::RateLimitError, "Rate limit reached" if repository == "example/two"
      []
    end
    with_timeline do
      patch "/admin/github-issues/timelines/42/update_milestones", params: { milestone_ids: ["101"] }
    end
    assert_nil @saved
    assert_equal "Rate limit reached", flash[:alert]
  end

  test "saved issue status colors grouped milestones and date lines" do
    shared = @milestone.merge("id" => "201", "repository" => "example/two")
    available = [@milestone, shared]
    @client.define_singleton_method(:milestones) { available }
    @client.define_singleton_method(:milestone_issues) do |repository:, **|
      [{ "number" => 7, "state" => "closed", "closed_on" => repository == "example/two" ? "2026-11-22" : "2026-11-20" }]
    end
    with_timeline do
      patch "/admin/github-issues/timelines/42/update_milestones", params: { milestone_ids: ["101"] }
    end
    saved = @saved.fetch(:milestones)
    @timeline.define_singleton_method(:milestones) { saved }
    with_timeline { get "/admin/github-issues/timelines/42" }
    assert_response :success
    assert_select ".tif-milestone-group.is-late > button[aria-label='Release <one>: Late']"
    assert_select "dialog#tif-milestone-details-42-101" do
      assert_select ".tif-milestone-status.is-late", text: "Late"
      assert_select ".tif-help", text: /GitHub issues checked/
      assert_select "h3", text: "Late issues (1)"
      assert_select "tbody tr", count: 2
      assert_select "td", text: "completed after the due date"
      assert_select "td", text: "Closed November 22, 2026"
      assert_select "a[href='https://github.com/example/two/issues/7']"
    end
    assert_select ".tif-milestone-line.is-late", count: 1
    saved.last["issues"].first["closed_on"] = "2026-11-21"
    with_timeline { get "/admin/github-issues/timelines/42" }
    assert_response :success
    assert_select ".tif-milestone-group.is-on_track > button[aria-label='Release <one>: Completed on time']"
    assert_select ".tif-milestone-line.is-on_track", count: 1
  end

  private

  def with_timeline
    scope = Object.new
    timeline = @timeline
    scope.define_singleton_method(:find) { |_| timeline }
    GithubIssueOrganizerEngine::Timeline.stub(:includes, scope) do
      GithubIssueOrganizerEngine::Github::Client.stub(:new, @client) { yield }
    end
  end
end
