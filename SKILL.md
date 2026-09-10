---
name: hot-mcp-workflows
description: |
  Workflows and best practices for using the HOT (Hub de Operaciones Tecnicas) MCP tools.
  Covers request lifecycle, milestone management, GitHub integration, checklists, and team coordination.

  Use when: creating requests via MCP, managing milestones, linking GitHub issues/branches/PRs,
  tracking progress with checklists, planning project workflows, or asking about HOT MCP tool usage.

license: MIT
version: 1.4.0
category: workflow
author: Tucan Marketing Digital
requires_tools:
  - hot-platform
---

# HOT MCP Workflows

**Status**: Production Ready
**Last Updated**: 2026-09-10
**Source**: Tucan-Marketing-Digital/zana-v2

---

## Quick Start — Decision Tree

Before calling any tool, decide your scenario:

```
Not sure who you are yet (need to self-assign or self-mention)?
│   └─ whoami → use returned id as assignee_ids / @mention target

What are you trying to do?
│
├─ Single request (no project)
│   └─ create_request → update_request_status → resolved
│
├─ Request inside a project
│   └─ list_projects → create_request(project_id) → GitHub flow → resolved
│
├─ Request inside a milestone
│   └─ list_projects → list_milestones → create_request(project_id, milestone_id) → GitHub flow → resolved
│
├─ Plan a full project with milestones
│   └─ list_projects → create milestone group(s) → create milestones (group_id + depends_on chain) → create requests per milestone → execute
│
└─ Track progress on existing work
    └─ list_requests / get_request → update_request_status / checklist / comments
```

---

## ⛔ Non-Negotiable: A Request in the Backlog Cannot Change Status

`requests.backlog_state` is `backlog` or `ready`. It is **orthogonal to `status`** and gates it: a
request born (or later returned) `backlog` (SR-4/SR-15) **cannot have its `status` changed at all** —
not to `assigned`, not to `in_progress`, nothing — until it's marked `ready`. This is enforced by a DB
trigger (`ERRCODE HT003`, `supabase/migrations/00117`) with **no admin bypass and no app/MCP
workaround**: `update_request_status` rejects the call locally before even reaching the trigger.

```
backlog_state: 'backlog'  ──╳──  update_request_status(...)   →  rejected, every time, ERRCODE HT003
backlog_state: 'backlog'  ──→   update_request(backlog_state: 'ready')  →  now status CAN change
```

**Born `ready` automatically** when `create_request` gets both `assignee_ids` and `due_date` in the same
call (`resolveCreateBacklogState`, `packages/shared/src/request-readiness.ts`) — which is exactly what
Rule 8/16 below already require you to pass. A request created that way never touches this gate. One
lands in `backlog` only when created without an assignee, without a due date, or explicitly forced there
(`ready: false`).

**How to get a request out of the backlog** — `update_request(id, backlog_state: "ready")`. There is no
dedicated `mark_request_ready` tool. Before flipping it, make sure the request is actually refined (Rule
17, "Backlog → Ready", below) — flipping the switch without refining defeats the entire point of the gate.

**`backlog` → itself is one-way past `pending`/`assigned`**: `update_request` only accepts
`backlog_state: "backlog"` while the request's current `status` is still `pending` or `assigned`. Once
work has started (`in_progress` or later), it can no longer be sent back to the backlog.

Check `backlog_state` with `list_requests(backlog_state: "backlog")` or on any single request via
`get_request` — both already return the field. Full mechanics, including the "born ready" criterion and
worked examples: [references/backlog-and-readiness.md](references/backlog-and-readiness.md).

---

## ⛔ Non-Negotiable: Every Request Is Born Assigned and Dated

`create_request` marks `assignee_ids`, `due_date` and `estimated_hours` as optional. **They are not
optional in practice.** A request created without them is not "incomplete but harmless" — it is
**invisible to every metric HOT computes**, permanently.

### What actually breaks (verified against the platform code)

