# Example: Incorrect Usage

Common mistakes with explanations and corrections.

---

## 1. Creating request without querying context first

### Wrong

```
create_request(
  title: "Add payment gateway",
  description: "Integrate Stripe for invoices",
  priority: "high"
)
// No project_id, no milestone_id, no assignees
// Where does this belong? Who works on it?
```

### Why it's wrong
- Request is orphaned in the triage inbox
- Not linked to any project or milestone
- **No assignee** → born `pending` instead of `assigned`; earns zero XP on resolution (the award
  trigger bails when the assignee count is 0, and never runs again); counts for nobody in the
  workload or developer-performance views
- **No `due_date`** → never shows up as overdue (the overdue queries filter out null dates), never
  triggers a reminder, never earns the on-time bonus
- **No `estimated_hours`** → effort base drops to its 30 XP floor
- Missing `category` — no planning data

### Correct

```
// 1. Get context first
list_projects()                              → project_id
list_milestones(project_id: "proj-uuid")     → milestone_id
list_team()                                  → assignee UUIDs

// 2. Create with full context
create_request(
  title: "Add payment gateway",
  description: "Integrate Stripe for invoices: checkout session, webhooks, refunds",
  priority: "high",
  category: "nuevo",
  project_id: "proj-uuid",
  milestone_id: "milestone-uuid",
  assignee_ids: ["dev-uuid"],
  estimated_hours: 20,
  due_date: "2026-06-01"
)
```

---

## 2. Skipping status transitions

### Wrong

```
// Request is "pending"
update_request_status(id: "req-uuid", status: "under_review")
// ERROR: Invalid transition from pending to under_review
```

### Why it's wrong
The state machine doesn't allow skipping. `pending` can only go to `assigned`, `in_progress`, or `cancelled`.

### Correct

```
update_request_status(id: "req-uuid", status: "in_progress")
// ... work happens ...
update_request_status(id: "req-uuid", status: "under_review")
```

---

## 3. Creating GitHub PR without issue+branch

### Wrong

```
create_request(title: "Fix bug", description: "...", priority: "high", category: "bug")

// Developer creates branch manually: git checkout -b bugfix/my-fix
// Developer pushes code

create_github_pr(request_id: "req-uuid")
// ERROR: No github link found for this request
```

### Why it's wrong
`create_github_pr` needs a `request_github_links` record that's created by `create_github_issue_branch`. Without it, there's no link between the HOT request and GitHub.

### Correct

```
create_request(...)
update_request_status(id: "req-uuid", status: "in_progress")
create_github_issue_branch(request_id: "req-uuid", base_branch: "develop")
// ... push code to the auto-created branch ...
create_github_pr(request_id: "req-uuid")
```

---

## 4. Completing milestone with unresolved requests

### Wrong

```
// Milestone has 3 requests: resolved, resolved, in_progress
update_milestone(milestone_id: "ms-uuid", status: "completed")
// API allows it, but it's WRONG
```

### Why it's wrong
The API doesn't enforce this constraint, but marking a milestone completed while requests are still open creates false progress reports. Stakeholders think the phase is done.

### Correct

```
// Check first
list_milestones(project_id: "proj-uuid")
// → Request 3 still "in_progress"
// → DO NOT complete milestone yet

// Wait for all requests to resolve, then:
update_milestone(milestone_id: "ms-uuid", status: "completed")
```

---

## 5. Creating branch from wrong base

### Wrong

```
create_github_issue_branch(request_id: "req-uuid")
// Uses repo's default branch (might be "main")
// But team works from "develop"!
// PR will target wrong branch, diff will be huge
```

### Why it's wrong
If your gitflow uses `develop` as the working branch but the repo's default is `main`, the branch will be based on `main`. The PR diff will include all commits from `develop` that haven't been merged to `main`.

### Correct

```
create_github_issue_branch(
  request_id: "req-uuid",
  base_branch: "develop"
)
```

---

## 6. Adding checklist AFTER work is done

### Wrong

