# Example: Full Project Flow

Complete project lifecycle with chained milestones, multiple requests per milestone, and GitHub integration.

---

## Scenario

New project "Sistema de Facturación" with 3 sequential phases.

## Flow

### Phase 0: Project context

```
list_projects()
→ "Sistema de Facturación" → project_id: "proj-uuid"

list_team()
→ Get developer UUIDs for assignment
```

### Phase 1: Create milestone chain

```
// Milestone A: Database (no dependency — starts first)
create_milestone(
  project_id: "proj-uuid",
  name: "Esquema de base de datos",
  start_date: "2026-05-15",
  target_date: "2026-05-22"
)
→ milestone-a-uuid

// Milestone B: API (depends on A)
create_milestone(
  project_id: "proj-uuid",
  name: "API y Server Actions",
  start_date: "2026-05-22",
  target_date: "2026-06-05",
  depends_on: "milestone-a-uuid"
)
→ milestone-b-uuid

// Milestone C: Frontend (depends on B)
create_milestone(
  project_id: "proj-uuid",
  name: "Interfaz de usuario",
  start_date: "2026-06-05",
  target_date: "2026-06-19",
  depends_on: "milestone-b-uuid"
)
→ milestone-c-uuid
```

**Dependency chain**: A → B → C (sequential execution)

### Phase 2: Populate milestones with requests

```
// ─── Milestone A: Database ───
create_request(
  title: "Invoice and line_items tables migration",
  description: "PostgreSQL tables for invoices, line items, tax config",
  priority: "high", category: "nuevo",
  project_id: "proj-uuid", milestone_id: "milestone-a-uuid",
  assignee_ids: ["dev-1-uuid"],
  estimated_hours: 8, due_date: "2026-05-19"
)
→ req-a1

create_request(
  title: "RLS policies for billing tables",
  description: "Row-level security: admins full access, commercials read own invoices",
  priority: "high", category: "nuevo",
  project_id: "proj-uuid", milestone_id: "milestone-a-uuid",
  assignee_ids: ["dev-1-uuid"],
  estimated_hours: 4, due_date: "2026-05-21"
)
→ req-a2

// ─── Milestone B: API ───
create_request(
  title: "CRUD server actions for invoices",
  description: "Create, read, update, delete with Zod validation",
  priority: "high", category: "nuevo",
  project_id: "proj-uuid", milestone_id: "milestone-b-uuid",
  assignee_ids: ["dev-2-uuid"],
  estimated_hours: 16, due_date: "2026-05-30"
)
→ req-b1

create_request(
  title: "PDF invoice generation",
  description: "Server action to generate PDF with company template",
  priority: "mid", category: "nuevo",
  project_id: "proj-uuid", milestone_id: "milestone-b-uuid",
  assignee_ids: ["dev-2-uuid"],
  estimated_hours: 12, due_date: "2026-06-03"
)
→ req-b2

// ─── Milestone C: Frontend ───
create_request(
  title: "Invoice list page with filters",
  description: "Paginated table with status, date, and client filters",
  priority: "high", category: "nuevo",
  project_id: "proj-uuid", milestone_id: "milestone-c-uuid",
  assignee_ids: ["dev-3-uuid"],
  estimated_hours: 10, due_date: "2026-06-12"
)
→ req-c1

create_request(
  title: "Invoice detail and edit form",
  description: "Detail view with line item editor, tax calculation, PDF preview",
  priority: "high", category: "nuevo",
  project_id: "proj-uuid", milestone_id: "milestone-c-uuid",
  assignee_ids: ["dev-3-uuid"],
  estimated_hours: 14, due_date: "2026-06-18"
)
→ req-c2
```

### Phase 3: Execute Milestone A

```
update_milestone(milestone_id: "milestone-a-uuid", status: "in_progress")

// ── Request A1 ──
add_checklist_item(request_id: "req-a1", title: "Migration file created")
add_checklist_item(request_id: "req-a1", title: "Indexes on foreign keys")
add_checklist_item(request_id: "req-a1", title: "Types regenerated")

update_request_status(id: "req-a1", status: "in_progress")
create_github_issue_branch(request_id: "req-a1", base_branch: "develop")
→ feature/50-invoice-and-line-items-tables-migration

// ... dev works, updates checklist items ...
update_request_status(id: "req-a1", status: "under_review")
create_github_pr(request_id: "req-a1", body: "## Changes\n- Tables: invoices, line_items, tax_config\n- Indexes on FK columns")
// ... PR reviewed, merged ...
update_request_status(id: "req-a1", status: "resolved")

// ── Request A2 (same pattern) ──
// ... create checklist, start, branch, work, PR, resolve ...
update_request_status(id: "req-a2", status: "resolved")

// ── All A requests done ──
update_milestone(milestone_id: "milestone-a-uuid", status: "completed")
```

### Phase 4: Execute Milestone B (now unblocked)

```
update_milestone(milestone_id: "milestone-b-uuid", status: "in_progress")

// Same pattern for req-b1, req-b2...
// ... checklist → start → branch → work → PR → resolve ...

update_milestone(milestone_id: "milestone-b-uuid", status: "completed")
```

### Phase 5: Execute Milestone C (now unblocked)

```
update_milestone(milestone_id: "milestone-c-uuid", status: "in_progress")

// Same pattern for req-c1, req-c2...

update_milestone(milestone_id: "milestone-c-uuid", status: "completed")
```

### Phase 6: Verify project completion

```
list_milestones(project_id: "proj-uuid")
→ All 3 milestones: "completed"
→ All 6 requests: "resolved"

// Project is done!
```

---

## Timeline Visualization

```
Week 1-2:  [████ Milestone A: Database ████]
Week 3-4:                                    [████ Milestone B: API ████████]
Week 5-6:                                                                    [████ Milestone C: UI ████████]
```

## Key Takeaways

- Milestones created with `depends_on` chain BEFORE any requests
- Each milestone fully populated with requests before execution
- Milestones executed sequentially following dependency order
- Each request follows the full lifecycle: checklist → start → GitHub → review → resolve
- Milestone only completed when ALL its requests are resolved
- Next milestone starts only after dependency is completed