| Missing field | Mechanical consequence |
|---------------|------------------------|
| `assignee_ids` | The request is born `pending`, not `assigned` — `create_request` does `status: hasAssignees ? "assigned" : "pending"`. On resolution the `on_request_resolved` trigger bails at `IF v_assignee_count = 0 THEN RETURN NEW`: **zero XP for anyone, no badges, no `developer_stats` recompute**. That trigger only fires on the transition *into* `resolved`, so assigning afterwards never back-pays it. `getDeveloperPerformance` and `getTeamWorkload` are built entirely from `request_assignees` — the task counts for nobody. The deadline cron emits one notification per (request × assignee) pair: no assignee, no reminder, even with a date. |
| `due_date` | The completeness multiplier in `calculate_request_xp` loses `+0.10`. `ON_TIME_BONUS` (+20) is gated on `due_date IS NOT NULL` → never awarded. `on_time_cnt` in `developer_stats` filters on `due_date IS NOT NULL` → the on-time rate is understated for everyone. `getOverdueRequests` and `getProjectHealth` filter `.not("due_date","is",null)` → **a late task with no date is invisible as overdue**. The deadline-reminders cron only selects requests that have one. |
| `estimated_hours` | The completeness multiplier loses `+0.15`, and the effort base falls to its floor: `0h → 30 XP`, versus `1–4h → 50`, `5–16h → 80`, `17–40h → 120`, `41h+ → 160`. |

Both gaps together drag the completeness multiplier from a possible `1.00` down to `0.75` *and* cut the
effort base — **the same work ends up worth roughly half the XP**, and the person who did it doesn't
appear in the workload view at all.

### How to fill them — always, at creation time

**1. `assignee_ids` — never empty.**

- The user named someone → resolve the name to a UUID with `list_team`. Never hardcode a UUID.
- The user named nobody → **default to the API-key owner** (`whoami`, cached for the session). That is
  the person asking; they own it until they say otherwise.
- Several people → pass them all; XP is split evenly (`CEIL(total / assignee_count)`), nothing is lost.

**2. `due_date` — never empty.** Use what the user gave. If they gave nothing, derive it from `priority`
(and if the user didn't state a priority either, default `priority` itself to `mid` — P2, not `high` —
before deriving the date from it):

| Priority | Default `due_date` |
|----------|--------------------|
| `critical` (P0 Crítica) | today — **same day**, no business-day math |
| `high` (P1 Alta) | today **+ 3 business days** |
| `mid` (P2 Media) | today **+ 7 business days** |
| `low` (P3 Baja) | today **+ 14 business days** |

`critical` is reserved for requests that genuinely can't wait (production down, blocking the
whole team). Its default isn't "fewer business days" — it's *today*, full stop. Don't reach for
it just to jump a queue; overusing P0 erodes it as a signal, and it also swings XP (+45 vs +30
for `high`).

Count **business days** — and resolve today's weekday with a tool before counting, never from
memory. A wrong anchor shifts every derived date, and `+3`/`+7` often survive it by coincidence
while `+14` does not. **A derived date landing on a Saturday or Sunday means the anchor was wrong.**

**3. `estimated_hours` — never empty.** Estimate from the scope actually described (the buckets above
are the ones the XP function reads), and announce it together with the date.

### Then say what you did, in one line

```
Creada REQ-A1B2C3 — asignada a Carlos Rivas, vence 2026-09-04
(default de prioridad alta: +3 días hábiles), estimada en 6 h.
Decime si ajusto fecha, horas o responsable.
```

**A default is not a fabrication.** Fabricating means inventing a value and passing it off as the
user's. A default derived from a stated rule and announced out loud is a *proposal*: visible,
attributed to the rule that produced it, correctable in the very next message. The alternative this
replaces — a request with no owner and no date — is not the honest option. It is a hole in the
metrics that nobody can see, and it never gets filled later.

**The one exception**: a throwaway standalone request with no project, no milestone and no intention of
being tracked. Everything that belongs to a project or a milestone gets all three fields.

---

## Tool Catalog (25 tools)

### Identity

| Tool | Purpose | Key params |
|------|---------|------------|
| `whoami` | Identify the current API key owner — id, name, email, role, scopes | — |

**Call this first** whenever a workflow needs to self-assign a request, self-mention in a comment, or check your own role before an action gated by role (e.g. milestone creation). Do not hardcode a UUID you remember from a previous session — always resolve it fresh with `whoami`.

### Reading

