# HOT MCP Tool Catalog

Complete reference for all 25 HOT Platform MCP tools.

---

## Identity Tools

### `whoami`

Get information about the currently authenticated user — the API key owner. Read-only, self-scoped.

**Parameters**: None

**Example**:
```
whoami()
```

**Returns**:
```json
{
  "id": "user-uuid",
  "name": "Ana García",
  "email": "ana.garcia@ejemplo.com",
  "role": "admin",
  "avatar_url": "https://...",
  "api_key_scopes": ["requests:read", "requests:write", "..."]
}
```

**Important**: Unlike every other tool in this catalog, `whoami` requires **no scope** — any valid, non-revoked, non-expired API key can call it, regardless of which scopes it was granted. It's equivalent to a "GET /me" endpoint.

**Use when**:
- Auto-assigning a newly created request to yourself (`assignee_ids: [whoami().id]`) instead of asking the user for their UUID
- Self-mentioning in a comment (`@[Name](uuid)`)
- Checking your own `role` before calling a role-gated tool (`create_milestone` and `update_milestone` require `admin` or `developer`)
- Any time you'd otherwise reuse a UUID cached from a previous session — API keys can be reassigned or rotated, so always resolve fresh

---

## Reading Tools

### `list_projects`

List all projects. Admins see all; others see projects where they are member or creator.

**Parameters**: None

**Example**:
```
list_projects()
```

**Returns**: Array of projects with `id`, `name`, `status`, `created_at`, and member info.

**Use when**: Starting any workflow — you need `project_id` for most operations.

---

### `list_requests`

List requests with optional filters and pagination.

**Parameters**:

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `status` | enum | `"all"` | `all`, `pending`, `assigned`, `in_progress`, `blocked`, `under_review`, `resolved`, `cancelled` |
| `priority` | enum | `"all"` | `all`, `critical`, `high`, `mid`, `low` |
| `category` | enum | `"all"` | `all`, `bug`, `mejora`, `nuevo` |
| `domain` | enum | `"all"` | `all`, `development`, `design`, `global` |
| `backlog_state` | enum | `"all"` | `all`, `backlog`, `ready` — SR-4/SR-15 readiness axis, orthogonal to `status`. See [backlog-and-readiness.md](backlog-and-readiness.md) |
| `project_id` | UUID | — | Filter by project UUID |
| `assignee_id` | UUID | — | Filter by assignee UUID |
| `creator_id` | UUID | — | Filter by creator UUID |
| `search` | string | — | Text search on title, description, and request code (REQ-XXXXXX) |
| `sort_by` | enum | `"created_at"` | `created_at`, `due_date`, `priority`, `updated_at` |
| `sort_order` | enum | `"desc"` | `asc`, `desc` |
| `view` | enum | `"all"` | `all`, `active` (non-terminal), `mine`, `closed` (resolved/cancelled) |
| `page` | integer | `1` | Page number (1-based) |
| `per_page` | integer | `20` | Results per page (max 50) |

**Response includes** (per result): `code` (e.g., `REQ-535CD5`, derived from the request UUID),
`backlog_state`, `status_changed_at`, `age_days` (days since `created_at`), `days_in_status` (days since
`status_changed_at`), and `github` (issue/branch/PR state, `null` if none linked).

**Example**:
```
list_requests(project_id: "uuid", view: "active")                // All active in a project
list_requests(assignee_id: "uuid", status: "in_progress")        // My in-progress work
list_requests(search: "REQ-535CD5")                               // Find by request code
list_requests(project_id: "uuid", domain: "development", sort_by: "due_date", sort_order: "asc")
list_requests(category: "bug", priority: "high")                  // High-priority bugs
list_requests(creator_id: "uuid", view: "active")                 // Requests I created
list_requests(status: "blocked")                                   // Find bottlenecks
list_requests(backlog_state: "backlog")                            // What needs refinement before it can move
```

**Use when**: Checking project status, finding bottlenecks, reviewing open work, listing requests by project/assignee/creator.

---

### `list_stale_requests`

Requests that have exceeded their aging (total age since creation) or time-in-status (staleness)
thresholds. Thresholds are per-project (`aging_warning_days`, `aging_critical_days`,
`stale_status_days` on `projects`, falling back to a global default when unset), unless `days` is
passed to override both axes uniformly. Excludes `resolved`/`cancelled` requests — once terminal,
`status_changed_at` is frozen and "stuck in status" no longer applies.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|--------------|
| `days` | integer | No | Override: flag whenever total age OR time in current status exceeds this many days, ignoring per-project thresholds |
| `project_id` | UUID | No | Restrict the scan to a single project |
| `page` | integer | No (default: 1) | Page number over the flagged results |
| `per_page` | integer | No (default: 20, max 50) | Flagged results per page |

