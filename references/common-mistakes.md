# Common Mistakes

Anti-patterns when using HOT MCP tools, with explanations and corrections.

---

## Mistake 1: Missing `project_id` on project requests

### Wrong
```
create_request(
  title: "Create users migration",
  description: "...",
  priority: "high"
)
// Request created but NOT linked to any project
```

### Why it fails
The request won't appear in the project view. It becomes an orphan in the triage inbox with no project context.

### Correct
```
create_request(
  title: "Create users migration",
  description: "...",
  priority: "high",
  project_id: "proj-uuid"
)
```

### Prevention
Always call `list_projects` first to get the `project_id`.

---

## Mistake 2: Missing `milestone_id` when milestone exists

### Wrong
```
// Milestone "Database Schema" already exists for this project
create_request(
  title: "Create users migration",
  description: "...",
  priority: "high",
  project_id: "proj-uuid"
  // milestone_id missing!
)
```

### Why it fails
Request is in the project but not tracked under any milestone. Milestone progress won't reflect this work.

### Correct
```
create_request(
  title: "Create users migration",
  description: "...",
  priority: "high",
  project_id: "proj-uuid",
  milestone_id: "milestone-uuid"
)
```

### Prevention
Call `list_milestones(project_id)` to find the right milestone before creating requests.

---

## Mistake 3: Invalid status transition

### Wrong
```
// Request is in "pending" status
update_request_status(id: "uuid", status: "under_review")
// ERROR: Invalid transition
```

### Why it fails
`pending` → `under_review` is not a valid transition. The state machine requires going through `in_progress` first.

### Correct
```
update_request_status(id: "uuid", status: "in_progress")
// ... work happens ...
update_request_status(id: "uuid", status: "under_review")
```

### Prevention
Always check current status with `get_request` before transitioning. Refer to valid transitions table.

---

## Mistake 4: Creating PR before issue+branch

### Wrong
```
create_request(title: "...", description: "...", priority: "high")
// Developer pushes code to some branch
create_github_pr(request_id: "uuid")
// ERROR: No github link found for this request
```

### Why it fails
`create_github_pr` looks for an existing `request_github_links` entry. Without calling `create_github_issue_branch` first, there's no link.

### Correct
```
create_request(...)
update_request_status("in_progress")
create_github_issue_branch(request_id: "uuid", base_branch: "develop")
// ... developer works and pushes commits ...
create_github_pr(request_id: "uuid")
```

---

## Mistake 5: Marking milestone completed with open requests

### Wrong
```
// Milestone has 3 requests: 2 resolved, 1 in_progress
update_milestone(milestone_id: "uuid", status: "completed")
// Misleading! Work is still in progress
```

### Why it fails
It doesn't error (the API allows it), but it creates false progress reporting. Stakeholders see "completed" but work remains.

### Correct
```
// Verify all requests first
list_milestones(project_id) → check linked requests
// All resolved? Then:
update_milestone(milestone_id: "uuid", status: "completed")
```

---

## Mistake 6: Creating GitHub issue before `in_progress`

### Wrong
```
// Request is still "pending"
create_github_issue_branch(request_id: "uuid")
// Issue+branch created, but request status says "pending"
// Status inconsistency!
```

### Why it fails
The GitHub issue exists, a branch is created, but HOT says the request hasn't started. This confuses tracking.

### Correct
```
update_request_status(id: "uuid", status: "in_progress")
create_github_issue_branch(request_id: "uuid")
```

---

## Mistake 7: Forgetting checklist before starting work

### Wrong
```
create_request(...)
update_request_status("in_progress")
create_github_issue_branch(...)
// ... developer works without clear acceptance criteria ...
// What counts as "done"?
```

### Why it fails
No definition of done. Developer might miss requirements. Review becomes subjective.

### Correct
```
create_request(...)
add_checklist_item(request_id, "Migration created and tested")
add_checklist_item(request_id, "RLS policies implemented")
add_checklist_item(request_id, "Types regenerated")
add_checklist_item(request_id, "Tests passing")
update_request_status("in_progress")
create_github_issue_branch(...)
```

---

## Mistake 8: Not specifying `base_branch`

### Wrong
```
create_github_issue_branch(request_id: "uuid")
// Branch created from repo's default branch (might be "main")
// But your gitflow uses "develop" as base!
```

### Why it fails
If the repo's default branch is `main` but your team works from `develop`, the branch will be based on the wrong commit. PRs will target the wrong branch.

### Correct
```
create_github_issue_branch(
  request_id: "uuid",
  base_branch: "develop"
)
```

---

## Mistake 9: Not using `repo_label` on multi-repo projects

### Wrong
```
// Project has repos: "client" and "backend"
create_github_issue_branch(request_id: "uuid")
// ERROR or creates on wrong repo
```

