---
name: hot-mcp-workflows
description: |
  Workflows and best practices for using the HOT (Hub de Operaciones Tecnicas) MCP tools.
  Covers request lifecycle, milestone management, GitHub integration, checklists, team coordination,
  and forum authoring (posts, comments, categories).

  Use when: creating requests via MCP, managing milestones, linking GitHub issues/branches/PRs,
  tracking progress with checklists, planning project workflows, writing or publishing forum posts
  ("foro", crear/publicar post, forum comment, categorias del foro), or asking about HOT MCP tool usage.

license: MIT
version: 1.6.0
category: workflow
author: Tucan Marketing Digital
requires_tools:
  - hot-platform
---

# HOT MCP Workflows

**Status**: Production Ready
**Last Updated**: 2026-10-27
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
├─ Track progress on existing work
│   └─ list_requests / get_request → update_request_status / checklist / comments
│
└─ Write/read something in the FORUM (/foro) — not a request at all
    ├─ Read      → list_forum_posts / get_forum_post (Markdown out, never registers a view)
    ├─ Publish   → list_forum_categories → create_forum_post (lands as DRAFT) → get_forum_post to verify → update_forum_post(status:"published")
    ├─ Extend    → update_forum_post(append_markdown) — NEVER content_markdown when content_conversion.lossy is true
    └─ Comment   → add_forum_comment, mentions written as @[Nombre](uuid) inside content
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

**A second, independent gate sits in front of `in_progress`**: even a `ready` request cannot enter
`in_progress` without a `due_date` (`ERRCODE HT004`, `supabase/migrations/00127`) — see Rule 19 below.

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

## Tool Catalog (33 tools)

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
| `update_request_status` | Move request through states — rejected if `backlog_state` is still `backlog` (HT003) | `id`, `status`, `note?` (mandatory, ≥5 chars, when `status: "blocked"`), `due_date?` (mandatory when `status: "in_progress"` and the request has none — HT004) |
| `update_request` | Update request fields (NOT status) — also the only way to flip `backlog_state` | `id`, `title?`, `priority?`, `due_date?` (cannot be set to `null` while `status` is `in_progress` — HT004), `estimated_hours?`, `assignee_ids?`, `category?`, `domain?`, `backlog_state?`, `note?` (mandatory, ≥5 chars, when changing/clearing an already-set `due_date`) |
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

### Forum (`/foro`) — scopes `forum:read` / `forum:write`

