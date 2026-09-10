# Timeline 34 repair preview

The scheduling fix preserves recorded segments before the timeline boundary and
subtracts their hours from the effort estimate. Historical dates by themselves
are not evidence of effort. Past schedule segments are planning history, not
independently verified time tracking.

Local database inspection found matching repository (`ChatBarAI/ai_lms`), GitHub
issue IDs, and developer (`ersad-persada`) in timelines 29, 33, and 34.
Timeline 34 is current; timelines 29 and 33 are obsolete. Timeline 34 has no
source_timeline_id, so these matches are supporting evidence, not an explicit
parent relationship.

Both earlier timelines record:

| Issue | Preserved work before September 11 | Estimate | Remaining |
| --- | --- | --- | --- |
| #48 | September 7, 09:00–17:00 (8 hours) | 8 hours | 0 hours |
| #50 | September 8–10, 09:00–17:00 each day (24 hours) | 40 hours | 16 hours |

If these records are authoritative, restore that history and reschedule timeline
34. Issue #48 ends September 7, and #50's remaining work occupies September 11
and 14, assuming no other capacity constraints.

If #48 was intentionally restarted on September 11, discard its old start date,
retain its September 11 segment, and restore only #50's history. Issue #50 then
occupies September 14–15. Its five recorded workdays total exactly 40 hours.

No database records have been changed. Resolve whether #48's September 7 work
counts before applying a repair. Preserve a snapshot of timeline 34's items,
restore the selected historical segments by repository and GitHub issue ID,
and reschedule within one transaction using its current item order and developer
assignments. Inspect the resulting full timeline before committing that transaction.

Do not automatically repair other timelines by matching issue numbers alone;
issue numbers are only unique within a repository. Missing historical segments
are now identified on the saved timeline chart rather than drawn as extra work.

## Verification

Engine regression coverage includes effort conservation across split work and
repeated scheduling, advancing the timeline boundary, partial history, boundary
clipping, weekends and interruptions, future unavailability, completed work, and
estimates reduced below historical hours. Reduced estimates retain their recorded
history and allocate no additional hours.
