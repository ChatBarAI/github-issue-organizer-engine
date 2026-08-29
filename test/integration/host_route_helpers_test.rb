ENV["RAILS_ENV"] ||= "test"

require_relative "../dummy/config/environment"
require "rails/test_help"

class HostRouteHelpersTest < ActionDispatch::IntegrationTest
  setup do
    @original_repositories = GithubIssueOrganizerEngine.configuration.repositories
    GithubIssueOrganizerEngine.configuration.repositories = [ "example/one", "example/two" ]
  end

  teardown do
    GithubIssueOrganizerEngine.configuration.repositories = @original_repositories
  end

  test "authorized engine root renders host callback and layout routes" do
    get "/admin/github-issues"

    assert_response :success
    assert_select "a[href='/admin']", text: "Admin"
    assert_select "a[href='/users/sign_out']", text: "Sign out"
    assert_select "h1", text: "GitHub Issue Organizer"
    assert_select "a[href='/admin/github-issues/settings']", text: "Settings"
    assert_select "input#tif-developer-count", count: 0
    assert_select "input#tif-save-timeline", count: 0
    assert_select "label.tif-switch input#tif-inherit-unavailability[type='checkbox'][role='switch'][checked]", count: 1
    assert_select "label.tif-switch input#tif-inherit-manual-assignments[type='checkbox'][role='switch'][checked]", count: 1
    assert_select ".tif-inline-options label.tif-switch input[type='radio'][name='state'] + .tif-switch-control", count: 3
    assert_select ".tif-filter-options > fieldset:first-child > legend", text: "Label matching", count: 1
    assert_select "fieldset" do |fieldsets|
      label_matching = fieldsets.find { |fieldset| fieldset.at_css("legend")&.text&.strip == "Label matching" }

      assert label_matching
      assert_select label_matching, "label.tif-switch input[type='radio'][name='label_match'][value='all'][checked] + .tif-switch-control", count: 1
      assert_select label_matching, "label.tif-switch input[type='radio'][name='label_match'][value='any'] + .tif-switch-control", count: 1
    end
    assert_select "details.tif-repositories" do
      assert_select "summary", text: /Repositories searched \(2\)/
      assert_select "a[href='https://github.com/example/one'][target='_blank']", text: "example/one"
      assert_select "a[href='https://github.com/example/two'][target='_blank']", text: "example/two"
    end
    assert_select "fieldset.tif-label-group" do |groups|
      assert_equal "General", groups.last.at_css("legend").text.strip

      priority_group = groups.find { |group| group.at_css("legend")&.text&.strip == "Priority" }

      assert priority_group
      assert_select priority_group, "input[name='no_priority'][value='1'][data-no-priority-filter]", count: 1
      assert_select priority_group, "input[name='labels[]'][data-priority-filter]", count: 4
      assert_includes priority_group.text, "No priority"
    end
  end
end