**Example**:
```
list_stale_requests()                          // Everything past its project's own thresholds
list_stale_requests(days: 14)                   // Uniform 14-day threshold, ignoring per-project config
list_stale_requests(project_id: "proj-uuid")    // Scoped to one project
```

**Returns**: `{ total, page, per_page, results }` — each result has `days_since_created`,
`days_in_status`, `aging_level` (`ok`/`warning`/`critical`), `stale_level` (`ok`/`stale`), sorted worst-
offender first (whichever axis is furthest past its threshold).

**Use when**: Triaging what's actually stuck, not just what's technically still open — a request can be
`in_progress` and look fine on `list_requests` while sitting untouched for weeks.

---

### `get_request`

Full details of a single request including assignees, project, and optionally the activity log.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | UUID | Yes | Request UUID |
| `include_activity` | boolean | No (default: false) | Include activity log (comments, status changes, assignments) AND `status_log` (see below) |

**Response includes**: `backlog_state`, `status_changed_at`, `age_days` (days since `created_at`),
`days_in_status` (days since `status_changed_at`), and `github` (issue/branch/PR state, `null` if none
linked) — always present, regardless of `include_activity`.

**With `include_activity: true`**, two additional arrays are added:
- `activity` — the human-readable comment-thread feed (comments, `"Cambió el estado de X a Y"` system
  entries, assignment notices)
- `status_log` — the raw `request_status_log` rows: `{ old_status, new_status, changed_at, changed_by,
  note }`. This is status-only and lighter-weight than `get_request_history`; it does NOT include
  `due_date` changes or the `time_in_status` breakdown — use `get_request_history` when you need those.

**Example**:
```
get_request(id: "uuid-here", include_activity: true)
```

**Use when**: Need full context before making changes, reviewing history.

---

### `get_request_history`

Merged audit history of a request: every `request_status_log` row and every `request_due_date_log` row,
combined into one newest-first feed, each entry with its author and justification note. Also computes a
`time_in_status` breakdown — how long the request has spent in each status it has passed through,
including the current one (still open, so its `duration_days` keeps growing between calls). This is the
MCP equivalent of the app's `getRequestChangeLog` (SR-2) — same merge criterion, same sort order.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|--------------|
| `request_id` | UUID | Yes | Request UUID |

**Example**:
```
get_request_history(request_id: "uuid-here")
```

**Returns**:
```json
{
  "request_id": "uuid",
  "code": "REQ-535CD5",
  "title": "...",
  "current_status": "blocked",
  "status_changed_at": "2026-09-08T14:30:00Z",
  "history": [
    {
      "kind": "status",
      "old_status": "in_progress",
      "new_status": "blocked",
      "changed_at": "2026-09-08T14:30:00Z",
      "changed_by": { "id": "uuid", "name": "Carlos Rivas" },
      "note": "esperando credenciales de staging del cliente"
    },
    {
      "kind": "due_date",
      "old_due_date": "2026-09-05",
      "new_due_date": "2026-09-12",
      "changed_at": "2026-09-07T10:00:00Z",
      "changed_by": { "id": "uuid", "name": "Carlos Rivas" },
      "note": "cliente pidió una semana más para validar el alcance"
    }
  ],
  "time_in_status": [
    { "status": "pending", "entered_at": "2026-09-01T09:00:00Z", "exited_at": "2026-09-01T09:15:00Z", "duration_days": 0, "current": false },
    { "status": "assigned", "entered_at": "2026-09-01T09:15:00Z", "exited_at": "2026-09-02T11:00:00Z", "duration_days": 1, "current": false },
    { "status": "in_progress", "entered_at": "2026-09-02T11:00:00Z", "exited_at": "2026-09-08T14:30:00Z", "duration_days": 6, "current": false },
    { "status": "blocked", "entered_at": "2026-09-08T14:30:00Z", "exited_at": null, "duration_days": 2, "current": true }
  ]
}
```