| Tool | Purpose | Key params |
|------|---------|------------|
| `list_projects` | List all projects (admin=all, others=own) | — |
| `list_requests` | List requests with filters | `status`, `priority`, `backlog_state`, `view`, `search` |
| `list_stale_requests` | Requests past their aging/time-in-status thresholds | `days?`, `project_id?` |
| `get_request` | Full request details + activity log | `id`, `include_activity` |
| `get_request_history` | Merged status + due_date audit log with time-in-status | `request_id` |
| `list_milestones` | Milestones for a project with linked requests | `project_id`, `status` |
| `list_milestone_groups` | Milestone groups for a project | `project_id` |
| `list_team` | Team directory | — |
| `get_checklist` | Checklist items for a request | `request_id` |

### Creating

| Tool | Purpose | Key params |
|------|---------|------------|
| `create_request` | New request (standalone or linked) | `title`, `description`, `priority`, `project_id?`, `milestone_id?`, `assignee_ids?`, `due_date?`, `estimated_hours?` |
| `create_milestone` | New milestone in a project | `project_id`, `name`, `start_date?`, `target_date?`, `depends_on?`, `group_id?` |
| `create_milestone_group` | New milestone group (organizational container) in a project | `project_id`, `name`, `description?` |

### Updating

| Tool | Purpose | Key params |
|------|---------|------------|
| `update_request_status` | Move request through states — rejected if `backlog_state` is still `backlog` (HT003) | `id`, `status`, `note?` (mandatory, ≥5 chars, when `status: "blocked"`) |
| `update_request` | Update request fields (NOT status) — also the only way to flip `backlog_state` | `id`, `title?`, `priority?`, `due_date?`, `estimated_hours?`, `assignee_ids?`, `category?`, `domain?`, `backlog_state?`, `note?` (mandatory, ≥5 chars, when changing/clearing an already-set `due_date`) |
| `update_milestone` | Update milestone fields/status | `milestone_id`, `status?`, `name?`, `depends_on?`, `group_id?` |
| `update_milestone_group` | Rename/redescribe a milestone group | `id`, `name?`, `description?` |
| `link_milestone` | Link/unlink request to milestone | `request_id`, `milestone_id` (null=unlink) |
| `add_checklist_item` | Add acceptance criteria | `request_id`, `title` |
| `update_checklist_item` | Check/uncheck item | `id`, `is_complete?`, `title?` |
| `delete_checklist_item` | Remove a checklist item | `id`, `request_id` |
| `add_comment` | Comment with @mentions | `request_id`, `content` |

### Deleting

| Tool | Purpose | Key params |
|------|---------|------------|
| `delete_milestone_group` | Delete a milestone group | `id` — milestones inside are **not** deleted, only ungrouped |

### GitHub Integration

| Tool | Purpose | Key params |
|------|---------|------------|
| `create_github_issue_branch` | Create GitHub issue + branch | `request_id`, `base_branch?`, `custom_branch_name?`, `extra_labels?`, `repo_label?` |
| `create_github_pr` | Create PR with auto-close | `request_id`, `body?`, `draft?`, `title?` |

> Full parameter details: [references/tool-catalog.md](references/tool-catalog.md)

---

## Fundamental Rules

### 1. Resolution Flow by Domain

Not every request needs GitHub. The flow depends on the request's `domain`:

```
┌─ domain = "development" ─────────────────────────────────────────────┐
│                                                                      │
│  GitHub is MANDATORY. Before starting work:                          │
│  1. Verify project has a linked GitHub repo                          │
│     → If NO repo: STOP execution, inform the user                   │
│     → If repo exists: proceed                                        │
│  2. create_github_issue_branch (creates issue + branch)              │
│  3. ... development work ...                                         │
│  4. create_github_pr (with auto-close)                               │
│  5. After merge → update_request_status("resolved")                  │
│                                                                      │
│  Flow: checklist → in_progress → issue+branch → work → PR → resolve │
└──────────────────────────────────────────────────────────────────────┘

┌─ domain = "design" | "global" ───────────────────────────────────────┐
│                                                                      │
│  No GitHub required. Simpler flow:                                   │
│  1. Work is tracked via checklist + comments                         │
│  2. No branch, no PR, no issue                                       │
│                                                                      │
│  Flow: checklist → in_progress → work → resolve                     │
└──────────────────────────────────────────────────────────────────────┘
```

### 2. Order of Operations