```
create_request(...)
update_request_status("in_progress")
create_github_issue_branch(...)
// ... developer works for 3 days ...
// "Oh wait, I should add a checklist"
add_checklist_item(request_id, "Migration done")       // already done
add_checklist_item(request_id, "Tests passing")        // already done
update_checklist_item(id: "item-1", is_complete: true) // retroactive
update_checklist_item(id: "item-2", is_complete: true) // retroactive
```

### Why it's wrong
Checklist items added retroactively provide no value — they don't guide work, they just create busywork. The team can't track real progress.

### Correct

```
create_request(...)
// Define done BEFORE starting
add_checklist_item(request_id, "Migration created and tested")
add_checklist_item(request_id, "RLS policies for all tables")
add_checklist_item(request_id, "Types regenerated")
add_checklist_item(request_id, "Unit tests for server actions")
// NOW start work
update_request_status("in_progress")
create_github_issue_branch(...)
```

---

## 7. Not documenting blockers

### Wrong

```
update_request_status(id: "req-uuid", status: "blocked")
// ... silence ...
// Days later:
update_request_status(id: "req-uuid", status: "in_progress")
```

### Why it's wrong
This doesn't even get the chance to be undocumented — `update_request_status(status: "blocked")` without
a `note` of at least 5 characters is rejected outright (`ERRCODE HT001`, SR-3/SR-15). The request never
moves to `blocked` at all. Even with a `note` short enough to only just pass, the underlying problem
remains: no one knows WHY it was blocked or HOW it was resolved without one that actually explains it.

### Correct

```
update_request_status(
  id: "req-uuid",
  status: "blocked",
  note: "Supabase Realtime no soporta el formato de función actual en RLS — esperando guía de @[Maria](uuid)"
)
add_comment(
  request_id: "req-uuid",
  content: "Blocked: Supabase Realtime doesn't support the current RLS function format. Need to simplify policy. Waiting on @[Maria](uuid) for guidance."
)

// When resolved:
add_comment(
  request_id: "req-uuid",
  content: "Unblocked: Simplified RLS to use auth.uid() = user_id directly. Maria confirmed this approach is safe for our use case."
)
update_request_status(id: "req-uuid", status: "in_progress")
```

---

## 8. Not updating HOT after GitHub merge

### Wrong

```
create_github_pr(request_id: "req-uuid")
// PR merged → GitHub issue auto-closed
// Developer forgets to update HOT
// Request shows "under_review" forever
```

### Why it's wrong
GitHub auto-close only affects the GitHub issue. HOT status is independent. The request appears stuck in review.

### Correct

```
// After PR merge:
update_request_status(id: "req-uuid", status: "resolved")
```

---

## 9. Using `milestone_id` without `project_id`

### Wrong

```
create_request(
  title: "Some task",
  description: "...",
  priority: "mid",
  milestone_id: "ms-uuid"
  // Missing project_id!
)
```

### Why it's wrong
Milestones belong to projects. A request can't be linked to a milestone without also being linked to the project.

### Correct

```
create_request(
  title: "Some task",
  description: "...",
  priority: "mid",
  project_id: "proj-uuid",
  milestone_id: "ms-uuid"
)
```

---

## 10. Starting dependent milestone too early

### Wrong

```
// Milestone B depends_on Milestone A
// Milestone A has 1 of 3 requests still in_progress
update_milestone(milestone_id: "milestone-b", status: "in_progress")
// Starting B before A is done!
```

### Why it's wrong
If B depends on A's output (e.g., API depends on database), starting B early leads to rework when A's final changes break B's assumptions.

### Correct

```
// Wait for A to complete
list_milestones(project_id)
// → milestone-a: all requests resolved ✓

update_milestone(milestone_id: "milestone-a", status: "completed")
// NOW start B
update_milestone(milestone_id: "milestone-b", status: "in_progress")
```

---

## 11. Leaving a request unassigned "so someone picks it up"

### Wrong