**Use when**: Answering "why is this stuck" — a request in `blocked` with no note tells you nothing; this
tool pairs every transition with the note that justified it (mandatory for blocks and for changing/
clearing an already-set `due_date` — see [backlog-and-readiness.md](backlog-and-readiness.md)) and shows
exactly where the time went. Prefer this over `get_request(include_activity: true)`'s `status_log` when
you also need `due_date` history or the time-in-status breakdown.

---

### `list_milestones`

List milestones for a project, including linked requests and dependencies.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `project_id` | UUID | Yes | Project UUID |
| `status` | enum | No | Filter: `pending`, `in_progress`, `completed`, `skipped` |

**Example**:
```
list_milestones(project_id: "uuid-here")
list_milestones(project_id: "uuid-here", status: "in_progress")
```

**Use when**: Planning work, checking milestone progress, finding next milestone to start.

---

### `list_milestone_groups`

List milestone groups for a project — the organizational containers that milestones can be assigned to via `group_id`.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `project_id` | UUID | Yes | Project UUID |

**Example**:
```
list_milestone_groups(project_id: "uuid-here")
```

**Use when**: Verifying a project's phase structure, finding a `group_id` to assign a new milestone to, checking what groups already exist before creating a duplicate.

---

### `list_team`

List team members.

**Parameters**: None

**Example**:
```
list_team()
```

**Returns**: Array of team members with `id`, `name`, `role`, `email`.

**Use when**: Need UUIDs for `assignee_ids` or `@[Name](uuid)` mentions in comments.

---

### `get_checklist`

Get all checklist items for a request, ordered by sort order.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `request_id` | UUID | Yes | Request UUID |

**Example**:
```
get_checklist(request_id: "uuid-here")
```

**Returns**: Array of items with `id`, `title`, `is_complete`, `sort_order`.

**Use when**: Checking progress, verifying all criteria met before closing.

---

## Creating Tools

### `create_request`

Create a new HOT platform request. The API key owner becomes the creator.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | Yes | Request title (max 200 chars) |
| `description` | string | Yes | Detailed description |
| `priority` | enum | Yes | `critical` (P0, today), `high` (P1, +3), `mid` (P2, +7), `low` (P3, +14 business days). No API default — if the user didn't state one, convention default is `mid` (P2) |
| `category` | enum | No (default: `"nuevo"`) | `bug`, `mejora`, `nuevo` |
| `domain` | enum | No (default: `"development"`) | `development`, `design`, `global` |
| `project_id` | UUID | No | Link to project |
| `milestone_id` | UUID | No | Link to milestone (requires `project_id`) |
| `assignee_ids` | UUID[] | API: No — **convention: YES** | Assign to team members. Named person → `list_team`; nobody named → `whoami`. **Never empty** |
| `due_date` | string | API: No — **convention: YES** | Due date `YYYY-MM-DD`. No value given → derive from priority: critical = today, high +3, mid +7, low +14 business days |
| `estimated_hours` | number | API: No — **convention: YES** | Estimated hours (> 0). No value given → estimate from the described scope |
| `ready` | boolean | No | SR-4 readiness override. Omit in the normal case — `backlog_state` is then derived: `ready` when created with BOTH `assignee_ids` and `due_date`, `backlog` otherwise. Pass explicitly only to force one state regardless of that criterion. See [backlog-and-readiness.md](backlog-and-readiness.md) |

> ⛔ The last three are optional in the *schema* and mandatory in *practice*. Omitting them produces a
> request that earns zero XP, counts for nobody in the workload and performance views, never appears
> in the overdue list, and triggers no reminder. See
> [common-mistakes.md → Mistakes 17 and 20](common-mistakes.md).

**Example — Standalone request** (user gave no assignee, no date, no estimate):
```
whoami() → { id: "my-uuid", name: "Carlos Rivas" }

create_request(
  title: "Fix login timeout on mobile",
  description: "Users on iOS report session expiring after 5 min",
  priority: "high",
  category: "bug",
  assignee_ids: ["my-uuid"],   // nobody named → the API-key owner
  due_date: "2026-09-04",       // high → today + 3 business days
  estimated_hours: 4
)
// Then say so: "…asignada a Carlos Rivas, vence 2026-09-04
//               (default de prioridad alta), estimada en 4 h. Decime si ajusto."
```

**Example — Linked to project + milestone**:
```
create_request(
  title: "Create users table migration",
  description: "PostgreSQL migration for users table with RLS",
  priority: "high",
  category: "nuevo",
  project_id: "proj-uuid",
  milestone_id: "milestone-uuid",
  assignee_ids: ["dev-uuid"],
  due_date: "2026-05-20",
  estimated_hours: 4
)
```

