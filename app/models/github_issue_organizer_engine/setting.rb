module GithubIssueOrganizerEngine
  class Setting < ApplicationRecord
    REPOSITORY_FORMAT = %r{\A[a-z\d_.-]+/[a-z\d_.-]+\z}i

    before_validation :normalize_values

    validate :repositories_are_present
    validate :repositories_use_full_names
    validate :developer_ids_are_present
    validate :developer_ids_are_limited

    def self.current
      first_or_initialize(
        repositories: GithubIssueOrganizerEngine.configuration.repositories,
        developer_ids: []
      )
    end

    def self.normalize_list(value)
      seen = {}
      Array(value).filter_map do |item|
        name = item.to_s.strip
        key = name.downcase
        next if name.empty? || seen[key]

        seen[key] = true
        name
      end
    end

    def self.normalize_repository_names(value)
      normalize_list(value)
    end

    def self.normalize_developer_ids(value)
      normalize_list(value)
    end

    def repositories_text
      Array(repositories).join("\n")
    end

    def repositories_text=(value)
      self.repositories = self.class.normalize_repository_names(
        value.to_s.split(/[\r\n,]+/)
      )
    end

    def developer_ids_text
      Array(developer_ids).join("\n")
    end

    def developer_ids_text=(value)
      self.developer_ids = self.class.normalize_developer_ids(
        value.to_s.split(/[\r\n,]+/)
      )
    end

    private

    def normalize_values
      self.repositories = self.class.normalize_repository_names(repositories)
      self.developer_ids = self.class.normalize_developer_ids(developer_ids)
    end

    def repositories_are_present
      errors.add(:repositories, "must include at least one repository") if repositories.empty?
    end

    def repositories_use_full_names
      invalid = repositories.reject { |repository| repository.match?(REPOSITORY_FORMAT) }
      return if invalid.empty?

      errors.add(
        :repositories,
        "must use owner/repository format (invalid: #{invalid.join(', ')})"
      )
    end

    def developer_ids_are_present
      errors.add(:developer_ids, "must include at least one developer ID") if developer_ids.empty?
    end

    def developer_ids_are_limited
      errors.add(:developer_ids, "cannot include more than 100 developer IDs") if developer_ids.size > 100
    end
  end
end
