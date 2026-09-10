# Example: Progress Tracking

Using checklists, comments, and status changes to track work in detail.

---

## Scenario

A developer is working on "Implement real-time notifications" and needs to track progress, handle a blocker, and coordinate with a teammate.

---

## Step 1: Setup with detailed checklist

```
create_request(
  title: "Implement real-time notifications",
  description: "Push notifications via Supabase Realtime for request status changes, new assignments, and mentions",
  priority: "mid",
  category: "nuevo",
  project_id: "proj-uuid",
  milestone_id: "milestone-uuid",
  assignee_ids: ["dev-uuid"],
  estimated_hours: 16,
  due_date: "2026-05-25"
)
→ req-uuid

// Detailed acceptance criteria
add_checklist_item(request_id: "req-uuid", title: "DB: notification_preferences table migration")
add_checklist_item(request_id: "req-uuid", title: "DB: notifications table with RLS")
add_checklist_item(request_id: "req-uuid", title: "Backend: Realtime channel setup")
add_checklist_item(request_id: "req-uuid", title: "Backend: Notification triggers on status change")
add_checklist_item(request_id: "req-uuid", title: "Backend: Notification triggers on assignment")
add_checklist_item(request_id: "req-uuid", title: "Backend: Notification triggers on @mention")
add_checklist_item(request_id: "req-uuid", title: "Frontend: NotificationBell component")
add_checklist_item(request_id: "req-uuid", title: "Frontend: NotificationPanel with mark-as-read")
add_checklist_item(request_id: "req-uuid", title: "Frontend: Toast for real-time notifications")
add_checklist_item(request_id: "req-uuid", title: "Test: All notification types firing correctly")
```

## Step 2: Start work

```
update_request_status(id: "req-uuid", status: "in_progress")
create_github_issue_branch(request_id: "req-uuid", base_branch: "develop")
→ feature/60-implement-real-time-notifications
```

## Step 3: Track progress day by day

### Day 1 — Database work

```
update_checklist_item(id: "item-1-uuid", is_complete: true)
update_checklist_item(id: "item-2-uuid", is_complete: true)

add_comment(
  request_id: "req-uuid",
  content: "DB tables created. Using JSONB for notification metadata to keep schema flexible."
)
```

### Day 2 — Hit a blocker

```
update_request_status(
  id: "req-uuid",
  status: "blocked",
  note: "RLS de Realtime no evalúa políticas basadas en función — necesito que Maria revise el enfoque"
)
// note is mandatory here (ERRCODE HT001 otherwise) — see backlog-and-readiness.md

add_comment(
  request_id: "req-uuid",
  content: "Blocked: Supabase Realtime requires specific RLS policy format for broadcast. Current policies use a function that Realtime can't evaluate. Need @[Maria Lopez](maria-uuid) to review the RLS approach."
)
```

### Day 3 — Blocker resolved

```
add_comment(
  request_id: "req-uuid",
  content: "Resolved: @[Maria Lopez](maria-uuid) confirmed we can use a simplified policy with auth.uid() = user_id for the notifications table. Realtime broadcast works with this pattern."
)

update_request_status(id: "req-uuid", status: "in_progress")

update_checklist_item(id: "item-3-uuid", is_complete: true)
update_checklist_item(id: "item-4-uuid", is_complete: true)
```

### Day 4 — More progress

```
update_checklist_item(id: "item-5-uuid", is_complete: true)
update_checklist_item(id: "item-6-uuid", is_complete: true)

add_comment(
  request_id: "req-uuid",
  content: "All backend triggers done. DB functions fire on INSERT to request_activity for status changes, assignments, and comments with mentions."
)
```

### Day 5 — Frontend complete

```
update_checklist_item(id: "item-7-uuid", is_complete: true)
update_checklist_item(id: "item-8-uuid", is_complete: true)
update_checklist_item(id: "item-9-uuid", is_complete: true)
update_checklist_item(id: "item-10-uuid", is_complete: true)
```

## Step 4: Submit for review

```
update_request_status(id: "req-uuid", status: "under_review")

create_github_pr(
  request_id: "req-uuid",
  body: "## Changes\n- 2 new tables: notifications, notification_preferences\n- Realtime broadcast on status/assignment/mention\n- NotificationBell + NotificationPanel components\n- Toast for live notifications\n\n## Testing\n- Tested all 3 trigger types\n- Tested mark-as-read\n- Tested with 2 users simultaneously"
)
```

## Step 5: Review feedback → back to work

```
add_comment(
  request_id: "req-uuid",
  content: "Review feedback from @[Carlos Ruiz](carlos-uuid): add unread count badge to NotificationBell and debounce the mark-as-read API call."
)

update_request_status(id: "req-uuid", status: "in_progress")

// ... make changes, push ...

update_request_status(id: "req-uuid", status: "under_review")

add_comment(
  request_id: "req-uuid",
  content: "Changes pushed: unread badge added, mark-as-read debounced to 500ms. Ready for re-review."
)
```

## Step 6: Approved and merged

```
// PR merged → Issue #60 auto-closed
update_request_status(id: "req-uuid", status: "resolved")

add_comment(
  request_id: "req-uuid",
  content: "Merged and deployed to staging. All notification types working correctly."
)
```

---

## Tracking Patterns Summary

| Situation | Tool | Example |
|-----------|------|---------|
| Work completed | `update_checklist_item` | Mark criteria done |
| Design decision | `add_comment` | Document the "why" |
| Hit a blocker | `update_request_status("blocked", note: "...")` + `add_comment` | `note` is mandatory (≥5 chars, ERRCODE HT001 otherwise) |
| Need someone's input | `add_comment` with `@[Name](uuid)` | Tag the person |
| Blocker resolved | `add_comment` + `update_request_status("in_progress")` | Explain resolution |
| Review feedback | `add_comment` + `update_request_status("in_progress")` | Document feedback |
| Changes ready | `update_request_status("under_review")` + `add_comment` | Signal re-review |
| Final merge | `update_request_status("resolved")` + `add_comment` | Close the loop |

---

## Reviewing Progress

At any point, check status with:

```
get_request(id: "req-uuid", include_activity: true)
→ Full timeline: status changes, comments, checklist updates

get_checklist(request_id: "req-uuid")
→ 8/10 items complete = 80% done
```