### Why it fails
With multiple repos, the tool doesn't know which one to use.

### Correct
```
create_github_issue_branch(
  request_id: "uuid",
  repo_label: "backend"
)
```

---

## Mistake 10: Forgetting to resolve request after PR merge

### Wrong
```
create_github_pr(request_id: "uuid")
// PR merged → GitHub issue auto-closed
// But HOT request still shows "under_review"!
```

### Why it fails
GitHub auto-close only affects the GitHub issue. The HOT request status is separate and must be updated manually.

### Correct
```
// After PR is merged:
update_request_status(id: "uuid", status: "resolved")
```

---

## Mistake 11: Starting work without `due_date` or `estimated_hours`

### Wrong
```
create_request(
  title: "Implement notifications",
  description: "...",
  priority: "mid",
  project_id: "proj-uuid",
  milestone_id: "ms-uuid"
  // No due_date, no estimated_hours
)
update_request_status(id: "req-uuid", status: "in_progress")
// Working without deadline or time estimate!
```

### Why it's wrong
- Deadline reminder cron won't fire (it only selects rows where `due_date IS NOT NULL`)
- Team workload view can't calculate capacity (no `estimated_hours`)
- Milestone timeline has gaps — can't visualize when work should finish
- The request is **invisible in the overdue views**, which filter `.not("due_date","is",null)`
- On resolve, the XP is roughly half what the same work would have earned

### Correct
```
create_request(
  title: "Implement notifications",
  description: "...",
  priority: "mid",
  project_id: "proj-uuid",
  milestone_id: "ms-uuid",
  assignee_ids: ["dev-uuid"],
  due_date: "2026-05-25",
  estimated_hours: 16
)
```

**Rule**: `due_date` and `estimated_hours` are API-optional but **required by convention** — set at
creation, never deferred. If the user gave no values, derive them (Mistake 17) rather than omitting them.

---

## Mistake 12: Development request without GitHub integration

### Wrong
```
create_request(
  title: "Add user notifications",
  description: "...",
  priority: "mid",
  category: "nuevo",
  domain: "development",
  project_id: "proj-uuid",
  milestone_id: "ms-uuid"
)
update_request_status(id: "req-uuid", status: "in_progress")
// Developer works directly on a manually created branch
// No GitHub issue, no traceability
update_request_status(id: "req-uuid", status: "resolved")
```

### Why it's wrong
For `domain: "development"` requests, GitHub integration is **mandatory**. Without it:
- No issue to track commits
- No auto-close on merge
- No traceability from request → issue → branch → PR → merge
- Code review happens outside the system

### Correct
```
create_request(domain: "development", ...)
update_request_status("in_progress")
create_github_issue_branch(request_id: "req-uuid", base_branch: "develop")
// ... work, push, checklist ...
create_github_pr(request_id: "req-uuid", body: "...")
// ... merge ...
update_request_status("resolved")
```

---

## Mistake 13: Starting dev request when project has no GitHub repo

### Wrong
```
create_request(domain: "development", project_id: "proj-uuid", ...)
update_request_status("in_progress")
create_github_issue_branch(request_id: "req-uuid")
// ERROR: Project has no linked GitHub repository
```

### Why it's wrong
`create_github_issue_branch` requires the project to have at least one linked GitHub repo. Without it, the tool fails and you're stuck with an `in_progress` request and no branch.

### Correct
```
// BEFORE creating development requests, verify:
// 1. Project exists
// 2. Project has a linked GitHub repo
// If no repo → STOP. Inform user:
//   "Project 'X' has no linked GitHub repository.
//    Add a repo in Project Settings → Integrations before creating development requests."
```

**Rule**: For `domain: "development"`, always verify the project has a GitHub repo BEFORE creating requests. If missing, halt and inform the user.

---

## Mistake 14: Hardcoding your own UUID instead of calling `whoami`

### Wrong
```
// Remembering "my UUID is a1b2c3d4-..." from a previous session
create_request(
  title: "Fix login bug",
  description: "...",
  priority: "high",
  assignee_ids: ["a1b2c3d4-0000-4000-8000-000000000000"]  // stale, hardcoded
)
```

### Why it's wrong
API keys can be reassigned to a different user or rotated. A UUID cached in memory/notes may no longer belong to the caller — silently assigning work to the wrong person.

### Correct
```
whoami() → { id: "current-uuid", role: "developer", ... }

create_request(
  title: "Fix login bug",
  description: "...",
  priority: "high",
  assignee_ids: ["current-uuid"]
)
```

**Rule**: Any time a workflow needs "yourself" — as an assignee or a comment mention — resolve it fresh with `whoami`, every session.

---

## Mistake 15: Simulating project phases with only `depends_on` chains

