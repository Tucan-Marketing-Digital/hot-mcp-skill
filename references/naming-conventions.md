# Naming Conventions

Standard values for categories, priorities, domains, dates, and branch prefixes in HOT.

---

## Request Categories

| Value | Spanish label | GitHub branch prefix | GitHub label |
|-------|--------------|---------------------|--------------|
| `nuevo` | Nuevo (new feature) | `feature/` | `feature` |
| `mejora` | Mejora (improvement) | `improvement/` | `enhancement` |
| `bug` | Bug (defect) | `bugfix/` | `bug` |

**Default**: `nuevo` when not specified.

---

## Request Priorities

| Value | Label | GitHub label | Default `due_date` when the user gives none |
|-------|-------|-------------|---------------------------------------------|
| `critical` | P0 Crítica | `priority: critical` | **today** — same day, no business-day math |
| `high` | P1 Alta | `priority: high` | today **+ 3 business days** |
| `mid` | P2 Media | `priority: mid` | today **+ 7 business days** |
| `low` | P3 Baja | `priority: low` | today **+ 14 business days** |

Priority is not only a label — it is the input to the date default. Setting the priority honestly is
what makes the default land in a sensible place. `priority` has no API default (the field is required)
— if the user didn't state one, the convention default is `mid` (P2), not `high`.

`critical` is reserved for genuinely urgent work (production down, whole team blocked) — it's not a way
to jump the queue. Overusing it erodes it as a signal; see
[common-mistakes.md](common-mistakes.md) for the anti-pattern.

---

## Mandatory Fields at Creation (Convention, Not API)

The MCP schema marks these optional. **The convention makes them required**, because HOT's metrics are
computed from exactly these three columns. Full breakdown of what each missing field breaks:
[common-mistakes.md → Mistake 17 and 20](common-mistakes.md).

| Field | Default when the user specifies nothing |
|-------|----------------------------------------|
| `assignee_ids` | The API-key owner (`whoami`). Named person → resolve via `list_team`. **Never empty.** |
| `due_date` | Derived from `priority` (table above) |
| `estimated_hours` | Estimated from the described scope (buckets below) |

Every derived value is announced in one correctable line together with the request code:

```
Creada REQ-A1B2C3 — asignada a Carlos Rivas, vence 2026-09-04
(default de prioridad alta: +3 días hábiles), estimada en 6 h.
Decime si ajusto fecha, horas o responsable.
```

---

## `estimated_hours` Buckets

These are the exact buckets `calculate_request_xp` reads to set the effort base, so an estimate that
lands in the right bucket matters more than one that is precise to the hour:

| Estimate | XP effort base |
|----------|----------------|
| not set | 30 (the floor — what an unestimated request is worth) |
| 1–4 h | 50 |
| 5–16 h | 80 |
| 17–40 h | 120 |
| 41 h+ | 160 |

On top of the base, setting `estimated_hours` at all adds `+0.15` to the completeness multiplier, and
setting `due_date` adds `+0.10` (multiplier starts at `0.50`, caps at `1.00`).

---

## Request Domains

| Value | Description |
|-------|-------------|
| `development` | Code, infrastructure, DevOps |
| `design` | UI/UX, visual, branding |
| `global` | Cross-functional, process, general |

**Default**: `development` when not specified.

---

## Request Statuses

| Value | Spanish label | Description |
|-------|--------------|-------------|
| `pending` | Pendiente | Awaiting triage |
| `assigned` | Asignada | Assigned, not started |
| `in_progress` | En progreso | Active work |
| `blocked` | Bloqueada | Waiting on dependency |
| `under_review` | En revisión | Code complete, reviewing |
| `resolved` | Resuelta | Done |
| `cancelled` | Cancelada | Abandoned |

---

## Milestone Statuses

| Value | Spanish label |
|-------|--------------|
| `pending` | Pendiente |
| `in_progress` | En progreso |
| `completed` | Completado |
| `skipped` | Omitido |

---

## Date Format

Always use **ISO 8601**: `YYYY-MM-DD`

```
"2026-05-15"    ← correct
"15/05/2026"    ← wrong
"May 15, 2026"  ← wrong
```

Used in: `due_date`, `start_date`, `target_date`.

**Business days**: the priority defaults above count business days — skip Saturdays and Sundays when
adding 3, 7 or 14.

**Check today's weekday with a tool before you count.** Do not recall it from memory: getting the
anchor wrong by one day silently shifts every derived date. `+3` and `+7` often survive a wrong
anchor (the weekend skip lands the same), so the error hides — `+14` crosses an extra weekend and
is where it surfaces. The tell is a `due_date` that lands on a Saturday or Sunday: if a derived
date falls on a weekend, the anchor was wrong, not the rule.

*Real case, 2026-09-01*: the day was taken to be Monday; it was Tuesday. `high` (Sep 4) and `mid`
(Sep 10) came out right by coincidence, `low` came out as Saturday Sep 19 instead of Monday Sep 21,
and four requests had to be rewritten.

---

## Branch Naming

### Pattern
```
{prefix}/{issueNumber}-{slug}
```

### Slug Rules
- Lowercase
- No accents (NFD normalized)
- Non-alphanumeric → dash
- No leading/trailing dashes
- Max 50 characters

### Examples

| Request title | Category | Issue # | Branch name |
|--------------|----------|---------|-------------|
| "Dashboard de usuario" | `nuevo` | 42 | `feature/42-dashboard-de-usuario` |
| "Fix login timeout" | `bug` | 15 | `bugfix/15-fix-login-timeout` |
| "Optimizar caché de queries" | `mejora` | 28 | `improvement/28-optimizar-cache-de-queries` |
| "Rediseño del módulo de facturación completo" | `nuevo` | 100 | `feature/100-rediseno-del-modulo-de-facturacion-c` |

---

## Comment Mentions

Format: `@[Display Name](user-uuid)`

```
"@[Juan Perez](550e8400-e29b-41d4-a716-446655440000) please review"
```

Get UUIDs from `list_team()`.

---

## GitHub Labels

Auto-generated combinations:

| Category + Priority | Labels |
|--------------------|--------|
| `nuevo` + `high` | `["feature", "priority: high"]` |
| `bug` + `mid` | `["bug", "priority: mid"]` |
| `mejora` + `low` | `["enhancement", "priority: low"]` |
| `nuevo` + (none) | `["feature"]` |

Extra labels can be added via `extra_labels` parameter (MCP only).

---

## Request Code

Auto-generated by the system: `REQ-XXXXXX` (6 random alphanumeric chars).

Not user-configurable. Used in GitHub issue body for backlinks.
