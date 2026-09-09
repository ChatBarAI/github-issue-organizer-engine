module GithubIssueOrganizerEngine
  module TimelinesHelper
    def issue_history_series(snapshots)
      maximum = [ snapshots.map(&:total).max.to_i, 1 ].max
      first_time = snapshots.first.captured_at.to_f
      duration = snapshots.last.captured_at.to_f - first_time
      priorities = [ "Total", *IssuePriorityCounts::PRIORITIES ]
      colors = %w[#3b82f6 #ef4444 #f97316 #f59e0b #10b981 #8b5cf6]
      cumulative = Array.new(snapshots.length, 0)

      priorities.zip(colors).map do |priority, color|
        points = snapshots.map do |snapshot|
          count = priority == "Total" ? snapshot.total : snapshot.priority_counts.fetch(priority, 0)
          x = duration.zero? ? 410 : 40 + 740 * (snapshot.captured_at.to_f - first_time) / duration
          { x: x.round(2), y: (170 - 150.0 * count / maximum).round(2), count: count,
            captured_at: snapshot.captured_at }
        end
        area = if priority != "Total"
          baseline = points.each_with_index.map do |point, index|
            { x: point[:x], y: (170 - 150.0 * cumulative[index] / maximum).round(2) }
          end
          top = points.each_with_index.map do |point, index|
            cumulative[index] += point[:count]
            { x: point[:x], y: (170 - 150.0 * cumulative[index] / maximum).round(2) }
          end
          { top: top, polygon: top + baseline.reverse }
        end
        { label: priority.delete_prefix("Priority: "), color: color, points: points, area: area }
      end
    end

    def issue_history_ticks(snapshots)
      return [] if snapshots.empty?

      first_time = snapshots.first.captured_at
      duration = snapshots.last.captured_at.to_f - first_time.to_f
      return [{ x: 410, captured_at: first_time, anchor: "middle" }] if duration.zero?

      5.times.map do |index|
        { x: 40 + 185 * index, captured_at: first_time + duration * index / 4.0,
          anchor: index.zero? ? "start" : index == 4 ? "end" : "middle" }
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