Content is **always plain Markdown** on this surface, both directions. See [Foro](#foro-markdown-draft-first-and-an-immutable-slug) below.

| Tool | Scope | Purpose | Key params |
|------|-------|---------|------------|
| `list_forum_posts` | `forum:read` | List posts (metadata only, no content) | `tab?` (`recent`/`popular`/`mine`), `category_id?`, `category_name?`, `search?`, `status?`, `author_id?`, `page?`, `per_page?` |
| `get_forum_post` | `forum:read` | One post + `content_markdown` + `content_conversion` + comments. Never registers a view | `id` **or** `slug` (exactly one), `include_comments?` |
| `list_forum_categories` | `forum:read` | Every category with `post_count` — **read-only, no create/delete** | — |
| `create_forum_post` | `forum:write` | New post from Markdown. **Defaults to `draft`**. admin/developer only | `title`, `content_markdown`, `category_ids?`, `category_names?`, `banner_url?`, `excerpt?`, `status?` |
| `update_forum_post` | `forum:write` | Edit + publish/unpublish. Slug **never** changes | `id`/`slug`, `title?`, `content_markdown?` **xor** `append_markdown?`, `category_ids?`, `banner_url?`, `excerpt?`, `status?` |
| `delete_forum_post` | `forum:write` | Permanent delete, cascades to comments/reactions/views | `id`/`slug`, `confirm: true` |
| `add_forum_comment` | `forum:write` | Comment or reply. Mentions parsed from `content` | `post_id`/`post_slug`, `content`, `parent_id?` |
| `delete_forum_comment` | `forum:write` | Permanent delete, cascades to replies | `id`, `confirm: true` |

**Existing API keys do not have `forum:read`/`forum:write`** — the scopes shipped later and are not
granted retroactively. A pre-existing key fails with `Permiso insuficiente: se requiere 'forum:write'`,
and nothing in the call can fix it: the user has to add the scopes in HOT → Ajustes → API keys. Check
`whoami().api_key_scopes` before your first forum write.

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
`update_request` first — same defaults, same one-line announcement. For `due_date` this isn't a
convention but a DB gate: `in_progress` without a date is rejected (`ERRCODE HT004`, Rule 19), and
`update_request_status` takes a `due_date` param so both can be set in one call.

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

### 19. No `in_progress` Without a `due_date` — `ERRCODE HT004`

A request cannot **enter** `in_progress` without a `due_date`, and one that's already `in_progress`
cannot have its `due_date` **removed**. Enforced by a DB trigger
(`trg_request_due_date_required_in_progress`, `supabase/migrations/00127`, REQ-87A849 / #295) with **no
admin bypass** — the whole call is rejected, the status never changes. Work that's actually underway
always has a deadline; without one it's invisible to the overdue views, the reminders and the on-time
metrics.

`update_request_status` takes an optional **`due_date`** param for exactly this: it's written in the
same `UPDATE` as the status, so one call satisfies the gate.

```
update_request_status(id, "in_progress")                        → rejected (HT004) if the request has no due_date
update_request_status(id, "in_progress", due_date: "2026-09-26") → OK, both set atomically

update_request(id, due_date: null)   // request is in_progress → rejected (HT004); no note authorizes it
```

Derive the date from `priority` exactly as Rule 8 does (critical = today / high +3 / mid +7 / low +14
business days) and announce it in the same correctable line. `due_date` is ignored on every transition
other than into `in_progress`. To genuinely drop a deadline, move the request out of `in_progress`
first (`blocked`/`under_review`/`cancelled`, with its own `note`), then clear it. Requests that were
already `in_progress` without a date before this rule shipped keep working — the gate only fires on a
real `status` or `due_date` change. A *backlog* request with no date reports HT003 first (mark it
`ready` before anything else).

---

## Foro: Markdown, Draft-First, and an Immutable Slug

The forum (`/foro`) is a separate surface from requests — no `status` machine, no backlog gate, no XP.
Eight tools, one hard boundary, and a handful of rules that will bite anyone who guesses. Full detail:
[references/forum-authoring.md](references/forum-authoring.md). Worked flow:
[examples/10-forum-post-publish.md](examples/10-forum-post-publish.md).

### The canonical flow

```
0. whoami                                  → check api_key_scopes has forum:write; check your role
1. list_forum_categories                   → real names + post_count (never invent one)
2. create_forum_post(content_markdown, …)  → lands as DRAFT by default. Read conversion.warnings
3. get_forum_post(slug)                    → read content_markdown back; check content_conversion.lossy
4. update_forum_post(append_markdown: …)   → additive edits (the safe kind)
5. update_forum_post(status: "published")  → this IS the publish tool; there is no other
6. add_forum_comment(content: "@[Nombre](uuid) …")  → mentions live in the text
```

### The rules

**1. Markdown only, both directions.** `content_markdown` / `append_markdown` in, `content_markdown`
out. **Never** BlockNote JSON on the tool surface — `forum_posts.content` is JSONB with no schema to
catch a hallucinated block, so a bad shape is stored happily and breaks the web renderer. Passing JSON
as `content_markdown` doesn't error either: it's parsed as literal text and you get a post whose body is
the JSON you pasted.

**2. `create_forum_post` defaults to `draft`, deliberately.** Your text just went through a converter
that silently drops constructs. Verify with `get_forum_post`, *then*
`update_forum_post(status: "published")`. There are no `publish_forum_post`/`unpublish_forum_post`
tools — `update_forum_post(status:)` absorbs both. `status: "published"` sets `published_at` only if it
was never set (an unpublish/republish keeps the original date); `status: "draft"` clears it.

**3. When `content_conversion.lossy` is `true`, use `append_markdown`, not `content_markdown`.**
`content_markdown` replaces the body wholesale. The web editor can produce colours, highlights,
alignment, underline and `video`/`audio`/`file`/`pageBreak`/`toggleListItem` blocks — Markdown can
represent none of them, so the Markdown you read back is a *degraded* copy. Writing it back makes the
degradation permanent, with no undo. `append_markdown` converts only the new text and concatenates it,
leaving everything already authored alone. Prefer it for every additive edit, lossy or not.

**4. The slug never changes — not even when the title does.** `generateSlug()` runs only inside
`create_forum_post`. `/foro/{slug}` is already shared, and `notifications.entity_id` stores the **slug**,
not the id — regenerating it would 404 every notification already sent. Keep the slug from the create
response (or use `id`); never derive one from a title, since it carries a random 4-char suffix.

**5. Categories are read-only through MCP.** No create, no delete — the taxonomy is human-curated in the
app. `list_forum_categories` returns `post_count` per category so you can see which ones are real
instead of inventing names; an unknown `category_names` entry throws and lists the valid options. Also:
`update_forum_post` takes `category_ids` only (no names), and it **replaces the post's whole category
list** — always send the complete intended set.

**6. No reaction and no view tools, on purpose.** `popularity_score` = `views ×1 + reactions ×3 +
comments ×5 + avg_read_seconds ×0.1` plus a recency bonus, and it drives the human-facing "Populares"
tab. A reaction is a person saying "this helped"; an agent emitting them at machine speed would weight a
human ranking, so there's nothing to call. `get_forum_post` still *reports* reactions, read-only, and
never registers a view or increments `view_count`. (Commenting *does* move the score, ×5 — so comment
because there's something to say, not to bump a post.)

**7. Mentions are parsed from `@[Nombre](uuid)` inside `content` — there is no `mentions` parameter.**
What a human reads and who got notified can never disagree. Every id is checked against `profiles` for
existence **and** `is_active`; any that fail reject the whole call, named. Resolve ids with `list_team` /
`whoami`. And mentions only work in **comments**: post bodies are never scanned, and `@[Ana](uuid)` in
`content_markdown` parses as a plain `@` plus a dead link.

**8. An admin cannot read another author's draft, but can publish or delete it.** The SELECT policy
(`forum_posts_select_published_or_own`, migration `00039`) has **no admin branch**; UPDATE and DELETE
do. `forum.ts` replicates both literally. `get_forum_post` on someone else's draft returns
`Post no encontrado o no tienes permiso para verlo.` — the same message as a nonexistent id, so ids
can't be enumerated. **That is the gate working, not a broken tool**: don't retry it, don't work around
it, don't report it. Relatedly, `list_forum_posts(status: "draft")` without being self-scoped
(`tab: "mine"`, or `author_id` = your own id) silently coerces to `published` and sets
`status_filter_coerced: true` — check that flag before saying "no hay borradores".

**9. Only `admin` and `developer` can create posts** (`forum_posts_insert_admin_developer`). `designer`
and `commercial` get `No tienes permiso para publicar en el foro. …`. Check `whoami().role` first.

**10. Existing API keys lack the new scopes.** `forum:read`/`forum:write` shipped after most keys were
created and are not granted retroactively, so a pre-existing key fails with
`Permiso insuficiente: se requiere 'forum:write'`. No retry fixes it — the user edits the key's
permissions in **HOT → Ajustes → API keys**. `whoami().api_key_scopes` lets you check before you write.

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
   → No due_date on the request? → update_request_status(id, "in_progress", due_date: "YYYY-MM-DD")
                                   (mandatory, ERRCODE HT004 otherwise — derive it from priority, Rule 8/19)
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
| Move a request with no `due_date` to `in_progress` | Rejected outright, `ERRCODE HT004` — the status never changes; work underway with no deadline is invisible to every overdue/on-time view | Pass `due_date` in the same call: `update_request_status(id, "in_progress", due_date: "YYYY-MM-DD")`, derived from `priority` (Rule 8/19) |
| Clear the `due_date` of a request that's already `in_progress` | Rejected outright, `ERRCODE HT004` — a `note` doesn't authorize it, unlike HT002 | Move it out of `in_progress` first (`blocked`/`under_review`/`cancelled`, with its own `note`), then clear the date (Rule 19) |
| Leave a request sitting in the backlog expecting it to show up on the board | It never will — `backlog_state` is invisible to `status`, nothing "graduates" it automatically | Refine it and flip `backlog_state: "ready"` explicitly (Rule 17) |
| Pass BlockNote JSON as `content_markdown` | No error — it's parsed as literal text, so the post's body becomes the JSON you pasted. `forum_posts.content` is schemaless JSONB; nothing catches it | Write plain Markdown; there is no parameter anywhere on the forum surface that accepts blocks (Foro rule 1) |
| Replace the whole post body with `content_markdown` just to add a paragraph | If the last `get_forum_post` said `content_conversion.lossy: true`, you overwrite real content with its degraded round-trip — colours, alignment, underline and media blocks gone, no undo | `update_forum_post(append_markdown: "…")` — converts only the new text and appends it (Foro rule 3) |
| Expect the slug to follow a changed title | It never does — `generateSlug` runs only at creation. `/foro/{slug}` is already shared and `notifications.entity_id` stores the slug, so rotating it would 404 every notification sent | Keep the slug from the create response, or use `id` (Foro rule 4) |
| Publish straight from `create_forum_post(status: "published")` | Dropped HTML, a reference link whose visible text vanished, or a split blockquote goes live *and* notifies everyone before anyone looks | Let it land as `draft` (the default), read `conversion.warnings` + `get_forum_post`, then `update_forum_post(status: "published")` (Foro rule 2) |
| Invent a category name in `category_names` | Rejected outright, listing the real names — and there is no `create_forum_category` to fall back on | `list_forum_categories` first; `post_count` shows which ones are actually in use (Foro rule 5) |
| Assume an admin can read another author's draft | The SELECT policy has no admin branch (UPDATE/DELETE do) — the read returns the same "not found" as a nonexistent id, by design | Accept it; the author publishes or pastes the content. Also check `status_filter_coerced` before concluding there are no drafts (Foro rule 8) |

> Full anti-patterns: [references/common-mistakes.md](references/common-mistakes.md)

---

## Cross-References

### Reference Documentation
- [Tool Catalog](references/tool-catalog.md) — Every tool with full params and examples
- [Forum Authoring](references/forum-authoring.md) — The supported Markdown subset, conversion warnings, `append_markdown` vs `content_markdown`, the immutable slug, draft/publish, why there are no reaction/view/category tools
- [Backlog and Readiness](references/backlog-and-readiness.md) — The HT003 gate, the "born ready" criterion, mandatory change notes, the HT004 due-date gate
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
- [Forum Post Publish](examples/10-forum-post-publish.md) — `whoami` → categories → draft → verify the conversion → `append_markdown` → publish → comment with a mention
