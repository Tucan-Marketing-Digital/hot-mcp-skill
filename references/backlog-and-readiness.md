# Backlog and Readiness

`requests.backlog_state` (`backlog` | `ready`), the HT003 status gate it enforces, the mandatory
change-note mechanism (HT001/HT002) that rides alongside it, and the due-date requirement for
`in_progress` (HT004). They're documented together because they're enforced by the same class of DB
trigger, on the same table, with the same "no admin bypass, no app/MCP workaround" posture — a trigger
is the only point both the Next.js app and the MCP's service-role client funnel through
unconditionally.

---

## `backlog_state` Is Orthogonal to `status`

Two independent axes on `requests`:

| Axis | Values | What it drives |
|------|--------|-----------------|
| `status` | `pending`, `assigned`, `in_progress`, `blocked`, `under_review`, `resolved`, `cancelled` | The workflow state machine — see [status-transitions.md](status-transitions.md) |
| `backlog_state` | `backlog`, `ready` | Whether the request is refined enough to be worked, and visible on the kanban board |

They interact through exactly one rule: **`status` cannot change while `backlog_state` is `backlog`.**
Nothing else couples them — a `ready` request can be any status, and a `backlog` request can technically
hold any status value it was created or left with, it just can't be *moved* to a new one.

## The HT003 Gate

`supabase/migrations/00117_request_ready_required_for_status_change.sql` adds
`trg_request_backlog_status_gate` (`BEFORE UPDATE OF status`): if `OLD.backlog_state = 'backlog'` and the
statement is changing `status`, the whole `UPDATE` is rejected with `ERRCODE HT003`. No admin bypass —
same posture as the terminal-status lock (`trg_request_terminal_lock`, 00099).

Both the MCP's `update_request_status` and the app's `updateRequestStatus` (`lib/services/requests.ts`)
carry a **local pre-check** that throws a clear error before the trigger would ever fire — belt-and-
braces, not a replacement for the trigger. From the MCP side, that means you get a readable error, not a
raw Postgres exception, but the underlying rule is identical either way:

```
update_request_status(id, "in_progress")   // request is still backlog_state: 'backlog'
→ "La solicitud está en el backlog y no puede cambiar de estado. Marcala como Ready primero."
```

**There is no dedicated `mark_request_ready` tool.** Flip it via `update_request`:

```
update_request(id, backlog_state: "ready")
```

## Born `ready` Automatically — the Same Criterion the Skill Already Requires