### Wrong
```
// Trying to represent "Fase 1: Fundación" as a naming convention only
create_milestone(project_id, name: "Fase 1: Database schema")
create_milestone(project_id, name: "Fase 1: Auth", depends_on: "db-milestone")
create_milestone(project_id, name: "Fase 1: Storage", depends_on: "auth-milestone")
// No group_id anywhere — "Fase 1" only exists in the milestone names
```

### Why it fails
`list_milestone_groups(project_id)` returns nothing. There's no way to query "everything in Fase 1" as a unit — you'd have to parse milestone names, which breaks the moment someone renames one.

### Correct
```
create_milestone_group(project_id, name: "Fase 1: Fundación") → group-uuid

create_milestone(project_id, name: "Database schema", group_id: "group-uuid")
create_milestone(project_id, name: "Auth", group_id: "group-uuid", depends_on: "db-milestone")
create_milestone(project_id, name: "Storage", group_id: "group-uuid", depends_on: "auth-milestone")
```

**Rule**: `group_id` (via `create_milestone_group`) is for organizational grouping; `depends_on` is for execution order. Use both together — they're not alternatives to each other.

---

## Mistake 16: Starting work without checking who it's assigned to

### Wrong
```
get_request(id: "req-uuid")
// assignee is someone else, or nobody — doesn't matter, just start
update_request_status(id: "req-uuid", status: "in_progress")
```

### Why it's wrong
You might be starting work nobody asked you to do, or silently taking over someone else's task. Each API key belongs to exactly one user with that user's own permissions — "who's asking" always has a real identity behind it.

### Correct
```
get_request(id: "req-uuid") → assignee info

// Unassigned?
whoami() → { id: "my-uuid" }
// Ask the user: "¿Asigno esta solicitud a vos?"
// If yes:
update_request(id: "req-uuid", assignee_ids: ["my-uuid"])

// Assigned to someone else? Ask before touching it — do not reassign silently.

// Assigned to you already? Proceed straight to in_progress.
```

---

## Mistake 17: Creating a request with no date because the user didn't give one

### Wrong
```
// User: "creá una tarea para arreglar el login"
create_request(
  title: "Fix login bug",
  description: "...",
  priority: "high"
)
// No due_date, no estimated_hours — "the user didn't say, so I left them empty"
```

### Why it's wrong
Leaving them null is not the neutral, honest choice — it is a silent hole in the metrics:

| What breaks | Where |
|-------------|-------|
| Never appears in the overdue list | `getOverdueRequests` / `getProjectHealth` filter `.not("due_date","is",null)` — a task 3 weeks late with no date is simply **not counted as late** |
| Never triggers a reminder | the deadline-reminders cron only selects rows with a `due_date` |
| Never earns the on-time bonus | `ON_TIME_BONUS` (+20) is gated on `due_date IS NOT NULL` |
| Drags down everyone's on-time rate | `on_time_cnt` in `developer_stats` counts only rows with a `due_date`, so the numerator shrinks while the denominator doesn't |
| Roughly halves the XP | completeness multiplier loses `+0.10` (no date) and `+0.15` (no estimate); effort base drops to its 30 XP floor |

The value that "looks deliberate and isn't" is a real risk — but the answer is not a null. It is a
**derived default, announced out loud**, which is visible, attributable and correctable.

### Correct
```
// User gave nothing → derive from priority, estimate from the described scope
create_request(
  title: "Fix login bug",
  description: "...",
  priority: "high",
  assignee_ids: ["carlos-uuid"],   // whoami, since the user named nobody
  due_date: "2026-09-04",          // high → today + 3 business days
  estimated_hours: 6
)

// Then, in the very next line of your reply:
// "Creada REQ-A1B2C3 — asignada a Carlos Rivas, vence 2026-09-04
//  (default de prioridad alta: +3 días hábiles), estimada en 6 h.
//  Decime si ajusto fecha, horas o responsable."
```

### The distinction that matters
- **Fabricating** = inventing a value and presenting it as if the user set it. Still forbidden.
- **Defaulting** = applying a stated rule, saying which rule you applied, and inviting correction in
  the same breath. This is what you do.

**Rule**: same principle applies to `start_date`/`target_date` on milestones — derive `start_date` from
the blocker's `target_date`, and `target_date` from the latest `due_date` of its planned requests.

### Only genuine exception
A throwaway standalone request with no `project_id`, no `milestone_id` and no intention of being
tracked. Anything inside a project or milestone gets all three fields.

---

## Mistake 18: Silence about the GitHub → HOT resolution gap

### Wrong
```
create_github_pr(request_id: "uuid", body: "...")
// PR created, request left at under_review
// ... nothing said to the user about what happens next ...
// PR gets merged days later — request still shows under_review forever,
// because nobody told HOT and nobody told the user they needed to.
```