High-level shape — see [Task Resolution Flow](#task-resolution-flow-working-a-single-request) below for the full step-by-step (assignment check, milestone cascade, PR-merge communication).

**Development requests** (full flow):

```
1. Query first       → list_projects, list_milestones, list_requests
2. Create structure   → create_milestone (with dependencies)
3. Create work items  → create_request (project + milestone + assignee_ids + due_date + estimated_hours — all of them, always)
4. Add criteria       → add_checklist_item (only if the task has real steps)
5. Verify GitHub      → Confirm project has linked repo. STOP if missing.
6. Start work         → check assignment → update_request_status("in_progress") → cascade milestone to in_progress if it was pending
7. GitHub setup       → create_github_issue_branch
8. Track progress     → update_checklist_item, add_comment
9. Request review     → update_request_status("under_review") + create_github_pr → tell user resolution isn't automatic
10. Close             → update_request_status("resolved") once user confirms the merge
11. Close milestone   → cascade check: update_milestone(status: "completed") when ALL requests resolved
```

**Design / Global requests** (simplified flow):

```
1. Query first       → list_projects, list_milestones, list_requests
2. Create structure   → create_milestone (with dependencies)
3. Create work items  → create_request (project + milestone + assignee_ids + due_date + estimated_hours — all of them, always)
4. Add criteria       → add_checklist_item (only if the task has real steps)
5. Start work         → check assignment → update_request_status("in_progress") → cascade milestone to in_progress if it was pending
6. Track progress     → update_checklist_item, add_comment
7. Close              → update_request_status("resolved")
8. Close milestone    → cascade check: update_milestone(status: "completed") when ALL requests resolved
```

### 3. Valid Status Transitions (Requests)

```
pending ──→ assigned ──→ in_progress ──→ under_review ──→ resolved
  │            │             │  ↑              │
  │            │             │  └── blocked ───┘
  │            │             │
  └────────────┴─────────────┴──→ cancelled ──→ pending (reopen)
```

Only these transitions are allowed. Skipping states (e.g., `pending` → `under_review`) will fail.

> Full state machine: [references/status-transitions.md](references/status-transitions.md)

### 4. Milestone States

```
pending → in_progress → completed
                     → skipped
```

**Rule**: Only mark a milestone `completed` when ALL its linked requests are `resolved`. There is no `blocked` status for milestones — only requests have that state.

### 5. Milestone Dates are Required — Same Rule as Requests

Same principle as Rule 8 (`due_date`/`estimated_hours` on requests), applied to `start_date`/`target_date` on `create_milestone`/`update_milestone`: the API marks them optional, **always pass both anyway**. Without them the timeline view has gaps, the Gantt has nothing to draw, and dependency scheduling is guesswork.

If the user didn't give dates, derive them instead of leaving the fields empty, and say so:

- `start_date` = today, or the `target_date` of the milestone it `depends_on` (a gated milestone cannot start before its blocker lands).
- `target_date` = the latest `due_date` among the requests planned for it. No requests yet? Sum their estimated hours at ~6 productive hours/day, and round up to the next business day.

Announce the derivation the same way as a request's date, in one correctable line.

### 6. GitHub Branch Naming

Auto-generated: `{prefix}/{issueNumber}-{slug}`

| Category | Prefix |
|----------|--------|
| `bug` | `bugfix/` |
| `mejora` | `improvement/` |
| `nuevo` | `feature/` |

Example: `feature/42-dashboard-redesign`

> Full details: [references/github-integration.md](references/github-integration.md)

### 7. Always Link to Project + Milestone

When working within a project, ALWAYS pass both `project_id` and `milestone_id` to `create_request`. Orphan requests inside projects lose traceability.

### 8. `due_date` and `estimated_hours` — Set at Creation, Every Time

**Never call `create_request` without both.** They feed the deadline cron, the overdue views, the
on-time rate, the workload view and the XP formula — see
[Every Request Is Born Assigned and Dated](#-non-negotiable-every-request-is-born-assigned-and-dated)
above for exactly what each missing field breaks.

- **The user gave values** → use them verbatim.
- **The user gave nothing** → derive `due_date` from `priority` (critical → today / high +3 / mid +7
  / low +14 business days), estimate `estimated_hours` from the scope described, and **announce both
  in one correctable line**. Deriving-and-announcing is not fabricating; leaving the fields null is
  not honesty.
- **The scope is genuinely unreadable** (you cannot tell whether it's 2 hours or 2 weeks) → ask,
  before creating. Ask *once*, with your best guess offered as the starting point.

A pre-existing request that reaches `in_progress` still missing either field gets it filled with
`update_request` first — same defaults, same one-line announcement.

**Only truly optional** for a throwaway standalone request tied to no project and no milestone.

### 9. Checklist = Acceptance Criteria (When the Task Has Steps)

Add checklist items BEFORE starting work, when the request naturally breaks down into multiple steps — they become the definition of done. A trivial, single-action request doesn't need one; don't manufacture steps just to have a checklist.

### 10. Comments for Context

Use `add_comment` for decisions, blockers, and progress updates. Use `@[Name](uuid)` syntax for mentions.

### 11. Identify Yourself with `whoami`

If a workflow needs to assign a request to "yourself" or mention yourself in a comment, call `whoami` — do not ask the user for their UUID and do not reuse a UUID cached from a previous session (API keys can be rotated/reassigned, and each key is scoped only to the permissions of the user who generated it). `whoami` requires no scope and works for any valid API key. Response includes `role`, useful to pre-check permission before calling role-gated tools like `create_milestone`.

**Cache it per session**: resolve your identity once and reuse the `id` for the rest of the conversation — don't call `whoami` before every single action once you already know who you are.

### 12. Milestone Groups vs. `depends_on` — Complementary, Not Interchangeable

These solve different problems and are normally used **together**:

- **`create_milestone_group`** — an organizational container (e.g. "Fase 1: Fundación"). Milestones join it via `group_id`. Purely for grouping/display — `list_milestone_groups` lets you query a project's phases without inferring them from naming conventions.
- **`depends_on`** — an execution-order constraint between two individual milestones (B can't start until A is `completed`). Independent of grouping.

A milestone can belong to a group AND have a `depends_on` pointing to a milestone in a different group. Use a group when you want milestones organizationally bundled (e.g. all "MVP" work); use `depends_on` when you want to gate start times. See [examples/05-milestone-groups.md](examples/05-milestone-groups.md) for combined patterns.

### 13. Check Assignment Before Starting Work

Before moving ANY request to `in_progress`, check who it's assigned to:

- **Assigned to you** → proceed
- **Unassigned** → ask the user: "¿Asigno esta solicitud a vos?" (resolve your id via `whoami` if not already cached this session)
- **Assigned to someone else** → ask before touching it — never silently reassign

See [Task Resolution Flow](#task-resolution-flow-working-a-single-request) below for the full sequence.

### 14. Milestones Cascade With Their Requests

A milestone's status should track its requests' progress even when nobody explicitly updates the milestone:

- Moving the **first** request in a milestone to `in_progress` → also move the milestone to `in_progress` if it's still `pending`
- Moving the **last** unresolved request in a milestone to `resolved` → check whether all requests are now `resolved`, and if so move the milestone to `completed` (proactively — don't wait to be asked)

> Full cascade rules: [references/status-transitions.md](references/status-transitions.md)

### 15. Set `category` and `domain` at Creation Time

Resolve `category` (`bug`/`mejora`/`nuevo`) and `domain` (`development`/`design`/`global`) when creating a request, not later — `domain` in particular determines whether the entire GitHub flow applies downstream (Rule 1). Getting it wrong means either a spurious GitHub issue+branch or a missing one.

**Note on "tags"**: there is no free-form tags/labels field on requests today — only `category` and `domain` exist as classification fields. `extra_labels` exists only on `create_github_issue_branch`, scoped to the GitHub issue, not the HOT request itself.

### 16. Assign at Creation — Rule 13 Is the Second Line of Defence, Not the First

Rule 13 checks assignment *before starting work*. That check exists for requests that arrive from
elsewhere. **For a request you create yourself, the assignee is decided at `create_request` time** and
`assignee_ids` is never empty:

| Situation | What to pass |
|-----------|--------------|
| The user named a person ("asignásela a Carlos") | `list_team` → match the name → their UUID |
| The user named several | all of their UUIDs — XP splits evenly, nothing is lost |
| The user named nobody | the API-key owner's id (`whoami`) — they asked for it, they own it |
| The user explicitly said to leave it unassigned | honour it, and say out loud that it will earn no XP and appear in no workload view until someone is assigned |

Resolving a name to a UUID is `list_team`'s entire purpose — **never hardcode a UUID from memory** and
never skip the field because "someone will pick it up". Nobody picks up what no view shows.

### 17. Backlog → Ready — Refine Before You Flip the Switch

Marking a request `ready` (`update_request(id, backlog_state: "ready")`) is what lifts the HT003 gate
above and puts it on the kanban board — do it only once the request is actually refined, not as a
rubber stamp. "Refined" means:

| Field | Why it's part of the gate |
|-------|---------------------------|
| `assignee_ids` | Same reasons as Rule 16 — someone has to own it once it's visible |
| `due_date` | Same reasons as Rule 8 — a ready request with no deadline is still invisible to the overdue views |
| `estimated_hours` | Same reasons as Rule 8 — feeds the XP effort base and completeness multiplier |
| `add_checklist_item` (if the work has real steps) | A ready request with no acceptance criteria is ready to work on but not ready to review against |

Marking a batch of backlog requests `ready` without filling these in first defeats the entire purpose of
the gate — it just moves the "incomplete and invisible-to-metrics" problem from `backlog_state` back to
the fields the gate was meant to force you to fill. If a request lacks one of these, fill it (via
`update_request`) in the *same* pass as the `ready` flip, not after.

### 18. Justify Blocks and Due-Date Changes — Always a Note, Always ≥5 Characters

Two mutations are gated by a DB trigger that requires a `note` param (5–500 chars) or **rejects the
entire call**, not just the field it can't validate:

| Mutation | Tool | Requires `note` when | Rejected with |
|----------|------|----------------------|----------------|
| `status → "blocked"` | `update_request_status` | Always, for this transition | `ERRCODE HT001` |
| Changing or clearing an **already-set** `due_date` | `update_request` | `due_date` is present in the call AND the current `due_date` isn't already `null` | `ERRCODE HT002` |

Setting a `due_date` for the first time (previously `null`) never requires a note. The note isn't a
comment-thread message — it's written onto the log row itself (`request_status_log.note` /
`request_due_date_log.note`) and shows up in `get_request_history`. Write what's blocking it (or why the
date moved) and who or what unblocks it — "bloqueado, esperando credenciales de staging de @[Ana](uuid)"
is a note; "bloqueado" alone will pass the 5-character floor but tells nobody anything.

---

## Task Resolution Flow (Working a Single Request)

The most common interaction: "resolve/work on this request." This is the sequence for an **already-existing** request — see [Master Flow](#master-flow-full-project-lifecycle) below for planning a project from scratch.

```
1. Identify the request        → get_request(id) / list_requests(search: "...")

2. Check assignment (Rule 13)
   ├─ Assigned to you           → go to step 3
   ├─ Unassigned                → ASK the user: "¿Asigno esta solicitud a vos?"
   │                                yes → whoami (if not cached) → update_request(id, assignee_ids: [your_id])
   └─ Assigned to someone else  → ASK before touching it — do not silently reassign

3. Move to in_progress          → update_request_status(id, "in_progress")
                                   (from whatever the current valid status is — pending, assigned, blocked, or back from under_review)
   → Check milestone cascade (Rule 14): if this is the first active request in its milestone, move the milestone to in_progress too

4. BEFORE touching any code:
   ├─ domain = "development"    → verify the project has a linked GitHub repo (STOP + inform user if not)
   │                               → create_github_issue_branch(request_id, base_branch, repo_label)
   │                               → check out the generated branch, THEN start working
   └─ domain = "design"/"global"→ no GitHub step, start working directly

5. Do the work (update_checklist_item as steps complete, add_comment for decisions/blockers)

6. When ready for review (tests pass / whatever "done" means for this task):
   → update_request_status(id, "under_review")
   → create_github_pr(request_id, body)
   → TELL THE USER EXPLICITLY: there is no automatic link between GitHub and HOT —
     "Dejo esto en under_review con la PR abierta. Avisame cuando se apruebe/mergee
     y lo paso a resuelto."

7. When the user confirms the PR merged → update_request_status(id, "resolved")
   → Check milestone cascade (Rule 14): if this was the last unresolved request in its milestone, move the milestone to completed
```

---

## Master Flow: Full Project Lifecycle

```
┌─────────────────────────────────────────────────────────┐
│                    PROJECT PLANNING                      │
│                                                         │
│  whoami → resolve your own id (for default assignments) │
│  list_projects → get project_id                         │
│  create_milestone_group(project_id, "Fase 1") → group_id │
│  create_milestone(A, group_id) ──→ create_milestone(B, depends:A, group_id) │
│                      ──→ create_milestone(C, depends:B, group_id) │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│                  PER-MILESTONE EXECUTION                 │
│                                                         │
│  update_milestone(A, "in_progress")                     │
│                                                         │
│  For each request in milestone A:                       │
│    create_request(project_id, milestone_id)             │
│    add_checklist_item(request_id, criteria...) — if it has real steps │
│    check assignment → update_request_status("in_progress") │
│    create_github_issue_branch(request_id)               │
│    ... development happens ...                          │
│    update_checklist_item(item_id, is_complete: true)    │
│    update_request_status("under_review")                │
│    create_github_pr(request_id, body)                   │
│    → tell user: not resolved until you confirm the merge │
│    ... user confirms PR merged ...                       │
│    update_request_status("resolved")                    │
│                                                         │
│  All requests resolved → update_milestone(A,"completed")│
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
              Next milestone (B) can start
```

> Detailed examples: [examples/](examples/)

---

## Categories and Priorities

| Field | Values | Notes |
|-------|--------|-------|
| `category` | `bug`, `mejora`, `nuevo` | Affects GitHub branch prefix and labels |
| `priority` | `critical`, `high`, `mid`, `low` | P0, P1, P2, P3 — affects GitHub labels **and the default `due_date`**. `critical` (P0) is for genuinely urgent work only — it defaults to *today*, not a shorter business-day count. Required by the tool schema — if the user didn't state one, default to `mid` (P2) |
| `domain` | `development`, `design`, `global` | Determines if GitHub is required (development = yes) |
| `due_date` | `YYYY-MM-DD` format | ISO format. **Mandatory** — default from priority: critical = today, high +3, mid +7, low +14 business days |
| `estimated_hours` | Number > 0 | **Mandatory.** XP effort buckets: 1–4h → 50, 5–16h → 80, 17–40h → 120, 41h+ → 160 (unset → 30) |
| `assignee_ids` | UUID[] | **Mandatory.** The person named, or the API-key owner (`whoami`) by default |

> Full conventions: [references/naming-conventions.md](references/naming-conventions.md)

---

## Common Mistakes

Avoid these patterns:

| Mistake | Why it fails | Correct approach |
|---------|-------------|-----------------|
| Skip `project_id` on request inside a project | Request won't appear in project view | Always pass `project_id` |
| Skip `milestone_id` when milestone exists | Request not tracked in milestone progress | Always pass `milestone_id` |
| `pending` → `under_review` directly | Invalid transition | Go through `in_progress` first |
| Development request without GitHub | No traceability for code changes | GitHub is **mandatory** for `domain: "development"` |
| Start dev request when project has no repo | `create_github_issue_branch` will fail | **STOP and inform user** — project needs a linked GitHub repo first |
| Create PR before issue+branch | No branch to PR from | `create_github_issue_branch` first |
| Mark milestone `completed` with open requests | Misleading progress | Verify all requests resolved first |
| Create GitHub issue before `in_progress` | Status inconsistency | Move to `in_progress` first, then create issue |
| Hardcode your own UUID from memory/a previous session | API keys can be reassigned/rotated — stale UUID silently assigns the wrong person | Call `whoami` fresh each session |
| Only use `depends_on` chains to simulate project phases | No queryable grouping — `list_milestone_groups` returns nothing, phases only exist as a naming convention | Use `create_milestone_group` + `group_id` for the phase, `depends_on` for ordering |
| Move a request to `in_progress` without checking who it's assigned to | Silently starts work on someone else's task, or work nobody agreed you should own | Check assignment first (Rule 13) — ask before self-assigning or touching someone else's request |
| Create a request with empty `assignee_ids` | Born `pending` instead of `assigned`; on resolve the XP trigger bails at zero assignees → **0 XP, forever**; invisible in workload and developer performance; no deadline reminder has anyone to notify | Always pass an assignee: the person named, or the API-key owner (`whoami`) by default |
| Create a request with no `due_date`/`estimated_hours` because the user didn't give them | No on-time bonus, understated on-time rate, **invisible in the overdue views**, no deadline reminder, and roughly half the XP for the same work | Derive from `priority` (critical = today / high +3 / mid +7 / low +14 business days), estimate the hours, and announce both in one correctable line |
| Use `critical` (P0) as a way to jump the queue instead of for genuinely urgent work | Erodes P0 as a signal — everything becomes "critical," so nothing is | Reserve `critical` for production-down / whole-team-blocked situations; default to `high`/`mid` otherwise |
| Announce nothing after applying a derived date or estimate | A silent default is indistinguishable from a fabrication — the user can't correct what they never saw | State assignee + date + hours in one line, inviting correction |
| Leave a request in `under_review` with no word to the user about resolution | GitHub merging the PR does **not** move the HOT request to `resolved` — it silently stalls forever | State explicitly when opening the PR that you'll mark it `resolved` once told the merge happened |
| Milestone status left `pending` while its requests are already `in_progress`/`resolved` | Misleading progress view — the milestone looks like it hasn't started or is stuck | Cascade milestone status with its requests (Rule 14): first request starts → milestone `in_progress`; last one resolves → milestone `completed` |
| No `start_date`/`target_date` on a milestone being planned | Timeline view has gaps, the Gantt has nothing to draw, dependency scheduling becomes guesswork | Always include both — derive from the blocker's `target_date` and the requests' dates if the user didn't specify (Rule 5) |
| Try to change the `status` of a request still in the backlog | Rejected outright, `ERRCODE HT003` — no partial effect, nothing to catch and retry around | `update_request(id, backlog_state: "ready")` first (after refining it — Rule 17), then `update_request_status` |
| Mark a batch of requests `ready` without refining them first | Defeats the HT003 gate's purpose — it just relabels the same incomplete requests as visible | Fill `assignee_ids` + `due_date` + `estimated_hours` (+ checklist if it has steps) in the same pass as the `ready` flip (Rule 17) |
| Call `update_request_status(status: "blocked")` without `note` | Trigger rejects the **whole UPDATE** — this is not a warning, the status never changes, `ERRCODE HT001` | Pass `note` (≥5 chars) explaining what's blocking it and who/what unblocks it (Rule 18) |
| Clear or change an already-set `due_date` without `note` | Same as above for the date axis — rejected outright, `ERRCODE HT002` | Pass `note` (≥5 chars) explaining why the date moved or was removed (Rule 18) |
| Leave a request sitting in the backlog expecting it to show up on the board | It never will — `backlog_state` is invisible to `status`, nothing "graduates" it automatically | Refine it and flip `backlog_state: "ready"` explicitly (Rule 17) |

> Full anti-patterns: [references/common-mistakes.md](references/common-mistakes.md)

---

## Cross-References

### Reference Documentation
- [Tool Catalog](references/tool-catalog.md) — Every tool with full params and examples
- [Backlog and Readiness](references/backlog-and-readiness.md) — The HT003 gate, the "born ready" criterion, mandatory change notes
- [Status Transitions](references/status-transitions.md) — State machines and rules
- [GitHub Integration](references/github-integration.md) — Branch naming, auto-close, trazabilidad
- [Common Mistakes](references/common-mistakes.md) — Anti-patterns with corrections
- [Naming Conventions](references/naming-conventions.md) — Categories, priorities, formats

### Usage Examples
- [Single Request](examples/01-single-request.md) — Standalone request lifecycle
- [Milestone with Requests](examples/02-milestone-with-requests.md) — One milestone, N requests
- [Full Project Flow](examples/03-full-project-flow.md) — Complete project with chained milestones
- [Bug/Hotfix Flow](examples/04-bug-hotfix-flow.md) — Bug category with GitHub bugfix branch
- [Milestone Groups](examples/05-milestone-groups.md) — Parallel + sequential dependency patterns
- [Progress Tracking](examples/06-progress-tracking.md) — Checklists, comments, blockers
- [Incorrect Usage](examples/07-incorrect-usage.md) — What NOT to do (with corrections)
- [Backlog Grooming](examples/08-backlog-grooming.md) — Refining and flipping requests from `backlog` to `ready`
- [Blocked With Reason](examples/09-blocked-with-reason.md) — Blocking a request and changing a due date, both with a justification note
