(() => {
  const compactWeekendsStorageKey = "github-issue-organizer-engine:compact-weekends";

  const formatDate = value => new Intl.DateTimeFormat(undefined, {
    day: "numeric",
    month: "short",
    year: "numeric"
  }).format(new Date(`${value}T00:00:00`));

  const localDateValue = date => {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  };

  const parseDate = value => new Date(`${value}T00:00:00`);

  const daysBetween = (start, finish) =>
    Math.round((parseDate(finish) - parseDate(start)) / 86400000);

  const dateRange = (start, finish) => {
    const dates = [];
    const cursor = parseDate(start);
    const last = parseDate(finish);
    while (cursor <= last) {
      dates.push(localDateValue(cursor));
      cursor.setDate(cursor.getDate() + 1);
    }
    return dates;
  };

  const compactWeekendsPreference = () => {
    try {
      return window.localStorage.getItem(compactWeekendsStorageKey) === "true";
    } catch (_error) {
      return false;
    }
  };

  const setCompactWeekendsPreference = value => {
    try {
      window.localStorage.setItem(compactWeekendsStorageKey, String(value));
    } catch (_error) {
      // The switch still works when storage is unavailable.
    }
  };

  const initializeCompactWeekendToggles = (container = document) => {
    const toggles = [
      ...(container.matches?.("[data-compact-weekends-toggle]") ? [ container ] : []),
      ...container.querySelectorAll("[data-compact-weekends-toggle]")
    ];
    toggles.forEach(toggle => {
      if (toggle.dataset.initialized === "true") return;

      const view = toggle.dataset.timelineChartTarget
        ? document.getElementById(toggle.dataset.timelineChartTarget)
        : toggle.closest("[data-timeline-chart-view]");
      if (!view) return;

      toggle.dataset.initialized = "true";
      toggle.checked = compactWeekendsPreference();
      view.classList.toggle("is-compact-weekends", toggle.checked);
      toggle.addEventListener("change", () => {
        view.classList.toggle("is-compact-weekends", toggle.checked);
        setCompactWeekendsPreference(toggle.checked);
      });
    });
  };

  const renderTimelineChart = (items, developerIds, timelineStartsOn) => {
    const firstScheduledDate = items.map(item => item.starts_on).sort()[0];
    const firstDate = [timelineStartsOn, firstScheduledDate].filter(Boolean).sort()[0];
    const lastDate = items.map(item => item.ends_on).sort().at(-1);
    const dates = dateRange(firstDate, lastDate);
    const view = document.createElement("div");
    view.className = "tif-timeline-chart-view";
    view.dataset.timelineChartView = "";

    const options = document.createElement("div");
    options.className = "tif-timeline-view-options";
    const switchLabel = document.createElement("label");
    switchLabel.className = "tif-switch";
    switchLabel.title = "Make Saturday and Sunday narrower to show more days";
    const switchInput = document.createElement("input");
    switchInput.type = "checkbox";
    switchInput.setAttribute("role", "switch");
    switchInput.dataset.compactWeekendsToggle = "";
    const switchTrack = document.createElement("span");
    switchTrack.className = "tif-switch-control";
    switchTrack.setAttribute("aria-hidden", "true");
    const switchText = document.createElement("span");
    switchText.className = "tif-switch-label";
    switchText.textContent = "Compact weekends";
    switchLabel.append(switchInput, switchTrack, switchText);
    options.append(switchLabel);
    view.append(options);

    const scroll = document.createElement("div");
    scroll.className = "tif-timeline-chart-scroll";
    scroll.setAttribute("role", "region");
    scroll.setAttribute("aria-label", "Issue schedule by developer and date");
    scroll.tabIndex = 0;

    const chart = document.createElement("div");
    chart.className = "tif-timeline-chart";
    chart.style.setProperty("--tif-timeline-days", dates.length);
    const compactDayColumns = dates.map(value => [ 0, 6 ].includes(parseDate(value).getDay()) ? "32px" : "112px");
    const compactContentWidth = compactDayColumns.reduce((total, width) => total + Number.parseInt(width, 10), 0);
    chart.style.setProperty("--tif-timeline-compact-content-width", `${compactContentWidth}px`);
    chart.style.setProperty("--tif-timeline-compact-day-columns", compactDayColumns.join(" "));
    chart.style.setProperty("--tif-timeline-compact-track-columns", compactDayColumns.join(" "));

    const corner = document.createElement("div");
    corner.className = "tif-timeline-corner";
    corner.textContent = "Developer ID";
    chart.append(corner);

    const axis = document.createElement("div");
    axis.className = "tif-timeline-axis";
    dates.forEach(value => {
      const date = parseDate(value);
      const tick = document.createElement("div");
      tick.className = "tif-timeline-tick";
      if (date.getDay() === 0 || date.getDay() === 6) {
        tick.classList.add("is-weekend");
        tick.dataset.compactLabel = date.getDay() === 6 ? "Sa" : "Su";
      }
      tick.textContent = new Intl.DateTimeFormat(undefined, {
        weekday: "short",
        day: "numeric",
        month: "short"
      }).format(date);
      tick.title = formatDate(value);
      axis.append(tick);
    });
    chart.append(axis);

    developerIds.forEach(developerId => {
      const developerItems = items
        .filter(item => item.developer_id === developerId)
        .sort((left, right) => left.starts_on.localeCompare(right.starts_on) || left.position - right.position);
      const laneEnds = [];
      const placements = developerItems.map(item => {
        const start = daysBetween(firstDate, item.starts_on);
        const end = daysBetween(firstDate, item.ends_on);
        let lane = laneEnds.findIndex(laneEnd => laneEnd < start);
        if (lane === -1) lane = laneEnds.length;
        laneEnds[lane] = end;
        return { item, start, end, lane };
      });
      const laneCount = Math.max(laneEnds.length, 1);

      const label = document.createElement("div");
      label.className = "tif-timeline-developer";
      label.textContent = developerId;
      chart.append(label);

      const track = document.createElement("div");
      track.className = "tif-timeline-track";
      track.style.setProperty("--tif-timeline-lanes", laneCount);
      dates.forEach((value, index) => {
        const date = parseDate(value);
        const dayColumn = document.createElement("span");
        dayColumn.className = "tif-timeline-day-column";
        if (date.getDay() === 0 || date.getDay() === 6) dayColumn.classList.add("is-weekend");
        dayColumn.setAttribute("aria-hidden", "true");
        dayColumn.style.gridColumn = `${index + 1}`;
        track.append(dayColumn);
      });
      placements.forEach(({ item, start, end, lane }) => {
        const task = document.createElement("article");
        task.className = "tif-timeline-task";
        task.style.gridColumn = `${start + 1} / ${end + 2}`;
        task.style.gridRow = `${lane + 1}`;
        task.title = `${formatDate(item.starts_on)} – ${formatDate(item.ends_on)}`;

        const link = document.createElement("a");
        link.href = item.url;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.textContent = item.title;
        link.title = `${item.repository}#${item.issue_number} · ${item.title}`;
        task.append(link);

        if (item.github_assignee_matches) {
          const marker = document.createElement("span");
          marker.className = "tif-github-assignee-marker";
          marker.textContent = "✓";
          marker.title = "Timeline developer matches the first GitHub assignee";
          marker.setAttribute("aria-label", marker.title);
          task.append(marker);
        }

        if (item.manually_assigned) {
          const marker = document.createElement("span");
          marker.className = "tif-manual-assignment-marker";
          marker.textContent = "M";
          marker.title = "Manually assigned in this timeline";
          marker.setAttribute("aria-label", marker.title);
          task.append(marker);
        }

        const meta = document.createElement("span");
        meta.textContent = `${item.repository}#${item.issue_number} · ${item.priority} · ${item.effort}`;
        task.append(meta);
        track.append(task);
      });
      chart.append(track);
    });

    scroll.append(chart);
    view.append(scroll);
    initializeCompactWeekendToggles(view);
    return view;
  };

  const appendIssue = (list, item, dateText, metaText) => {
    const row = document.createElement("li");
    row.className = "tif-timeline-item";

    const dates = document.createElement("div");
    dates.className = "tif-timeline-dates";
    dates.textContent = dateText;
    row.append(dates);

    const details = document.createElement("div");
    details.className = "tif-timeline-issue";

    const link = document.createElement("a");
    link.href = item.url;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    const repositoryName = item.repository.split("/").pop();
    link.textContent = `${repositoryName}#${item.issue_number} · ${item.title}`;
    details.append(link);

    const meta = document.createElement("div");
    meta.className = "tif-timeline-meta";
    meta.textContent = metaText;
    details.append(meta);
    row.append(details);
    list.append(row);
  };

  const renderInformationalIssues = (container, groups) => {
    const items = groups.flatMap(group => group.items.map(item => ({ item, options: group.options })));
    if (!items.length) return;

    const section = document.createElement("details");
    section.className = "tif-informational-issues tif-compact-issue-cards";
    const heading = document.createElement("summary");
    heading.textContent = `Not Scheduled (${items.length})`;
    section.append(heading);

    const help = document.createElement("p");
    help.className = "tif-help";
    help.textContent = "In-review and blocked issues are shown for visibility and do not consume timeline capacity.";
    section.append(help);

    const grid = document.createElement("div");
    grid.className = "tif-issue-card-grid";
    items.forEach(({ item, options }) => {
      const assignee = item.github_assignee_login || item.github_assignee_id;
      const priorityName = item.priority?.replace(/^Priority:\s*/, "");
      const priorityClass = priorityName ? ` tif-has-priority is-priority-${priorityName.toLowerCase()}` : "";
      const metadata = [item.effort, assignee && `@${assignee}`].filter(Boolean);
      const card = document.createElement("article");
      card.className = `tif-issue-card tif-informational-card ${options.className}${priorityClass}`;

      const badge = document.createElement("div");
      badge.className = "tif-issue-card-position tif-informational-card-badge";
      badge.textContent = options.badge;
      badge.setAttribute("aria-label", options.status);
      card.append(badge);

      const content = document.createElement("div");
      content.className = "tif-issue-card-content";
      const title = document.createElement("h3");
      const link = document.createElement("a");
      link.href = item.url;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.title = `${item.repository}#${item.issue_number}`;
      link.textContent = item.title;
      title.append(link);
      content.append(title);

      const status = document.createElement("p");
      status.textContent = item.status_conflict ? `${options.status} · conflicting status labels` : options.status;
      content.append(status);

      if (priorityName || metadata.length) {
        const meta = document.createElement("p");
        if (priorityName) {
          const priority = document.createElement("span");
          priority.className = "tif-priority-indicator";
          priority.setAttribute("aria-label", item.priority);

          const priorityDot = document.createElement("span");
          priorityDot.className = "tif-priority-indicator-dot";
          priorityDot.setAttribute("aria-hidden", "true");
          priority.append(priorityDot, priorityName);
          meta.append(priority);
        }
        if (priorityName && metadata.length) meta.append(" · ");
        if (metadata.length) meta.append(metadata.join(" · "));
        content.append(meta);
      }

      card.append(content);
      grid.append(card);
    });
    section.append(grid);
    container.append(section);
  };

  const renderTimeline = (container, payload) => {
    container.replaceChildren();

    const heading = document.createElement("h3");
    heading.textContent = "Proposed order";
    container.append(heading);

    const summary = document.createElement("p");
    summary.className = "tif-timeline-summary";
    const summaryParts = [
      `${payload.scheduled.length} scheduled`,
      `${payload.total_hours / 8} developer-days across ${payload.developer_ids.length} ${payload.developer_ids.length === 1 ? "developer" : "developers"}`,
      ...(payload.ends_on ? [`ends ${formatDate(payload.ends_on)}`] : []),
      ...(payload.inherited_unavailability_count ? [
        `${payload.inherited_unavailability_count} unavailable ${payload.inherited_unavailability_count === 1 ? "period" : "periods"} inherited`
      ] : []),
      ...(payload.inherited_manual_assignment_count ? [
        `${payload.inherited_manual_assignment_count} manual ${payload.inherited_manual_assignment_count === 1 ? "assignment" : "assignments"} kept`
      ] : []),
      `${payload.needs_labels.length} need labels`
    ];
    if (payload.incomplete_results) summaryParts.push("GitHub reported incomplete results");
    if (payload.timeline_id) summaryParts.push(`saved as draft #${payload.timeline_id}`);
    summary.textContent = summaryParts.join(" · ");
    container.append(summary);

    if (payload.scheduled.length) {
      container.append(renderTimelineChart(payload.scheduled, payload.developer_ids, payload.starts_on));
    } else {
      const empty = document.createElement("p");
      empty.className = "tif-help";
      empty.textContent = "No matching issues have both a priority and an effort label.";
      container.append(empty);
    }

    renderInformationalIssues(container, [
      {
        items: payload.in_review || [],
        options: { className: "is-review", status: "In review", badge: "R" }
      },
      {
        items: payload.blocked || [],
        options: { className: "is-blocked", status: "Blocked", badge: "!" }
      }
    ]);

    if (payload.needs_labels.length) {
      const notes = document.createElement("details");
      notes.className = "tif-timeline-notes";
      const notesSummary = document.createElement("summary");
      notesSummary.textContent = `${payload.needs_labels.length} issues need labels`;
      notes.append(notesSummary);

      const list = document.createElement("ul");
      list.className = "tif-timeline-list";
      payload.needs_labels.forEach(item => {
        appendIssue(list, item, item.missing.map(value => `missing ${value}`).join(" and "), "");
      });
      notes.append(list);
      container.append(notes);
    }

    container.hidden = false;
  };

  const renderRanking = (container, payload, submitRanking) => {
    container.replaceChildren();

    const heading = document.createElement("h3");
    heading.textContent = "Choose the schedule order";
    container.append(heading);

    const help = document.createElement("p");
    help.className = "tif-timeline-summary";
    help.textContent = "There are more same-priority issues than available developers. Click every issue in the order it should be scheduled. Click a ranked issue to remove its position.";
    container.append(help);

    const groupKey = group => group.ranking_key || group.priority;
    const selections = new Map(payload.ranking_groups.map(group => [groupKey(group), []]));
    const expectedCount = payload.ranking_groups.reduce((total, group) => total + group.issues.length, 0);
    const groupsContainer = document.createElement("div");
    groupsContainer.className = "tif-ranking-groups";
    container.append(groupsContainer);

    const actions = document.createElement("div");
    actions.className = "tif-ranking-actions";
    const automaticButton = document.createElement("button");
    automaticButton.type = "button";
    automaticButton.textContent = "Order automatically by creation date";
    automaticButton.addEventListener("click", () => submitRanking("created_at", []));
    actions.append(automaticButton);

    const confirmButton = document.createElement("button");
    confirmButton.type = "button";
    confirmButton.className = "tif-primary";
    confirmButton.textContent = "Generate with this order";
    confirmButton.disabled = true;
    confirmButton.addEventListener("click", () => {
      const issueOrder = payload.ranking_groups.flatMap(group => selections.get(groupKey(group)));
      submitRanking("manual", issueOrder);
    });
    actions.append(confirmButton);
    container.append(actions);

    const renderGroups = () => {
      groupsContainer.replaceChildren();

      payload.ranking_groups.forEach(group => {
        const section = document.createElement("section");
        section.className = "tif-ranking-group";
        const title = document.createElement("h4");
        title.textContent = group.status === "in_progress" ? `${group.priority} · In progress` : group.priority;
        section.append(title);

        const selectedIds = selections.get(groupKey(group));
        const list = document.createElement("div");
        list.className = "tif-ranking-list";
        group.issues.forEach(issue => {
          const rank = selectedIds.indexOf(issue.id);
          const button = document.createElement("button");
          button.type = "button";
          button.className = "tif-ranking-issue";
          button.setAttribute("aria-pressed", rank >= 0 ? "true" : "false");
          if (rank >= 0) button.classList.add("is-ranked");

          const position = document.createElement("span");
          position.className = "tif-ranking-position";
          position.textContent = rank >= 0 ? String(rank + 1) : "–";
          button.append(position);

          const label = document.createElement("span");
          label.className = "tif-ranking-label";
          const issueName = document.createElement("span");
          issueName.className = "tif-ranking-name";
          issueName.textContent = `${issue.repository.split("/").pop()}#${issue.issue_number} · ${issue.title}`;
          label.append(issueName);

          const effort = document.createElement("span");
          effort.className = "tif-ranking-effort";
          effort.textContent = issue.effort;
          label.append(effort);
          button.append(label);

          button.addEventListener("click", () => {
            if (rank >= 0) {
              selectedIds.splice(rank, 1);
            } else {
              selectedIds.push(issue.id);
            }
            renderGroups();
          });
          list.append(button);
        });
        section.append(list);
        groupsContainer.append(section);
      });

      const selectedCount = Array.from(selections.values()).reduce((total, ids) => total + ids.length, 0);
      confirmButton.disabled = selectedCount !== expectedCount;
    };

    renderGroups();
    container.hidden = false;
  };

  const initialize = root => {
    if (root.dataset.initialized === "true") return;
    root.dataset.initialized = "true";

    const form = root.querySelector("#github-issue-filters");
    const copyButton = root.querySelector("#tif-copy-link");
    const openTimelineButton = root.querySelector("#tif-open-timeline");
    const dialog = root.querySelector("#tif-timeline-dialog");
    const closeTimelineButton = root.querySelector("#tif-close-timeline");
    const generateButton = root.querySelector("#tif-generate-timeline");
    const startsOnInput = root.querySelector("#tif-starts-on");
    const inheritUnavailabilityInput = root.querySelector("#tif-inherit-unavailability");
    const inheritManualAssignmentsInput = root.querySelector("#tif-inherit-manual-assignments");
    const results = root.querySelector("#tif-timeline-results");
    const status = root.querySelector("#tif-status");
    const resultTypeInput = form.querySelector("[name='result_type']");
    const noPriorityInput = form.querySelector("[data-no-priority-filter]");
    const priorityInputs = form.querySelectorAll("[data-priority-filter]");

    const updateTimelineAvailability = () => {
      const issuesSelected = resultTypeInput.value === "issues";
      openTimelineButton.disabled = !issuesSelected;
      openTimelineButton.title = issuesSelected ? "" : "Timelines can only be drafted from issues";
    };

    resultTypeInput.addEventListener("change", updateTimelineAvailability);
    updateTimelineAvailability();

    noPriorityInput.addEventListener("change", () => {
      if (!noPriorityInput.checked) return;

      priorityInputs.forEach(input => { input.checked = false; });
    });

    priorityInputs.forEach(input => {
      input.addEventListener("change", () => {
        if (input.checked) noPriorityInput.checked = false;
      });
    });

    copyButton.addEventListener("click", async () => {
      copyButton.disabled = true;
      status.textContent = "Preparing link…";

      try {
        const query = new URLSearchParams(new FormData(form));
        const response = await fetch(`${root.dataset.githubUrl}?${query}`, {
          headers: { Accept: "application/json" }
        });
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.error || "Could not build the GitHub link.");

        await navigator.clipboard.writeText(payload.url);
        status.textContent = "GitHub link copied.";
      } catch (error) {
        status.textContent = error.message;
      } finally {
        copyButton.disabled = false;
      }
    });

    openTimelineButton.addEventListener("click", () => {
      startsOnInput.value ||= localDateValue(new Date());
      results.hidden = true;
      results.replaceChildren();
      dialog.showModal();
    });

    closeTimelineButton.addEventListener("click", () => dialog.close());

    const requestTimeline = async (tieBreaker = null, issueOrder = []) => {
      if (!startsOnInput.reportValidity()) return;

      generateButton.disabled = true;
      generateButton.textContent = "Loading issues…";
      results.hidden = false;
      results.replaceChildren();
      const loading = document.createElement("p");
      loading.className = "tif-help";
      loading.textContent = "Loading matching issues from GitHub…";
      results.append(loading);

      const body = new FormData(form);
      body.set("starts_on", startsOnInput.value);
      body.set("inherit_unavailability", inheritUnavailabilityInput.checked ? "1" : "0");
      body.set("inherit_manual_assignments", inheritManualAssignmentsInput.checked ? "1" : "0");
      if (tieBreaker) body.set("tie_breaker", tieBreaker);
      issueOrder.forEach(issueId => body.append("issue_order[]", issueId));

      try {
        const response = await fetch(root.dataset.timelineUrl, {
          method: "POST",
          headers: {
            Accept: "application/json",
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
          },
          body
        });
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.error || "Could not generate the timeline.");
        if (payload.ranking_required) {
          renderRanking(results, payload, requestTimeline);
        } else if (payload.timeline_url) {
          window.location.assign(payload.timeline_url);
        } else {
          renderTimeline(results, payload);
        }
      } catch (error) {
        const message = document.createElement("p");
        message.className = "tif-error";
        message.textContent = error.message;
        results.replaceChildren(message);
      } finally {
        generateButton.disabled = false;
        generateButton.textContent = "Generate draft";
      }
    };

    generateButton.addEventListener("click", () => requestTimeline());
  };

  const initializeTimelineDetails = root => {
    if (root.dataset.timelineDetailsInitialized === "true") return;
    root.dataset.timelineDetailsInitialized = "true";

    const chart = root.querySelector(".tif-timeline-chart");
    const tasks = Array.from(root.querySelectorAll("[data-timeline-issue]"));
    const cards = Array.from(root.querySelectorAll("[data-timeline-issue-card]"));
    if (!chart || !tasks.length || !cards.length) return;

    const activate = issueKey => {
      root.dataset.highlightedTimelineIssue = issueKey;
      chart.classList.add("is-highlighting-issue");
      tasks.forEach(task => task.classList.toggle("is-highlighted", task.dataset.timelineIssue === issueKey));
      cards.forEach(card => card.classList.toggle("is-highlighted", card.dataset.timelineIssueCard === issueKey));
    };

    const deactivate = issueKey => {
      if (root.dataset.highlightedTimelineIssue !== issueKey) return;

      delete root.dataset.highlightedTimelineIssue;
      chart.classList.remove("is-highlighting-issue");
      tasks.forEach(task => task.classList.remove("is-highlighted"));
      cards.forEach(card => card.classList.remove("is-highlighted"));
    };

    cards.forEach(card => {
      const issueKey = card.dataset.timelineIssueCard;
      card.addEventListener("mouseenter", () => activate(issueKey));
      card.addEventListener("mouseleave", () => {
        if (!card.matches(":focus-within")) deactivate(issueKey);
      });
      card.addEventListener("focusin", () => activate(issueKey));
      card.addEventListener("focusout", event => {
        if (!card.contains(event.relatedTarget)) deactivate(issueKey);
      });
    });
  };

  const initializeTimelineIssueEditor = root => {
    if (root.dataset.timelineIssueEditorInitialized === "true") return;
    root.dataset.timelineIssueEditorInitialized = "true";

    const tracks = Array.from(root.querySelectorAll("[data-timeline-issue-drop-track]"));
    const tasks = Array.from(root.querySelectorAll("[data-timeline-item-move-url]"));
    const status = root.querySelector("[data-timeline-issue-move-status]");
    if (!tracks.length || !tasks.length) return;

    let draggedIssueId = null;
    let draggedMoveUrl = null;

    const draggedTasks = () => tasks.filter(task => task.dataset.timelineIssue === draggedIssueId);
    const clearDragState = () => {
      draggedTasks().forEach(task => task.classList.remove("is-dragging"));
      tracks.forEach(track => {
        track.classList.remove("is-issue-drag-over");
        track.style.removeProperty("--tif-issue-drop-left");
      });
      draggedIssueId = null;
      draggedMoveUrl = null;
    };

    const beforeIssueAt = (track, clientX) => {
      const issues = new Map();
      track.querySelectorAll("[data-timeline-item-move-url]").forEach(task => {
        const issueId = task.dataset.timelineIssue;
        if (issueId === draggedIssueId) return;

        const current = issues.get(issueId);
        if (!current || Number(task.dataset.itemStartColumn) < Number(current.dataset.itemStartColumn)) {
          issues.set(issueId, task);
        }
      });

      return Array.from(issues.values())
        .sort((left, right) => Number(left.dataset.itemStartColumn) - Number(right.dataset.itemStartColumn))
        .find(task => clientX < task.getBoundingClientRect().left + (task.getBoundingClientRect().width / 2))
        ?.dataset.timelineIssue || null;
    };

    const moveIssue = async (track, beforeItemId) => {
      if (!draggedMoveUrl) return;

      const moveUrl = draggedMoveUrl;
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content;
      if (status) status.textContent = `Moving issue to ${track.dataset.developerId}…`;
      root.classList.add("is-moving-timeline-issue");

      try {
        const response = await fetch(moveUrl, {
          method: "PATCH",
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
            ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
          },
          body: JSON.stringify({
            timeline_item: {
              developer_id: track.dataset.developerId,
              before_item_id: beforeItemId
            }
          })
        });
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.error || "Could not move the issue.");

        window.location.assign(payload.timeline_url || window.location.href);
      } catch (error) {
        root.classList.remove("is-moving-timeline-issue");
        if (status) status.textContent = error.message;
      }
    };

    tasks.forEach(task => {
      task.addEventListener("dragstart", event => {
        if (root.classList.contains("is-selecting-unavailability")) {
          event.preventDefault();
          return;
        }

        draggedIssueId = task.dataset.timelineIssue;
        draggedMoveUrl = task.dataset.timelineItemMoveUrl;
        draggedTasks().forEach(issueTask => issueTask.classList.add("is-dragging"));
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("text/plain", draggedIssueId);
        if (status) status.textContent = "Choose a position in any developer's schedule.";
      });

      task.addEventListener("dragend", clearDragState);

      task.addEventListener("keydown", event => {
        if (!event.altKey || !event.shiftKey || ![ "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown" ].includes(event.key)) return;

        const sourceTrack = task.closest("[data-timeline-issue-drop-track]");
        const sourceTrackIndex = tracks.indexOf(sourceTrack);
        const sourceIssueIds = Array.from(new Map(
          Array.from(sourceTrack.querySelectorAll("[data-timeline-item-move-url]"))
            .sort((left, right) => Number(left.dataset.itemStartColumn) - Number(right.dataset.itemStartColumn))
            .map(issueTask => [ issueTask.dataset.timelineIssue, issueTask ])
        ).keys());
        const sourceIssueIndex = sourceIssueIds.indexOf(task.dataset.timelineIssue);
        let targetTrack = sourceTrack;
        let beforeItemId;

        if (event.key === "ArrowLeft") {
          if (sourceIssueIndex <= 0) return;
          beforeItemId = sourceIssueIds[sourceIssueIndex - 1];
        } else if (event.key === "ArrowRight") {
          if (sourceIssueIndex === sourceIssueIds.length - 1) return;
          beforeItemId = sourceIssueIds[sourceIssueIndex + 2] || null;
        } else {
          const offset = event.key === "ArrowUp" ? -1 : 1;
          targetTrack = tracks[sourceTrackIndex + offset];
          if (!targetTrack) return;
        }

        event.preventDefault();
        draggedIssueId = task.dataset.timelineIssue;
        draggedMoveUrl = task.dataset.timelineItemMoveUrl;
        if (beforeItemId === undefined) {
          const bounds = task.getBoundingClientRect();
          beforeItemId = beforeIssueAt(targetTrack, bounds.left + (bounds.width / 2));
        }
        moveIssue(targetTrack, beforeItemId);
        clearDragState();
      });
    });

    tracks.forEach(track => {
      track.addEventListener("dragover", event => {
        if (!draggedIssueId) return;

        event.preventDefault();
        event.dataTransfer.dropEffect = "move";
        tracks.forEach(candidate => candidate.classList.toggle("is-issue-drag-over", candidate === track));
        const bounds = track.getBoundingClientRect();
        const relativeX = Math.max(0, Math.min(event.clientX - bounds.left, bounds.width));
        track.style.setProperty("--tif-issue-drop-left", `${(relativeX / bounds.width) * 100}%`);
      });

      track.addEventListener("dragleave", event => {
        if (track.contains(event.relatedTarget)) return;
        track.classList.remove("is-issue-drag-over");
        track.style.removeProperty("--tif-issue-drop-left");
      });

      track.addEventListener("drop", event => {
        if (!draggedIssueId) return;

        event.preventDefault();
        const beforeItemId = beforeIssueAt(track, event.clientX);
        moveIssue(track, beforeItemId);
        clearDragState();
      });
    });
  };

  const initializeUnavailabilityEditor = root => {
    if (root.dataset.unavailabilityEditorInitialized === "true") return;
    root.dataset.unavailabilityEditorInitialized = "true";

    const addDialog = root.querySelector("#tif-add-unavailability-dialog");
    const openAddDialogButton = root.querySelector("[data-open-add-unavailability-dialog]");
    if (addDialog && openAddDialogButton) {
      const addForm = addDialog.querySelector("form");
      const selectionPrompt = root.querySelector("[data-unavailability-selection-prompt]");
      const selectionTracks = Array.from(root.querySelectorAll("[data-unavailability-selection-track]"));
      const defaultPrompt = "Click a position in the timeline to choose the developer and start time.";
      const addField = name => addForm?.elements[`timeline_unavailability[${name}]`];
      let selecting = false;

      const slotGeometry = track => {
        const slotCount = Number(track.dataset.slotCount);
        const dayCount = slotCount / 8;
        const compact = track.closest("[data-timeline-chart-view]")?.classList.contains("is-compact-weekends");
        const weekendIndexes = new Set((track.dataset.weekendDayIndexes || "")
          .split(",")
          .filter(Boolean)
          .map(Number));
        const dayWidths = Array.from({ length: dayCount }, (_value, index) =>
          compact && weekendIndexes.has(index) ? 32 : 112
        );
        const totalWidth = dayWidths.reduce((total, width) => total + width, 0);

        return { dayWidths, slotCount, totalWidth };
      };

      const slotAt = (track, clientX) => {
        const bounds = track.getBoundingClientRect();
        const relativeX = Math.max(0, Math.min(clientX - bounds.left, bounds.width - 1));
        const geometry = slotGeometry(track);
        const timelineX = (relativeX / bounds.width) * geometry.totalWidth;
        let dayStart = 0;

        for (let dayIndex = 0; dayIndex < geometry.dayWidths.length; dayIndex += 1) {
          const dayWidth = geometry.dayWidths[dayIndex];
          if (timelineX < dayStart + dayWidth) {
            const hourIndex = Math.min(7, Math.floor(((timelineX - dayStart) / dayWidth) * 8));
            return (dayIndex * 8) + hourIndex;
          }
          dayStart += dayWidth;
        }

        return geometry.slotCount - 1;
      };

      const slotPosition = (track, slot) => {
        const geometry = slotGeometry(track);
        const dayIndex = Math.floor(slot / 8);
        const hourIndex = slot % 8;
        const dayStart = geometry.dayWidths
          .slice(0, dayIndex)
          .reduce((total, width) => total + width, 0);
        const slotWidth = geometry.dayWidths[dayIndex] / 8;

        return {
          left: ((dayStart + (hourIndex * slotWidth)) / geometry.totalWidth) * 100,
          width: (slotWidth / geometry.totalWidth) * 100
        };
      };

      const selectionAt = (track, clientX) => {
        const slot = slotAt(track, clientX);
        const date = parseDate(track.dataset.startDate);
        date.setDate(date.getDate() + Math.floor(slot / 8));

        return {
          date: localDateValue(date),
          developerId: track.dataset.developerId,
          hour: 9 + (slot % 8),
          slot
        };
      };

      const describeSelection = selection => {
        const time = `${String(selection.hour).padStart(2, "0")}:00`;
        return `${selection.developerId} · ${formatDate(selection.date)} at ${time} — click to select`;
      };

      const setSelecting = value => {
        selecting = value;
        root.classList.toggle("is-selecting-unavailability", selecting);
        openAddDialogButton.setAttribute("aria-pressed", String(selecting));
        openAddDialogButton.textContent = selecting ? "Cancel selection" : "Add";
        if (selectionPrompt) {
          selectionPrompt.hidden = !selecting;
          selectionPrompt.textContent = defaultPrompt;
        }
        if (!selecting) {
          selectionTracks.forEach(track => {
            track.style.removeProperty("--tif-selection-left");
            track.style.removeProperty("--tif-selection-width");
          });
        }
      };

      openAddDialogButton.addEventListener("click", () => {
        if (!selectionTracks.length) {
          addDialog.showModal();
          return;
        }

        setSelecting(!selecting);
        if (selecting) {
          root.querySelector(".tif-timeline-chart-scroll")?.scrollIntoView({ behavior: "smooth", block: "center" });
        }
      });

      selectionTracks.forEach(track => {
        track.addEventListener("pointermove", event => {
          if (!selecting) return;

          const selection = selectionAt(track, event.clientX);
          const position = slotPosition(track, selection.slot);
          track.style.setProperty("--tif-selection-left", `${position.left}%`);
          track.style.setProperty("--tif-selection-width", `${position.width}%`);
          if (selectionPrompt) selectionPrompt.textContent = describeSelection(selection);
        });

        track.addEventListener("pointerleave", () => {
          if (!selecting) return;

          track.style.removeProperty("--tif-selection-left");
          track.style.removeProperty("--tif-selection-width");
          if (selectionPrompt) selectionPrompt.textContent = defaultPrompt;
        });

        track.addEventListener("click", event => {
          if (!selecting) return;

          event.preventDefault();
          event.stopPropagation();
          const selection = selectionAt(track, event.clientX);
          addField("developer_id").value = selection.developerId;
          addField("unavailable_on").value = selection.date;
          addField("unavailable_at_time").value = `${String(selection.hour).padStart(2, "0")}:00`;
          setSelecting(false);
          addDialog.showModal();
        }, true);
      });

      root.addEventListener("keydown", event => {
        if (selecting && event.key === "Escape") setSelecting(false);
      });

      addDialog.querySelectorAll("[data-close-add-unavailability-dialog]").forEach(button => {
        button.addEventListener("click", () => addDialog.close());
      });

      addDialog.addEventListener("click", event => {
        if (event.target === addDialog) addDialog.close();
      });
    }

    const dialog = root.querySelector("#tif-unavailability-dialog");
    const updateForm = dialog?.querySelector("[data-unavailability-update-form]");
    if (!dialog || !updateForm) return;

    const field = name => updateForm.elements[`timeline_unavailability[${name}]`];

    root.querySelectorAll("[data-unavailability]").forEach(period => {
      period.addEventListener("click", () => {
        updateForm.action = period.dataset.updateUrl;
        field("developer_id").value = period.dataset.developerId;
        field("unavailable_on").value = period.dataset.unavailableOn;
        field("unavailable_at_time").value = period.dataset.unavailableAtTime;
        field("duration_amount").value = period.dataset.durationAmount;
        field("duration_unit").value = "hours";
        field("reason").value = period.dataset.reason || "";
        field("allow_reassignment").checked = true;
        dialog.showModal();
      });
    });

    dialog.querySelectorAll("[data-close-unavailability-dialog]").forEach(button => {
      button.addEventListener("click", () => dialog.close());
    });

    dialog.addEventListener("click", event => {
      if (event.target === dialog) dialog.close();
    });
  };

  const initializeAll = () => {
    initializeCompactWeekendToggles();
    document.querySelectorAll(".github-issue-organizer-engine[data-timeline-url]").forEach(initialize);
    document.querySelectorAll(".github-issue-organizer-engine[data-timeline-details]").forEach(initializeTimelineDetails);
    document.querySelectorAll(".github-issue-organizer-engine[data-timeline-issue-editor]").forEach(initializeTimelineIssueEditor);
    document.querySelectorAll(".github-issue-organizer-engine[data-unavailability-editor]").forEach(initializeUnavailabilityEditor);
  };

  document.addEventListener("DOMContentLoaded", initializeAll);
  document.addEventListener("turbo:load", initializeAll);
  document.addEventListener("turbo:before-cache", () => {
    document.querySelectorAll(".github-issue-organizer-engine[data-initialized]").forEach(root => {
      delete root.dataset.initialized;
    });
    document.querySelectorAll(".github-issue-organizer-engine[data-timeline-details-initialized]").forEach(root => {
      delete root.dataset.timelineDetailsInitialized;
    });
    document.querySelectorAll(".github-issue-organizer-engine[data-timeline-issue-editor-initialized]").forEach(root => {
      delete root.dataset.timelineIssueEditorInitialized;
    });
    document.querySelectorAll(".github-issue-organizer-engine[data-unavailability-editor-initialized]").forEach(root => {
      delete root.dataset.unavailabilityEditorInitialized;
    });
    document.querySelectorAll("[data-compact-weekends-toggle][data-initialized]").forEach(toggle => {
      delete toggle.dataset.initialized;
    });
  });
})();