### Why it's wrong
There's no webhook linking GitHub PR merges back to HOT request status. If the agent doesn't say so out loud, the user assumes it's automatic — because from a GitHub-native workflow, closing an issue on merge feels automatic. It isn't, for the HOT side.

### Correct
```
update_request_status(id: "uuid", status: "under_review")
create_github_pr(request_id: "uuid", body: "...")
// Tell the user explicitly:
// "Dejo esto en under_review con la PR abierta. Avisame cuando se
//  apruebe/mergee y lo paso a resuelto."

// ... later, once the user confirms the merge ...
update_request_status(id: "uuid", status: "resolved")
```

---

## Mistake 19: Milestone status not cascading with its requests

### Wrong
```
// Milestone "Auth module" is still "pending"
update_request_status(id: "req-uuid", status: "in_progress")  // first request in that milestone starts
// Milestone left at "pending" — nobody updated it
// ... days later, all requests in the milestone are "resolved"
// Milestone STILL shows "pending" — nobody checked
```

### Why it's wrong
The milestone progress view is now actively misleading — it looks like nothing has started when work is done, or looks not-started when it's actually finished.

### Correct
```
update_request_status(id: "req-uuid", status: "in_progress")
// This was the first active request in "Auth module" (still pending) →
update_milestone(milestone_id: "auth-milestone-uuid", status: "in_progress")

// ... later, this resolves the last open request in the milestone ...
update_request_status(id: "req-uuid-2", status: "resolved")
// Check: list_milestones(project_id) → all linked requests resolved? →
update_milestone(milestone_id: "auth-milestone-uuid", status: "completed")
```

**Rule**: treat milestone status as something that tracks its requests automatically — check the cascade after every status change on a request that belongs to a milestone, don't wait to be asked.

---

## Mistake 20: Creating a request with nobody assigned

### Wrong
```
// User: "creá la tarea del reporte de ventas"
create_request(
  title: "Reporte de ventas mensual",
  description: "...",
  priority: "mid",
  project_id: "proj-uuid",
  milestone_id: "ms-uuid",
  due_date: "2026-09-10",
  estimated_hours: 8
  // assignee_ids omitted — "someone will pick it up"
)
```

### Why it's wrong
Nobody picks up what no view shows. The consequences are mechanical, not stylistic:

| What breaks | Where |
|-------------|-------|
| Born `pending`, not `assigned` | `create_request` does `status: hasAssignees ? "assigned" : "pending"` — it lands in the triage inbox instead of somebody's queue |
| **Zero XP for anyone, permanently** | `on_request_resolved` bails at `IF v_assignee_count = 0 THEN RETURN NEW`. The trigger fires only on the transition *into* `resolved` — assigning it afterwards never back-pays the XP, the badges or the stats recompute |
| Counts for nobody in performance | `getDeveloperPerformance` builds its whole map from `request_assignees` |
| Invisible in workload | `getTeamWorkload` reads the same junction table, then filters out anyone with a zero total |
| No reminder reaches anyone | the deadline cron builds one notification per (request × assignee) pair — with a date but no assignee, it produces nothing |

An unassigned request is the single most expensive omission available: the work still gets done, and
none of it registers anywhere.

### Correct
```
// The user named someone
list_team() → find "Carlos Rivas" → carlos-uuid

create_request(
  title: "Reporte de ventas mensual",
  description: "...",
  priority: "mid",
  project_id: "proj-uuid",
  milestone_id: "ms-uuid",
  assignee_ids: ["carlos-uuid"],
  due_date: "2026-09-10",
  estimated_hours: 8
)

// The user named nobody → default to the API-key owner
whoami() → { id: "my-uuid", name: "Carlos Rivas" }
create_request(..., assignee_ids: ["my-uuid"])
```

### If the user genuinely wants it unassigned
Honour it — and say what it costs, once:

> "La dejo sin asignar. Ojo: así no suma XP a nadie al resolverse, no aparece en la vista de carga
>  del equipo y el recordatorio de vencimiento no tiene a quién avisar."

**Rule**: `assignee_ids` is decided at `create_request` time and is never empty by default. Rule 13
(check assignment before starting work) is the second line of defence, for requests that arrived from
somewhere else — it is not a licence to create them blank.

---

## Mistake 21: Trying to change the status of a request still in the backlog

### Wrong
```
// Request was created without assignee_ids or due_date → born backlog_state: "backlog"
update_request_status(id: "uuid", status: "in_progress")
```

### Why it fails
`backlog_state` gates `status` unconditionally (SR-15, `ERRCODE HT003`, `supabase/migrations/00117`).
The check runs regardless of which transition is requested — `pending → assigned`, `pending →
in_progress`, all of them, rejected the same way. There is no admin bypass and no way around it except
marking the request `ready` first. See
[backlog-and-readiness.md](backlog-and-readiness.md).

