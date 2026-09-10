# Backlog and Readiness

`requests.backlog_state` (`backlog` | `ready`), the HT003 status gate it enforces, and the mandatory
change-note mechanism (HT001/HT002) that rides alongside it. All three ship together because they're
enforced by the same class of DB trigger, on the same table, with the same "no admin bypass, no app/MCP
workaround" posture — a trigger is the only point both the Next.js app and the MCP's service-role client
funnel through unconditionally.

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

## Reading It Back

- `list_requests(backlog_state: "backlog" | "ready" | "all")` — filter by readiness, orthogonal to
  `status` filters.
- `get_request(id)` — includes `backlog_state` directly on the response.
- `get_request_history(request_id)` — merged `request_status_log` + `request_due_date_log` feed with
  every note and author, plus a `time_in_status` breakdown. Use this to see *why* a request has been
  stuck, not just that it has.
