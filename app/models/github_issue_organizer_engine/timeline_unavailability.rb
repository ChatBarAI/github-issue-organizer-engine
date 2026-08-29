module GithubIssueOrganizerEngine
  class TimelineUnavailability < ApplicationRecord
    belongs_to :timeline,
      class_name: "GithubIssueOrganizerEngine::Timeline",
      inverse_of: :unavailabilities

    attr_accessor :allow_reassignment,
      :duration_amount,
      :duration_unit,
      :unavailable_at_time,
      :unavailable_on

    validates :developer_id, :starts_at, :ends_at, presence: true
    validates :duration_amount,
      numericality: { greater_than: 0 },
      if: :duration_input_supplied?
    validates :duration_unit,
      inclusion: { in: %w[hours days] },
      if: :duration_input_supplied?
    validate :developer_belongs_to_timeline
    validate :ends_after_it_starts

    before_validation :set_starts_at_from_parts
    before_validation :set_ends_at_from_duration

    private

    def duration_input_supplied?
      duration_amount.present? || duration_unit.present?
    end

    def set_starts_at_from_parts
      return if unavailable_on.blank? || unavailable_at_time.blank?

      self.starts_at = Time.zone.parse("#{unavailable_on} #{unavailable_at_time}")
    rescue ArgumentError
      self.starts_at = nil
    end

    def set_ends_at_from_duration
      return if starts_at.blank? || duration_amount.blank?

      multiplier = duration_unit == "days" ? 24 : 1
      hours = Float(duration_amount) * multiplier
      self.ends_at = starts_at + hours.hours if hours.positive?
    rescue ArgumentError, TypeError
      self.ends_at = nil
    end

    def developer_belongs_to_timeline
      return if timeline.blank? || developer_id.blank?
      return if timeline.developer_ids.include?(developer_id)

      errors.add(:developer_id, "is not part of this timeline")
    end

    def ends_after_it_starts
      return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

      errors.add(:ends_at, "must be after the start time")
    end
  end
end