**Important**:
- `milestone_id` requires `project_id` — cannot link to milestone without project
- `category` affects GitHub branch prefix when `create_github_issue_branch` is called later
- **Initial status depends on the assignee**: the tool does `status: hasAssignees ? "assigned" : "pending"`.
  Pass `assignee_ids` and the request lands in that person's queue as `assigned`; omit it and it sits in
  the triage inbox as `pending`
- Only the **first** id in `assignee_ids` is mirrored into the legacy `requests.assignee_id` column; all
  of them go into the `request_assignees` junction table, which is what every metric actually reads
- **A request born `backlog_state: "backlog"` cannot have its `status` changed** (`update_request_status`
  will be rejected, `ERRCODE HT003`) until `update_request(id, backlog_state: "ready")` is called first —
  see [backlog-and-readiness.md](backlog-and-readiness.md). Passing both `assignee_ids` and `due_date`
  here avoids this entirely.
- **A request created without a `due_date` also cannot later be moved to `in_progress`** without one
  (`ERRCODE HT004`) — `update_request_status` will demand the `due_date` param. Passing `due_date` at
  creation (Rule 8) avoids both gates at once.

---

### `create_milestone`

Create a new milestone in a project. Only admin and developer roles.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `project_id` | UUID | Yes | Project UUID |
| `name` | string | Yes | Milestone name (max 200 chars) |
| `description` | string | No | Description (max 1000 chars) |
| `start_date` | string | No | Start date `YYYY-MM-DD` |
| `target_date` | string | No | Target date `YYYY-MM-DD` |
| `depends_on` | UUID | No | Milestone dependency — this milestone waits for the other |
| `group_id` | UUID | No | Milestone group this milestone belongs to (from `create_milestone_group`/`list_milestone_groups`) |
| `status` | enum | No (default: `"pending"`) | `pending`, `in_progress`, `completed`, `skipped` |

**Example — Independent milestone**:
```
create_milestone(
  project_id: "proj-uuid",
  name: "Database Schema",
  start_date: "2026-05-15",
  target_date: "2026-05-22"
)
```

**Example — Dependent milestone**:
```
create_milestone(
  project_id: "proj-uuid",
  name: "API Endpoints",
  start_date: "2026-05-22",
  target_date: "2026-06-01",
  depends_on: "schema-milestone-uuid"
)
```

**Example — Grouped milestone**:
```
create_milestone(
  project_id: "proj-uuid",
  name: "Auth module",
  group_id: "fase1-group-uuid"
)
```

**Important**:
- Use `depends_on` to create sequential chains
- Use `group_id` to organize milestones into a phase/container (see `create_milestone_group`) — independent of `depends_on`, the two can be combined
- Parallel milestones = no `depends_on` between them
- `start_date` and `target_date` are optional at the API level but **required by convention** when planning real work — without them the timeline view has gaps and the Gantt has nothing to draw. Use the user's values; if they gave none, derive `start_date` from today or the blocker's `target_date`, and `target_date` from the latest `due_date` of the milestone's planned requests, then state the derivation in one correctable line.

---

### `create_milestone_group`

Create a new milestone group — an organizational container for milestones within a project (e.g. "Fase 1: Fundación").

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `project_id` | UUID | Yes | Project UUID |
| `name` | string | Yes | Group name (max 200 chars) |
| `description` | string | No | Description (max 2000 chars) |

**Example**:
```
create_milestone_group(
  project_id: "proj-uuid",
  name: "Fase 1: Fundación",
  description: "DB schema, auth, storage — foundational work before feature phases"
)
```

**Use when**: Planning a project with distinct phases/releases and you want them queryable as a unit via `list_milestone_groups`, not just inferable from milestone names.

**Important**: Grouping is purely organizational — it does not affect `depends_on` execution order. A milestone can have both a `group_id` and a `depends_on` pointing outside its group.

---

## Updating Tools

### `update_request_status`

Move a request through the status state machine.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | UUID | Yes | Request UUID |
| `status` | enum | Yes | Target status |
| `note` | string | Mandatory when `status: "blocked"` (5-500 chars) | Justification note. Ignored for every other transition |
| `due_date` | string | Mandatory when `status: "in_progress"` **and** the request has no `due_date` yet | Due date set atomically with the status change. Same format as `update_request`'s `due_date` (bare `YYYY-MM-DD` = END of that day in America/Bogota, UTC-5; full ISO-8601 with offset stored verbatim). Ignored for every other transition |

