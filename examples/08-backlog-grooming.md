# Example: Backlog Grooming

Refining requests sitting in `backlog_state: "backlog"` and moving them to `"ready"` so they can actually
be worked. Full mechanics: [backlog-and-readiness.md](../references/backlog-and-readiness.md).

---

## Scenario

A commercial user created three requests via the triage inbox without assignees or due dates — they
landed `backlog_state: "backlog"` automatically. A developer is about to start sprint planning and needs
to find them, refine them, and get them onto the kanban board.

---

## Step 1: Find what needs refinement

```
list_requests(backlog_state: "backlog", project_id: "proj-uuid")
→ {
    total: 3,
    results: [
      { id: "req-1-uuid", title: "Exportar reporte a Excel",      priority: "mid",  assignees: [], due_date: null },
      { id: "req-2-uuid", title: "Botón de deshacer en el editor", priority: "low",  assignees: [], due_date: null },
      { id: "req-3-uuid", title: "Caché de queries del dashboard", priority: "high", assignees: [], due_date: null }
    ]
  }
```

None of these has an assignee or a `due_date` — that's exactly why they're `backlog`, not a bug.

---

## Step 2: Resolve who's available

```
whoami() → { id: "my-uuid", name: "Carlos Rivas" }
list_team() → [ { id: "ana-uuid", name: "Ana Torres", role: "developer" }, ... ]
```

---

## Step 3: Refine and flip each one in the same call

**Trivial, no real steps → no checklist needed:**
```
update_request(
  id: "req-2-uuid",
  assignee_ids: ["ana-uuid"],
  due_date: "2026-09-24",          // low → +14 business days
  estimated_hours: 3,
  backlog_state: "ready"
)
```

**Has real steps → checklist first, then the flip:**
```
add_checklist_item(request_id: "req-1-uuid", title: "Endpoint que genera el .xlsx")
add_checklist_item(request_id: "req-1-uuid", title: "Botón de exportar en la UI del reporte")
add_checklist_item(request_id: "req-1-uuid", title: "Probado con reportes de 1000+ filas")

update_request(
  id: "req-1-uuid",
  assignee_ids: ["my-uuid"],
  due_date: "2026-09-19",          // mid → +7 business days
  estimated_hours: 8,
  backlog_state: "ready"
)
```

**High priority → shorter default, still refined before flipping:**
```
add_checklist_item(request_id: "req-3-uuid", title: "Identificar queries N+1 en el dashboard")
add_checklist_item(request_id: "req-3-uuid", title: "Agregar capa de caché con invalidación por proyecto")
add_checklist_item(request_id: "req-3-uuid", title: "Medir tiempo de carga antes/después")

update_request(
  id: "req-3-uuid",
  assignee_ids: ["ana-uuid"],
  due_date: "2026-09-15",          // high → +3 business days
  estimated_hours: 12,
  backlog_state: "ready"
)
```

---

## Step 4: Confirm they're on the board

```
list_requests(backlog_state: "ready", project_id: "proj-uuid", assignee_id: "ana-uuid")
→ req-2-uuid and req-3-uuid now show up
```

---

## What NOT to do — flip without refining

```
// Wrong: clears the backlog view but leaves every metric blind
update_request(id: "req-2-uuid", backlog_state: "ready")   // no assignee, no due_date, no estimate
```

This passes — the trigger only cares about `backlog_state` transitions being allowed from the request's
current `status`, not about which fields are filled in. It's a documentation/skill rule (Rule 17 in
[SKILL.md](../SKILL.md)), not a DB constraint — which is exactly why it's easy to skip and easy to get
wrong. The request is now visible on the kanban and *looks* done, but earns no XP signal, has no
deadline, and nobody's workload reflects it. Always refine in the same pass as the flip.

---

## Starting work afterward

Once `ready`, the request behaves like any other — the HT003 gate no longer applies:

```
update_request_status(id: "req-3-uuid", status: "in_progress")
create_github_issue_branch(request_id: "req-3-uuid")
```

A request that's still `backlog` at this point would reject the `update_request_status` call with
`ERRCODE HT003` — see [Mistake 21](../references/common-mistakes.md).