### Correct
```
update_request(id: "uuid", backlog_state: "ready")   // after refining it — see Mistake 22
update_request_status(id: "uuid", status: "in_progress")
```

### Prevention
Before calling `update_request_status` on any request, check `backlog_state` via `get_request` or
`list_requests`. A request created with both `assignee_ids` and `due_date` is born `ready` and never
needs this — see Rule 8/16 in [SKILL.md](../SKILL.md).

---

## Mistake 22: Marking a request `ready` without refining it first

### Wrong
```
// Bulk-clearing a backlog view without filling anything in
list_requests(backlog_state: "backlog") → for each: update_request(id, backlog_state: "ready")
```

### Why it fails
`backlog_state: "ready"` is what makes the request visible on the kanban board and lifts the HT003 gate
— it's supposed to mean "refined enough to work," not "technically allowed to change status now."
Flipping it without filling in `assignee_ids`, `due_date`, `estimated_hours` (and a checklist, if the
work has real steps) just relocates the "incomplete and invisible to metrics" problem: the request is
now on the board, still missing the fields every XP/overdue/workload view reads. See Rule 8/17 in
[SKILL.md](../SKILL.md).

### Correct
```
update_request(
  id: "uuid",
  assignee_ids: ["dev-uuid"],
  due_date: "2026-09-15",
  estimated_hours: 6,
  backlog_state: "ready"
)
add_checklist_item(request_id: "uuid", title: "...")  // if the work has real steps
```

### Prevention
Treat "mark ready" and "refine" as one action, not two. If a backlog request is missing any of the three
fields, fill them in the same call (or immediately before) the `backlog_state: "ready"` flip.

---

## Mistake 23: Blocking a request without a justification note

### Wrong
```
update_request_status(id: "uuid", status: "blocked")
```

### Why it fails
`fn_log_request_status_change` rejects the transition outright (`ERRCODE HT001`) when `new_status =
"blocked"` and no `note` of at least 5 characters was provided. **This is not a warning that gets logged
around** — the status does not change, the whole call fails, exactly like Mistake 21's HT003. The note
also isn't optional context; it's what a future reader (including `get_request_history`) uses to
understand why the request stalled.

### Correct
```
update_request_status(id: "uuid", status: "blocked", note: "esperando credenciales de staging del cliente")
```

### Prevention
Never call `update_request_status(status: "blocked")` without deciding the `note` first. Write what's
blocking it and who/what unblocks it — a 5-character note like `"bloqueado"` clears the DB floor but
tells nobody anything.

---

## Mistake 24: Clearing or changing an already-set `due_date` without a justification note

### Wrong
```
// due_date is currently "2026-09-10"
update_request(id: "uuid", due_date: null)
```

### Why it fails
Same mechanism as Mistake 23, different trigger: `fn_log_request_due_date_change` rejects the update
(`ERRCODE HT002`) when `OLD.due_date` was already set and no `note` (≥5 chars) is provided — whether the
new value is a different date or `null`. Setting a `due_date` for the **first time** (previous value
`null`) never requires a note; only changing or clearing an existing one does.

### Correct
```
update_request(id: "uuid", due_date: null, note: "cliente pausó el proyecto indefinidamente")
update_request(id: "uuid", due_date: "2026-09-20", note: "cliente pidió una semana más para validar el alcance")
```

### Prevention
Before clearing or moving a `due_date` that's already set, have the `note` ready. Check the current
`due_date` with `get_request` if it isn't already known — the mandatory-note decision is based on the
row's current value, not on what the caller assumes it is.

---

## Mistake 25: Starting a request that has no `due_date`

### Wrong
```
// Request has due_date: null
update_request_status(id: "uuid", status: "in_progress")
```