**Valid transitions**:

| From | Allowed targets |
|------|----------------|
| `pending` | `assigned`, `in_progress`, `cancelled` |
| `assigned` | `in_progress`, `cancelled` |
| `in_progress` | `under_review`, `blocked`, `resolved`, `cancelled` |
| `under_review` | `in_progress`, `resolved`, `cancelled` |
| `blocked` | `in_progress`, `cancelled` |
| `resolved` | (terminal — no transitions) |
| `cancelled` | `pending` (reopen) |

**Example**:
```
update_request_status(id: "uuid", status: "in_progress")                       // request already has a due_date
update_request_status(id: "uuid", status: "in_progress", due_date: "2026-09-26")  // request had none — set both in one call
update_request_status(id: "uuid", status: "blocked", note: "esperando credenciales de staging del cliente")
```

**Important — three independent gates, all of them reject the whole call, not a partial write**:
- **Invalid transitions** (skipping states) return a plain error. Always check current status first.
- **`backlog_state` gate (`ERRCODE HT003`)**: if the request's `backlog_state` is still `"backlog"`, this
  call is rejected regardless of which transition was requested. `update_request(id, backlog_state:
  "ready")` first. See [backlog-and-readiness.md](backlog-and-readiness.md).
- **Note gate (`ERRCODE HT001`)**: transitioning to `"blocked"` without a `note` of at least 5 characters
  is rejected outright — the status does not change. Not a warning.
