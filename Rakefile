require "bundler/gem_tasks"
require "rake/testtask"

require "rails"
require "rails/test_unit/railtie"

require_relative "lib/github_issue_organizer_engine"

GithubIssueOrganizerEngine::Engine.load_tasks

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
  task.warning = false
end

task default: :test
