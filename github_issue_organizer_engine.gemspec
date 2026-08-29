require_relative "lib/github_issue_organizer_engine/version"

Gem::Specification.new do |spec|
  spec.name = "github_issue_organizer_engine"
  spec.version = GithubIssueOrganizerEngine::VERSION
  spec.authors = [ "ChatBar AI" ]
  spec.summary = "A mountable Rails engine for finding and scheduling GitHub issues."
  spec.description = "Searches configured GitHub repositories and creates draft timelines from priority and effort labels."
  spec.homepage = "https://github.com/ChatBarAI/github-issue-organizer-engine"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.chdir(__dir__) do
    Dir["{app,config,db,lib}/**/*", "README.md", "LICENSE.txt"]
  end
  spec.require_paths = [ "lib" ]

  spec.add_dependency "rails", ">= 7.2.2.1", "< 8.0"
end
