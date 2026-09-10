# Status Transitions

State machines for requests and milestones in the HOT Platform.

---

## ⛔ Prerequisite: `backlog_state` Must Be `"ready"`

Every transition table below assumes the request has already cleared a gate that sits in front of all of
them: `requests.backlog_state` must be `"ready"`, not `"backlog"`. A request still in the backlog cannot
have its `status` changed to *anything* — not even the first hop out of `pending` — regardless of what
the transition tables say is otherwise allowed. The DB rejects the attempt with `ERRCODE HT003`, no
exceptions.

```
backlog_state: "backlog"  →  update_request_status(...)  →  rejected (HT003), no matter the target status
```

Fix: `update_request(id, backlog_state: "ready")` first (after refining the request — see
[backlog-and-readiness.md](backlog-and-readiness.md)). A request created with both `assignee_ids` and
`due_date` is born `ready` and never hits this gate — see Rule 8/16 in [SKILL.md](../SKILL.md).

---

## Request Status State Machine

### States

| Status | Description | Terminal? |
|--------|-------------|-----------|
| `pending` | Created, awaiting triage | No |
| `assigned` | Assigned to developer, not started | No |
| `in_progress` | Actively being worked on | No |
| `blocked` | Work paused, waiting on something | No |
| `under_review` | Code complete, awaiting review | No |
| `resolved` | Done and verified | Yes |
| `cancelled` | Abandoned or invalid | Semi (can reopen) |

### Transition Map

```
                    ┌──────────────────────────────────────────┐
                    │                                          │
                    ▼                                          │
 ┌─────────┐    ┌──────────┐    ┌─────────────┐    ┌─────────┴───┐
 │ pending  │───→│ assigned │───→│ in_progress │───→│under_review │
 └────┬─────┘    └────┬─────┘    └──┬───┬──────┘    └──┬────┬─────┘
      │               │             │   │               │    │
      │               │             │   │  ┌────────┐   │    │
      │               │             │   └─→│blocked │───┘    │
      │               │             │      └────┬───┘        │
      │               │             │           │            │
      │               │             ▼           │            ▼
      │               │        ┌──────────┐     │      ┌──────────┐
      └───────────────┴───────→│cancelled │     │      │ resolved │
                               └────┬─────┘     │      └──────────┘
                                    │           │
                                    └───→ pending (reopen)
```

### Valid Transitions Table

| Current Status | Can transition to |
|----------------|-------------------|
| `pending` | `assigned`, `in_progress`, `cancelled` |
| `assigned` | `in_progress`, `cancelled` |
| `in_progress` | `under_review`, `blocked`, `resolved`, `cancelled` |
| `under_review` | `in_progress`, `resolved`, `cancelled` |
| `blocked` | `in_progress`, `cancelled` |
| `resolved` | — (terminal, no transitions) |
| `cancelled` | `pending` (reopen only) |

### Transition Rules

1. **No skipping states forward**: `pending` cannot go directly to `under_review`
2. **`resolved` is terminal**: Once resolved, the request is closed permanently
3. **`cancelled` can reopen**: But only to `pending` — it starts the lifecycle over
4. **`blocked` ↔ `in_progress`**: Bidirectional for blocker management
5. **`under_review` → `in_progress`**: Sends back for changes after review
6. **`in_progress` → `resolved`**: Allowed for quick fixes that don't need formal review
7. **`→ blocked` requires a `note`**: Any transition into `blocked` needs the `note` param (5-500 chars)
   justifying it, or `update_request_status` is rejected outright (`ERRCODE HT001`) — see
   [backlog-and-readiness.md](backlog-and-readiness.md)

### Common Transition Sequences

**Standard flow**:
```
pending → assigned → in_progress → under_review → resolved
```

**Quick fix (no review)**:
```
pending → in_progress → resolved
```

**With blockers**:
```
pending → in_progress → blocked → in_progress → under_review → resolved
```

**Review rejection**:
```
... → under_review → in_progress → under_review → resolved
```

**Cancelled and reopened**:
```
... → cancelled → pending → in_progress → ...
```

---

## Milestone Status State Machine

### States

| Status | Description |
|--------|-------------|
| `pending` | Planned, not started |
| `in_progress` | Active work underway |
| `completed` | All work done |
| `skipped` | Milestone no longer needed |

### Transitions

```
pending → in_progress → completed
                     → skipped
```

### Milestone Completion Rules

1. **Check all requests first**: Before marking `completed`, verify ALL linked requests are `resolved`
2. **Dependency chain**: When milestone A completes, milestone B (depends_on: A) can start
3. **Skipping**: Use `skipped` when scope changes make a milestone irrelevant
4. **No backward transitions**: `completed` and `skipped` are terminal
5. **No `blocked` status exists for milestones** — only requests have that state. A milestone with a blocked request just stays `in_progress`.
6. **Dates are required in practice**: `start_date`/`target_date` are API-optional but must always be set when planning real work (same principle as `due_date`/`estimated_hours` on requests). If the user gave none, derive them — `start_date` = today or the blocker's `target_date`; `target_date` = the latest `due_date` of its planned requests — and say which derivation you used. Deriving-and-announcing is not fabricating; leaving the timeline blank is not honesty.

### Cascade Rules — Milestone Status Tracks Its Requests

A milestone's status should never be updated in isolation from its requests. Two triggers, both proactive (don't wait to be asked):

| Trigger | Action |
|---|---|
| A request in a `pending` milestone moves to `in_progress` (or any active state) | Move the milestone to `in_progress` too, if it isn't already |
| The last unresolved request in an `in_progress` milestone moves to `resolved` | Check all linked requests via `list_milestones(project_id)` — if ALL are `resolved`, move the milestone to `completed` |

This applies regardless of whether the milestone's own status was ever explicitly touched — starting or finishing work on any of its requests is enough to trigger the cascade check. The user can also explicitly ask to start/complete a milestone directly (`update_milestone`), independent of individual request status — that's always allowed, the cascade is a minimum, not a restriction.

### Verification Pattern

Before completing a milestone:

```
// Step 1: Check all requests in milestone
list_milestones(project_id) → find milestone → check linked requests

// Step 2: Verify all resolved
// If any request is NOT resolved → do NOT complete milestone

// Step 3: Complete
update_milestone(milestone_id, status: "completed")

// Step 4: Start next milestone in dependency chain
update_milestone(next_milestone_id, status: "in_progress")
```

---

## Status-to-Action Mapping

| When you need to... | Set status to... | Also do... |
|---------------------|-----------------|------------|
| Start working on a request | `in_progress` | Check assignment first; `create_github_issue_branch`; cascade milestone to `in_progress` if it was `pending` |
| Report a blocker | `blocked` | `add_comment` with blocker details |
| Unblock and resume | `in_progress` | `add_comment` explaining resolution |
| Submit for review | `under_review` | `create_github_pr`; tell the user resolution won't happen automatically on merge |
| Send back from review | `in_progress` | `add_comment` with review feedback |
| Mark as done | `resolved` | Verify checklist complete; cascade milestone to `completed` if this was the last open request |
| Abandon a request | `cancelled` | `add_comment` with reason |
| Reopen cancelled | `pending` | `add_comment` explaining why reopened |