- **Due-date gate (`ERRCODE HT004`)**: transitioning INTO `"in_progress"` while the request has no
  `due_date` and none is supplied in the same call is rejected outright — no work starts without a
  deadline (REQ-87A849 / #295, `supabase/migrations/00127`, no admin bypass). Pass `due_date` and both
  columns are written in the *same* `UPDATE`, so the gate sees the new date. Two separate calls
  (`update_request(due_date)` then `update_request_status`) also work, but the one-call form is the
  correct one. See [backlog-and-readiness.md](backlog-and-readiness.md).

> `note` and `due_date` cannot be passed in the **same** `update_request_status` call — the underlying
> RPC refuses the combination outright (the due-date log trigger consumes the change note before the
> status log can read it). In practice they never need to coexist: `note` is only required entering
> `blocked`, `due_date` only entering `in_progress`.

---

### `update_request`

Update fields of an existing request. Does NOT change status — use `update_request_status` for that. At least one field must be provided. Also the only way to move a request between `backlog` and `ready`.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | UUID | Yes | Request UUID |
| `title` | string | No | New title (max 200 chars) |
| `description` | string | No | New description |
| `priority` | enum | No | `critical` (P0), `high` (P1), `mid` (P2), `low` (P3). Changing to `critical` does NOT retroactively pull `due_date` in — update it explicitly if the new urgency should too |
| `category` | enum | No | `bug`, `mejora`, `nuevo` |
| `domain` | enum | No | `development`, `design`, `global` |
| `due_date` | string/null | No | `YYYY-MM-DD` or `null` to remove. Requires `note` if a `due_date` was already set (see below). `null` is **rejected outright** (`ERRCODE HT004`) while the request's `status` is `in_progress` — no note can authorize it |
| `estimated_hours` | number/null | No | Hours > 0 or `null` to remove |
| `assignee_ids` | UUID[] | No | Replace all assignees. Empty array `[]` removes all. |
| `backlog_state` | enum | No | `"backlog"` or `"ready"` — SR-4/SR-15 readiness axis, orthogonal to `status`. `"backlog"` is only accepted while the request's current `status` is still `pending`/`assigned`. See [backlog-and-readiness.md](backlog-and-readiness.md) |
| `note` | string | Mandatory when changing/clearing an already-set `due_date` (5-500 chars) | Justification note. Ignored if `due_date` isn't part of the call |

> This is the tool that **retro-fits** a request created without a date or an assignee. Worth knowing:
> filling in `due_date` later fully restores the overdue views, the reminders and the on-time counters.
> Filling in `assignee_ids` later does **not** restore XP if the request is already `resolved` — the
> award trigger fires only on the transition into `resolved` and never runs again. Fix open requests
> before they close; a resolved one with no assignee is XP that cannot be recovered.
> `update_request` also refuses to touch a request in a terminal status (`resolved`/`cancelled`).

**Example — Update tracking fields**:
```
update_request(
  id: "uuid",
  due_date: "2026-06-01",
  estimated_hours: 16
)
```

**Example — Change priority and assignees**:
```
update_request(
  id: "uuid",
  priority: "high",
  assignee_ids: ["dev-1-uuid", "dev-2-uuid"]
)
```

**Example — Change an already-set due date (requires `note`)**:
```
update_request(id: "uuid", due_date: "2026-09-20", note: "cliente pidió una semana más para validar el alcance")
```
Omitting `note` here fails with `ERRCODE HT002` — the DB rejects the entire update. Setting a `due_date`
that was previously `null` never requires a note.

**Cannot clear the `due_date` of an `in_progress` request** (REQ-87A849 / #295):
```
// status is "in_progress"
update_request(id: "uuid", due_date: null, note: "cliente pausó el proyecto")
→ rejected, ERRCODE HT004 — "Una solicitud En progreso necesita una fecha límite."
```
The `note` doesn't help here: HT002 asks *why* the date moved, HT004 refuses the resulting state
outright. An `in_progress` request can never be left without a deadline. Move it out of `in_progress`
first (`update_request_status(id, "blocked" | "under_review" | "cancelled", ...)`), or just change the
date instead of clearing it. Legacy rows already sitting in `in_progress` with no `due_date` are not
broken by this — the gate only fires on a genuine `status`/`due_date` change, so they can still be
reprioritized, reassigned or resolved, and can be fixed forward at any time by simply setting a date.

**Example — Mark a refined backlog request ready**:
```
update_request(id: "uuid", backlog_state: "ready")
```
Do this only after `assignee_ids`, `due_date` and `estimated_hours` are all filled in — see
[backlog-and-readiness.md](backlog-and-readiness.md).

**Activity log**: All changes logged automatically with human-readable description.

**Use when**: Updating tracking fields (due_date, estimated_hours), reassigning, changing priority/category/domain, editing title/description, or flipping `backlog_state`.

---

### `update_milestone`

Update milestone fields or status. Only admin and developer roles.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `milestone_id` | UUID | Yes | Milestone UUID |
| `name` | string | No | New name |
| `description` | string/null | No | New description (null to remove) |
| `status` | enum | No | `pending`, `in_progress`, `completed`, `skipped` |
| `start_date` | string/null | No | `YYYY-MM-DD` or null to remove |
| `target_date` | string/null | No | `YYYY-MM-DD` or null to remove |
| `depends_on` | UUID/null | No | New dependency or null to remove |
| `group_id` | UUID/null | No | New milestone group, or null to ungroup |
| `sort_order` | integer | No | Display order |

**Example**:
```
update_milestone(milestone_id: "uuid", status: "completed")
update_milestone(milestone_id: "uuid", target_date: "2026-06-15")
update_milestone(milestone_id: "uuid", group_id: "fase2-group-uuid")  // move to another group
update_milestone(milestone_id: "uuid", group_id: null)  // ungroup
```

---

### `update_milestone_group`

Rename or redescribe an existing milestone group.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | UUID | Yes | Group UUID |
| `name` | string | No | New name (max 200 chars) |
| `description` | string/null | No | New description (max 2000 chars) or null to remove |

**Example**:
```
update_milestone_group(id: "uuid", name: "Fase 1: Fundación (revisada)")
```

---

### `delete_milestone_group`

Delete a milestone group.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | UUID | Yes | Group UUID to delete |

**Example**:
```
delete_milestone_group(id: "uuid")
```

**Important**: Milestones inside the group are **not** deleted — they're only ungrouped (`group_id` set to null). Safe to call without first moving milestones out.

---

### `link_milestone`

Link or unlink a request to/from a milestone.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `request_id` | UUID | Yes | Request UUID |
| `milestone_id` | UUID/null | Yes | Milestone UUID or `null` to unlink |

**Example**:
```
link_milestone(request_id: "req-uuid", milestone_id: "milestone-uuid")
link_milestone(request_id: "req-uuid", milestone_id: null)  // unlink
```

**Use when**: Request was created without milestone and needs to be linked later, or needs to move to a different milestone.

---

### `add_checklist_item`

Add acceptance criteria to a request.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `request_id` | UUID | Yes | Request UUID |
| `title` | string | Yes | Item text |

**Example**:
```
add_checklist_item(request_id: "uuid", title: "Migration created and tested locally")
add_checklist_item(request_id: "uuid", title: "RLS policies implemented")
add_checklist_item(request_id: "uuid", title: "Types regenerated")
add_checklist_item(request_id: "uuid", title: "Unit tests passing")
```

**Best practice**: Add ALL checklist items before starting work. They are the definition of done.

---

### `update_checklist_item`

Mark a checklist item as complete/incomplete or update its title.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | UUID | Yes | Checklist item UUID |
| `is_complete` | boolean | No | true=done, false=incomplete |
| `title` | string | No | New title |

At least one of `is_complete` or `title` must be provided.

**Example**:
```
update_checklist_item(id: "item-uuid", is_complete: true)
```

---

### `delete_checklist_item`

Remove a checklist item from a request.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | UUID | Yes | Checklist item UUID |
| `request_id` | UUID | Yes | Parent request UUID |

**Example**:
```
delete_checklist_item(id: "item-uuid", request_id: "req-uuid")
```

**Use when**: A checklist item was created by mistake or acceptance criteria changed before work started. Prefer this over leaving stale/incorrect items — they're the definition of done and reviewers rely on them being accurate.

---

### `add_comment`

Add a comment to a request. Supports @mentions.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `request_id` | UUID | Yes | Request UUID |
| `content` | string | Yes | Comment text |

**Mention syntax**: `@[Display Name](user-uuid)`

**Example**:
```
add_comment(
  request_id: "uuid",
  content: "API endpoints done. Waiting on @[Juan Perez](user-uuid) for design review."
)
```

**Use when**: Progress updates, decisions, blockers, questions.

---

## GitHub Integration Tools

### `create_github_issue_branch`

Create a GitHub issue and branch for a HOT request. Requires user to have GitHub connected and project to have a linked repo.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `request_id` | UUID | Yes | Request UUID |
| `base_branch` | string | No | Base branch (default: repo's default) |
| `custom_branch_name` | string | No | Override auto-generated branch name |
| `custom_title` | string | No | Override issue title |
| `extra_labels` | string[] | No | Additional GitHub labels |
| `repo_label` | string | No | Repo label (e.g., `"client"`, `"backend"`) |
| `repo_url` | string | No | Full repo URL (alternative to `repo_label`) |

**Branch naming**: `{category_prefix}/{issueNumber}-{slug}`

| Category | Prefix |
|----------|--------|
| `bug` | `bugfix/` |
| `mejora` | `improvement/` |
| `nuevo` | `feature/` |

**Auto-generated labels**: Based on category + priority (e.g., `["feature", "priority: high"]`)

**Example**:
```
create_github_issue_branch(
  request_id: "uuid",
  base_branch: "develop"
)
```

**Example — Multi-repo project**:
```
create_github_issue_branch(
  request_id: "uuid",
  repo_label: "backend",
  base_branch: "develop"
)
```

**Prerequisites**:
- User must have GitHub OAuth connected in HOT integrations
- Project must have at least one linked GitHub repository
- If project has multiple repos, specify `repo_label` or `repo_url`

**Persists to**: `request_github_links` table (issue_url, issue_number, branch_name, repo_full_name)

---

### `create_github_pr`

Create a GitHub Pull Request for a request that already has an issue+branch link.

**Parameters**:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `request_id` | UUID | Yes | Request UUID |
| `body` | string | No | Additional PR body text |
| `title` | string | No | PR title (default: `"Issue #N: {title}"`) |
| `draft` | boolean | No (default: false) | Create as draft PR |
| `link_id` | UUID | No | Specific GitHub link (default: most recent) |

**Auto-close**: `Closes #N` is always prepended to PR body automatically.

**Example**:
```
create_github_pr(
  request_id: "uuid",
  body: "## Changes\n- Created migration\n- Added RLS policies\n- Regenerated types"
)
```

**Example — Draft PR**:
```
create_github_pr(
  request_id: "uuid",
  draft: true,
  body: "WIP: API endpoints in progress"
)
```

**Prerequisites**:
- Must have called `create_github_issue_branch` first
- Branch must have at least one commit pushed

**Persists to**: Updates `request_github_links` with `pr_url`, `pr_number`, `pr_state`

**Auto-close flow**: When PR is merged → GitHub closes the issue → traceability complete.