```
// User: "creá la tarea del reporte mensual"
create_request(
  title: "Reporte de ventas mensual",
  description: "...",
  priority: "mid",
  project_id: "proj-uuid",
  milestone_id: "ms-uuid",
  due_date: "2026-09-10",
  estimated_hours: 8
)
// assignee_ids omitted on purpose — "el equipo la toma"
```

### Why it's wrong
Nobody takes what no view shows. The request lands as `pending` in the triage inbox rather than in
anyone's queue, and — the expensive part — when it is finally resolved, `on_request_resolved` exits
immediately at zero assignees: **no XP, no badges, no stats recompute, for anyone**. That trigger runs
only on the transition into `resolved`, so assigning the request afterwards recovers nothing.

### Correct

```
// Named person → resolve the name
list_team() → "Carlos Rivas" → carlos-uuid
create_request(..., assignee_ids: ["carlos-uuid"])

// Nobody named → the API-key owner asked for it, so they own it
whoami() → { id: "my-uuid" }
create_request(..., assignee_ids: ["my-uuid"])
```

If the user really wants it unassigned, honour it — and say what it costs, once:

> "La dejo sin asignar. Ojo: así no suma XP a nadie al resolverse, no aparece en la vista de carga del
>  equipo, y el recordatorio de vencimiento no tiene a quién avisar."

---

## 12. Omitting the date because the user didn't give one

### Wrong

```
// User: "creá una tarea para arreglar el login"
create_request(
  title: "Fix login bug",
  description: "...",
  priority: "high",
  assignee_ids: ["my-uuid"]
)
// "No dijo fecha, así que no le pongo ninguna."
```

### Why it's wrong
A null `due_date` is not the neutral choice — it removes the request from every deadline mechanism at
once. The overdue queries filter `due_date IS NOT NULL`, so a task three weeks late is simply **not
counted as late**. The reminder cron never selects it. The on-time bonus is gated on the same
condition, and `on_time_cnt` in `developer_stats` counts only dated rows — so the whole team's on-time
rate reads lower than reality.

The instinct behind the omission is sound: *don't invent numbers and pass them off as the user's.*
The fix isn't to leave the hole — it's to make the default **visible**.

### Correct

```
create_request(
  title: "Fix login bug",
  description: "...",
  priority: "high",
  assignee_ids: ["my-uuid"],
  due_date: "2026-09-04",     // high → today + 3 business days
  estimated_hours: 6
)
```

Then, in the same reply:

```
Creada REQ-A1B2C3 — asignada a Carlos Rivas, vence 2026-09-04
(default de prioridad alta: +3 días hábiles), estimada en 6 h.
Decime si ajusto fecha, horas o responsable.
```

**Fabricating** is inventing a value and presenting it as the user's. **Defaulting** is applying a
stated rule, naming the rule, and inviting correction in the same breath. Only the first one is
forbidden.

---

## Summary: The 15 Commandments

1. **Always query context** before creating (`list_projects`, `list_milestones`, `list_team`)
2. **Always link** `project_id` and `milestone_id` when they exist
3. **Respect the state machine** — no skipping transitions
4. **Issue+branch before PR** — always `create_github_issue_branch` first
5. **Verify before completing** milestones — all requests must be resolved
6. **Specify `base_branch`** — don't rely on repo defaults
7. **Checklist before work** — define done upfront
8. **Document blockers** — always comment why blocked and how resolved
9. **Update HOT after merge** — GitHub auto-close ≠ HOT resolution
10. **Respect dependencies** — don't start milestone before its dependency completes
11. **Always include `due_date` and `estimated_hours`** — at creation, not later; derive from priority and scope if the user gave none, and say so
12. **GitHub is mandatory for development** — `domain: "development"` requests MUST use issue+branch+PR
13. **Verify project has GitHub repo** before creating dev requests — STOP and inform if missing
14. **Never create a request with empty `assignee_ids`** — the person named (`list_team`) or the API-key owner (`whoami`). An unassigned request earns zero XP, permanently
15. **Announce every derived value** — assignee, date and hours in one correctable line. A silent default is indistinguishable from a fabrication
