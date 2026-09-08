module GithubIssueOrganizerEngine
  module TimelinesHelper
    def issue_history_series(snapshots)
      maximum = [ snapshots.map(&:total).max.to_i, 1 ].max
      first_time = snapshots.first.captured_at.to_f
      duration = snapshots.last.captured_at.to_f - first_time
      priorities = [ "Total", *IssuePriorityCounts::PRIORITIES ]
      colors = %w[#0969da #cf222e #bc4c00 #9a6700 #1a7f37 #6e7781]

      priorities.zip(colors).map do |priority, color|
        points = snapshots.map do |snapshot|
          count = priority == "Total" ? snapshot.total : snapshot.priority_counts.fetch(priority, 0)
          x = duration.zero? ? 440 : 60 + 760 * (snapshot.captured_at.to_f - first_time) / duration
          { x: x.round(2), y: (260 - 220.0 * count / maximum).round(2), count: count,
            captured_at: snapshot.captured_at }
        end
        { label: priority.delete_prefix("Priority: "), color: color, points: points }
      end
    end

    def compact_date_range(starts_on, ends_on)
      return I18n.l(starts_on, format: "%B %-d, %Y") if starts_on == ends_on

      if starts_on.year == ends_on.year && starts_on.month == ends_on.month
        "#{I18n.l(starts_on, format: "%B %-d")}–#{I18n.l(ends_on, format: "%-d, %Y")}"
      elsif starts_on.year == ends_on.year
        "#{I18n.l(starts_on, format: "%B %-d")} – #{I18n.l(ends_on, format: "%B %-d, %Y")}"
      else
        "#{I18n.l(starts_on, format: "%B %-d, %Y")} – #{I18n.l(ends_on, format: "%B %-d, %Y")}"
      end
    end

    def timeline_user_name(user, user_id)
      user.try(:fullname).presence || user.try(:email).presence || "User ##{user_id}"
    end

    def timeline_status_label(timeline)
      return "Draft edit" if timeline.draft? && timeline.source_timeline_id.present?

      timeline.status.titleize
    end
  end
end