`create_request` resolves `backlog_state` itself (`resolveCreateBacklogState`,
`packages/shared/src/request-readiness.ts` — the single source of truth shared by the app and the MCP,
since they run in two runtimes that can't import from one another):

```
ready  ⟺  assignee_ids is non-empty  AND  due_date is set
```

Rule 8/16 in [SKILL.md](../SKILL.md) already require both of those on every `create_request` call that
isn't a genuine throwaway. Follow them and this gate never becomes visible — every request you create
lands `ready` and on the kanban immediately. A request only lands in `backlog` when it's created without
an assignee, without a due date, or with `ready: false` passed explicitly.

`ready` can be passed to `create_request` directly to force one state regardless of the derived
criterion — use this only when you deliberately want to override the default (e.g. staging a known-
incomplete request on purpose).

## Returning to the Backlog — One-Way Past `pending`/`assigned`

`update_request(id, backlog_state: "backlog")` is accepted only while the request's *current* `status`
is still `pending` or `assigned` (`BACKLOG_RETURN_ALLOWED_STATUSES`, app-layer check, not a DB trigger —
there is no ERRCODE for this one). Once a request has reached `in_progress` or beyond, it can no longer
be sent back to the backlog — work has already started, so "needs refinement" no longer applies.

## Refine Before You Flip — the Ready Checklist

See Rule 17 ("Backlog → Ready") in [SKILL.md](../SKILL.md) for the full checklist. Short version:
`assignee_ids`, `due_date`, `estimated_hours`, and — when the work has real steps — a checklist via
`add_checklist_item`. Flip `backlog_state` in the *same* pass as filling these in, not before.

## Mandatory Change Notes — HT001 and HT002

Two more triggers on the same table gate specific mutations behind a `note`, and reject the entire
`UPDATE` (not just the field) when it's missing or too short. Minimum length is **5 characters**
(lowered from 10 by SR-15, which also closed a gap where the trigger had never actually enforced a
minimum at all — only a bare non-empty check).

| Trigger | Fires on | Requires `note` when | ERRCODE |
|---------|----------|----------------------|---------|
| `fn_log_request_status_change` | Any `status` change | New status is `blocked` | `HT001` |
| `fn_log_request_due_date_change` | Any `due_date` change | `OLD.due_date` was already set (changing or clearing it) — first-time set needs nothing | `HT002` |

Both tools that touch these fields (`update_request_status` for HT001, `update_request` for HT002) carry
the same local-pre-check pattern as HT003: a clear error before the raw trigger rejection, same
underlying rule.

The full set of DB-enforced gates on `requests`, for reference:

| Gate | Trigger | Rejects | ERRCODE | Tool that hits it |
|------|---------|---------|---------|-------------------|
| Ready gate (SR-15) | `trg_request_backlog_status_gate` (00117) | Any `status` change while `backlog_state = 'backlog'` | `HT003` | `update_request_status` |
| Block note (SR-3) | `fn_log_request_status_change` (00112) | `status → 'blocked'` without a `note` ≥5 chars | `HT001` | `update_request_status` |
| Due-date note (SR-3) | `fn_log_request_due_date_change` (00112) | Changing/clearing an already-set `due_date` without a `note` ≥5 chars | `HT002` | `update_request` |
| Due date for `in_progress` (REQ-87A849 / #295) | `trg_request_due_date_required_in_progress` (00127) | Entering `in_progress` with no `due_date`, **or** clearing the `due_date` of a request already `in_progress` | `HT004` | `update_request_status`, `update_request` |

```
update_request_status(id, "blocked")
→ "Bloquear una solicitud requiere una nota de justificación de al menos 5 caracteres (parámetro note)."

update_request_status(id, "blocked", note: "esperando credenciales de staging")
→ OK — note lands on request_status_log.note

update_request(id, due_date: null)          // due_date was already "2026-09-20"
→ "No se puede modificar la fecha límite sin una nota de justificación..."

update_request(id, due_date: null, note: "cliente pausó el proyecto indefinidamente")
→ OK — note lands on request_due_date_log.note
```

The note is not a comment-thread message — it's written directly onto the audit-log row
(`request_status_log.note` / `request_due_date_log.note`), and surfaces through
`get_request_history`'s merged feed rather than `add_comment`/`get_request(include_activity: true)`'s
activity list. Write what's actually blocking it and who/what resolves it — the 5-character floor
accepts "bloqueado" but that tells the next reader nothing.

## The HT004 Gate — No `in_progress` Without a `due_date`

`supabase/migrations/00127_request_due_date_required_in_progress.sql` adds
`trg_request_due_date_required_in_progress` (`BEFORE INSERT OR UPDATE OF status, due_date`): a
`requests` row can never end an `INSERT`/`UPDATE` as `status = 'in_progress' AND due_date IS NULL`.
Rejected with `ERRCODE HT004`, no admin bypass, same posture as HT001/HT002/HT003 (REQ-87A849 / #295).

Two ways to hit it:

| Attempt | Tool | Fix |
|---------|------|-----|
| Move a request with no `due_date` into `in_progress` | `update_request_status` | Pass the `due_date` param in the same call |
| Clear the `due_date` of a request that's already `in_progress` | `update_request(due_date: null)` | Move it out of `in_progress` first, or change the date instead of clearing it |

`update_request_status` gained an optional **`due_date`** param for exactly this. It rides the *same*
`UPDATE` as the status change (via `set_request_status_with_note`'s `p_due_date`), so the gate sees the
new date and the transition passes — no "set the date, then flip the status" two-step, which would
leave a window where the gate still reads `NULL`:

```
// Request has no due_date yet
update_request_status(id, "in_progress")
→ "Una solicitud En progreso necesita una fecha límite. Pasá el parámetro due_date para continuar."

update_request_status(id, "in_progress", due_date: "2026-09-26")
→ OK — status and due_date set atomically

// Request is already in_progress with due_date "2026-09-26"
update_request(id, due_date: null, note: "cliente pausó el proyecto")
→ rejected (HT004) — the note doesn't authorize it, an in_progress request can't lose its deadline
```

`due_date` is ignored for every other transition — it only matters entering `in_progress`.

Both tools carry the usual local pre-check (a readable error before the trigger fires); the trigger
stays the real authority, so the rule is identical from the app and from the MCP.

**Legacy rows are not broken.** The gate only re-evaluates on an `INSERT`, a genuine `status` change, or
a genuine `due_date` change. A request that was already sitting in `in_progress` with no `due_date`
before 00127 can still be reprioritized, reassigned, archived, or moved on to `under_review`/`resolved`
without being forced through this gate — and it's fixed forward at any time by just setting a date on
it. And since HT003 fires first, a *backlog* request with no date still gets the HT003 message (mark it
`ready` first), not this one.

## Reading It Back

- `list_requests(backlog_state: "backlog" | "ready" | "all")` — filter by readiness, orthogonal to
  `status` filters.
- `get_request(id)` — includes `backlog_state` directly on the response.
- `get_request_history(request_id)` — merged `request_status_log` + `request_due_date_log` feed with
  every note and author, plus a `time_in_status` breakdown. Use this to see *why* a request has been
  stuck, not just that it has.