### Why it fails
`trg_request_due_date_required_in_progress` rejects the transition outright (`ERRCODE HT004`,
`supabase/migrations/00127`, REQ-87A849 / #295) when the resulting row would be `in_progress` with
`due_date IS NULL`. Like HT001/HT003, **the whole call fails** — the status does not change, there is no
partial write and no admin bypass. The point is that a request being actively worked on always has a
deadline: without one it's invisible to the overdue views, the deadline reminders and the on-time
metrics, which is exactly the state "en progreso" is supposed to make impossible.

The same trigger also refuses the reverse move — you cannot clear the `due_date` of a request that's
already `in_progress` (see below), and no `note` authorizes it: HT002 asks *why* the date changed, HT004
refuses the resulting state.

### Correct
```
// One call — status and due_date are written in the SAME UPDATE, which is what the gate inspects
update_request_status(id: "uuid", status: "in_progress", due_date: "2026-09-26")
```
```
// Also valid: set the date first, then start it (two calls, same outcome)
update_request(id: "uuid", due_date: "2026-09-26")
update_request_status(id: "uuid", status: "in_progress")
```
```
// WRONG — clearing the date of a request already in_progress
update_request(id: "uuid", due_date: null, note: "cliente pausó el proyecto")
→ rejected, HT004

// Right: move it out of in_progress first
update_request_status(id: "uuid", status: "blocked", note: "cliente pausó el proyecto indefinidamente")
update_request(id: "uuid", due_date: null, note: "cliente pausó el proyecto indefinidamente")
```

### Prevention
Derive the `due_date` from `priority` (critical = today / high +3 / mid +7 / low +14 business days) and
pass it at `create_request` (Rule 8) — a request born with a date never meets this gate. When you're
starting a request that somehow lacks one, decide the date and pass it as the `due_date` param of the
same `update_request_status` call instead of discovering the rejection first. Note that a *backlog*
request with no date reports HT003 (mark it `ready` first), not HT004 — the Ready gate fires first.

---

## Mistake 26: Passing BlockNote JSON to a forum tool

### Wrong
```
create_forum_post(
  title: "Runbook de despliegue",
  content_markdown: '[{"type":"paragraph","content":[{"type":"text","text":"Requisitos","styles":{}}]}]'
)
```

### Why it fails
It doesn't fail loudly — that's the problem. `content_markdown` is a **string of Markdown**, and the
converter will happily parse that JSON as literal text: the post ends up containing one paragraph whose
visible content is `[{"type":"paragraph",...}]`. No error, no warning, a corrupted post.

The forum stores content as BlockNote JSONB, but **the MCP tool surface never exposes it** — not as a
parameter, not in a response. `forum_posts.content` has no DB-level schema (it's JSONB), so there is
nothing to catch a hallucinated block type; a bad shape is stored happily and breaks the web renderer
instead. That's precisely why the Markdown boundary exists
(`packages/shared/src/forum-markdown.ts` is the only place the translation happens).

### Correct
```
create_forum_post(
  title: "Runbook de despliegue",
  content_markdown: "## Requisitos\n\n- Node 22\n- Acceso a Supabase\n"
)
```

### Prevention
Write Markdown. Read Markdown. There is no parameter anywhere in the forum tool surface that accepts
blocks, so if you find yourself constructing `{ "type": ..., "props": ... }`, you've taken a wrong turn.
See [forum-authoring.md](forum-authoring.md) for the exact supported subset.

---

## Mistake 27: Replacing the whole post body just to add a paragraph

### Wrong
```
get_forum_post(slug: "runbook-despliegue-7k2f")
→ { content_markdown: "## Requisitos\n…", content_conversion: { lossy: true, dropped_block_types: ["video"] } }

update_forum_post(
  slug: "runbook-despliegue-7k2f",
  content_markdown: <the markdown just read> + "\n\n## Rollback\n\n1. …"
)
```

### Why it fails
`content_markdown` **replaces** `forum_posts.content` wholesale. When the preceding `get_forum_post`
reported `content_conversion.lossy: true`, the Markdown you just read is a *degraded* copy of the post —
the embedded video is now a text link, the highlighted paragraph lost its background colour, the
underline and the centring are gone. Writing it back makes the degradation permanent. There is no undo
and no version history on `forum_posts.content`.

The web editor can produce `video`/`audio`/`file`/`pageBreak`/`toggleListItem` blocks and
`textColor`/`backgroundColor`/`textAlignment`/`underline` styling. Markdown can represent **none** of
them. `lossy: true` is the converter telling you exactly that.

### Correct
```
update_forum_post(
  slug: "runbook-despliegue-7k2f",
  append_markdown: "## Rollback\n\n1. Revertir el deploy desde el panel\n2. …"
)
```

`append_markdown` converts **only** the new text and concatenates its blocks after the existing ones.
Everything already authored is untouched.

### Prevention
Make `append_markdown` your default for any additive edit, lossy or not — one call, nothing to
mis-transcribe. Reserve `content_markdown` for a rewrite the user actually asked for, and only after
`get_forum_post` reported `lossy: false`.

Note the cosmetic trap that tempts the full replace: round-tripped Markdown separates top-level blocks
with a blank line, so a tight list comes back loose. Same blocks, same render — not a loss, and not
worth a rewrite.

---

## Mistake 28: Expecting the slug to follow the title

### Wrong
```
update_forum_post(slug: "runbook-staging-7k2f", title: "Runbook: despliegue a producción")
→ success

get_forum_post(slug: "runbook-despliegue-a-produccion-7k2f")
→ Post no encontrado o no tienes permiso para verlo.
```

### Why it fails
`generateSlug()` runs **only** inside `create_forum_post`. `update_forum_post` never touches `slug`,
even when `title` changes — deliberately:

- `/foro/{slug}` is the public URL people have already shared and bookmarked.
- `notifications.entity_id` stores the **slug**, not the post id (`lib/forum-notifications.ts`), and
  `getNotificationUrl` builds `/foro/{entity_id}`. A regenerated slug would 404 every notification
  already sent for that post.

### Correct
```
update_forum_post(slug: "runbook-staging-7k2f", title: "Runbook: despliegue a producción")
get_forum_post(slug: "runbook-staging-7k2f")      // the original slug still resolves
// or, immune to the whole question:
get_forum_post(id: "post-uuid")
```

### Prevention
Record the `slug` (and `id`) from the `create_forum_post` response and keep using it for the rest of the
session. Never derive a slug from a title — not even the original title, since the slug carries a random
4-char suffix you cannot reconstruct.

> The web app's `updateForumPost` in `lib/services/requests.ts` *does* regenerate the slug on a title
> change. That's a known bug on the web side. The MCP tools don't replicate it, and shouldn't be
> "aligned" to it.

---

## Mistake 29: Publishing without reviewing the conversion

### Wrong
```
create_forum_post(
  title: "Guía de migraciones",
  content_markdown: "<div class='warning'>Leer primero</div>\n\nVer [la doc][d].\n\n[d]: https://…",
  status: "published"
)
```

### Why it fails
`status` defaults to `"draft"` **on purpose**: the text has just gone through a converter that silently
drops constructs Markdown-to-BlockNote can't map. In the call above, two things were lost before anyone
could see them:

- the `<div>` block vanished (`html_dropped`)
- `[la doc][d]` is a reference-style link — **its visible text vanished too**, leaving `Ver .`
  (`unsupported_markdown_node`, `"linkReference"`)

And because `status: "published"` was passed, `post_published` notifications already went out pointing
at the broken post.

### Correct
```
create_forum_post(title: "Guía de migraciones", content_markdown: "…")   // draft (the default)
→ { slug: "guia-de-migraciones-3x9p", conversion: { warnings: [...] } }   // ← read these

get_forum_post(slug: "guia-de-migraciones-3x9p")
→ content_markdown: "…"   // ← read this: is it what you meant?
   content_conversion: { lossy: false, warnings: [] }

update_forum_post(slug: "guia-de-migraciones-3x9p", status: "published")
```

### Prevention
Treat the draft default as a mandatory review step, not a formality. Two habits cover it:

1. **Read `conversion.warnings`** on every write — a non-empty array means your Markdown didn't fully
   land.
2. **Read the post back with `get_forum_post`** before publishing, and look at `content_markdown`.

Also: use inline links (`[text](url)`), never reference links; strip HTML; and never start the Markdown
with `---` on line 1 (it's rejected as frontmatter). There are no `publish_forum_post`/`unpublish_forum_post`
tools — `update_forum_post(status:)` is both.

---

## Mistake 30: Inventing a category name

### Wrong
```
create_forum_post(
  title: "Runbook de despliegue",
  content_markdown: "…",
  category_names: ["Runbooks"]        // sounds right, doesn't exist
)
→ No existen las categorías: Runbooks. Categorías válidas: Anuncios, Debate, Preguntas, Tutoriales.
```

### Why it fails
**Categories are read-only through MCP.** There is no `create_forum_category` and no delete — the
taxonomy is curated by humans in the app. The error above is the tool's *only* guardrail against a
hallucinated category, and it exists because the alternative (silently ignoring the name) would produce
an uncategorised post nobody notices.

### Correct
```
list_forum_categories()
→ { total: 4, categories: [
    { id: "cat-anuncios",   name: "Anuncios",   post_count: 12 },
    { id: "cat-debate",     name: "Debate",     post_count: 0  },
    { id: "cat-preguntas",  name: "Preguntas",  post_count: 5  },
    { id: "cat-tutoriales", name: "Tutoriales", post_count: 3  }
  ]}

create_forum_post(title: "…", content_markdown: "…", category_names: ["Tutoriales"])
```

### Prevention
Call `list_forum_categories` before any `category_names`/`category_ids`. `post_count` is there precisely
so you can tell a real, in-use category from a dormant one. If none fits, say so out loud and pick the
closest — don't retry the error with another guess, and don't ask the tool to create one.

Two more traps on the same parameter:

- `update_forum_post` takes **`category_ids` only** — no `category_names`. Resolve names to UUIDs first.
- `category_ids` on `update_forum_post` **replaces the whole list** (delete-then-insert). Passing one id
  drops the rest; `[]` clears them all. Always send the complete intended set.

---

## Mistake 31: Assuming an admin can read another author's draft

### Wrong
```
// You're an admin, reviewing a colleague's unpublished post
get_forum_post(id: "other-authors-draft-uuid")
→ Post no encontrado o no tienes permiso para verlo.
// …retried with the slug, then reported the tool as broken
```

### Why it fails
It's not broken. `forum.ts` replicates the RLS policies in
`supabase/migrations/00039_forum_module.sql` **literally**, including their asymmetry:

| Operation | Policy | Admin branch? |
|---|---|---|
| SELECT | `forum_posts_select_published_or_own` | **No** — published posts, or your own |
| UPDATE | `forum_posts_update_author_or_admin` | **Yes** |
| DELETE | `forum_posts_delete_author_or_admin` | **Yes** |

So **an admin cannot read another author's draft, but can publish or delete it**:

```
get_forum_post(id: "other-authors-draft-uuid")                      → not found
update_forum_post(id: "other-authors-draft-uuid", status: "published") → success
delete_forum_post(id: "other-authors-draft-uuid", confirm: true)       → success
```

Surprising, faithful to the DB, and deliberately not "fixed" in the tool layer. The not-found message is
also **identical** to the one for a nonexistent id, on purpose — otherwise a caller could enumerate post
UUIDs by diffing error messages.

### Correct
Accept the gate. If an admin needs to review a draft, the **author** publishes it or pastes the content.
Don't retry the read, don't try `slug` instead of `id`, don't report it as a bug.

### Prevention
The same floor hides drafts from listing, in a way that's easy to misread:

```
list_forum_posts(status: "draft")
→ { status_filter_coerced: true, posts: [...only published ones...] }
```

`list_forum_posts` ORs `status.eq.published,author_id.eq.<you>` into every query, and asking for
`status: "draft"`/`"all"` without being self-scoped (`tab: "mine"`, or `author_id` = your own id)
silently coerces the filter to `published` and sets `status_filter_coerced: true`. **Check that flag**
before telling the user there are no drafts. To see your own:

```
list_forum_posts(tab: "mine", status: "all")
```

---

## Quick Reference: Correct Order

**Working an existing request** (already created — the most common flow):
```
1. get_request / list_requests            ← Find the request
2. Check assignment                       ← Yours? proceed. Unassigned? ask + whoami. Someone else's? ask.
3. update_request_status("in_progress")   ← From whatever the current valid status is
   → No due_date on the request? pass `due_date` in this same call (HT004, Mistake 25)
   → Cascade: milestone still "pending"? move it to "in_progress" too
4. domain = "development"?                ← Verify GitHub repo linked, STOP if missing
   → create_github_issue_branch           ← Check out the branch, THEN start
5. Do the work (checklist + comments as you go)
6. update_request_status("under_review") + create_github_pr
   → TELL THE USER: no auto-link GitHub→HOT, you'll resolve it once told the merge happened
7. User confirms merge → update_request_status("resolved")
   → Cascade: last unresolved request in its milestone? move milestone to "completed"
```

**Development requests — planning/creation** (GitHub mandatory once started):
```
0. whoami                                 ← Resolve your own id (only if self-assigning)
1. list_projects                          ← Get project context
2. Verify project has GitHub repo         ← STOP if missing
3. list_milestones                        ← Find/verify milestone
4. create_request (IDs + assignee_ids + due_date + estimated_hours) ← Never blank: name→list_team or whoami; date from priority
5. add_checklist_item (×N)                ← Only if the task has real steps to decompose
6. → continue with "Working an existing request" above from step 2
```

**Design / Global requests** (no GitHub):
```
0. whoami                                 ← Resolve your own id (only if self-assigning)
1. list_projects                          ← Get project context
2. list_milestones                        ← Find/verify milestone
3. create_request (IDs + assignee_ids + due_date + estimated_hours) ← Never blank: name→list_team or whoami; date from priority
4. add_checklist_item (×N)                ← Only if the task has real steps to decompose
5. → continue with "Working an existing request" above from step 2 (no GitHub step)
```

**Planning multiple milestones as a phase**:
```
1. whoami                                 ← Resolve your own id
2. list_projects                          ← Get project context
3. create_milestone_group(project_id, name: "Fase N")  ← Organizational container
4. create_milestone (×N, with group_id + depends_on as needed)
5. create_request per milestone (as above)
```

**Publishing a forum post** (Markdown only, draft first — Mistakes 26–31):
```
0. whoami                                 ← Check api_key_scopes has forum:write, and your role
1. list_forum_categories                  ← Real names + post_count. Never invent one
2. create_forum_post (content_markdown)   ← Lands as DRAFT by default. Read conversion.warnings
3. get_forum_post(slug)                   ← Verify content_markdown + content_conversion.lossy
4. update_forum_post(append_markdown)     ← Additive edits. NEVER content_markdown when lossy: true
5. update_forum_post(status: "published")  ← This is the publish tool; there is no other
6. add_forum_comment                      ← Mentions as @[Nombre](uuid) IN the text, ids from list_team
```
