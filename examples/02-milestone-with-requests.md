# Example: Milestone with Requests

One milestone containing multiple related requests, all linked to a project.

---

## Scenario

Project "Portal de Clientes" needs a milestone for implementing user authentication.

## Flow

### Step 1: Get project context

```
list_projects()
→ Find "Portal de Clientes" → project_id: "proj-uuid"

list_milestones(project_id: "proj-uuid")
→ No authentication milestone exists yet

list_team()
→ "Ana Gómez" → dev-1-uuid  ·  "Luis Ortega" → dev-2-uuid
// Resolve names to UUIDs here, once. Never hardcode a UUID from memory.
```

### Step 2: Create the milestone

```
create_milestone(
  project_id: "proj-uuid",
  name: "Autenticación de usuarios",
  description: "Login, registro, recuperación de contraseña, y protección de rutas",
  start_date: "2026-05-15",
  target_date: "2026-05-30"
)
→ Returns: { id: "milestone-uuid" }
```

### Step 3: Create requests linked to milestone

```
// Request 1: Database
create_request(
  title: "Migration for auth tables",
  description: "Create users, sessions, and password_resets tables with RLS",
  priority: "high",
  category: "nuevo",
  project_id: "proj-uuid",
  milestone_id: "milestone-uuid",
  assignee_ids: ["dev-1-uuid"],
  estimated_hours: 6,
  due_date: "2026-05-18"
)
→ req-1-uuid

// Request 2: Backend
create_request(
  title: "Auth server actions (login, register, forgot password)",
  description: "Server actions with Zod validation, rate limiting, and email templates",
  priority: "high",
  category: "nuevo",
  project_id: "proj-uuid",
  milestone_id: "milestone-uuid",
  assignee_ids: ["dev-1-uuid"],
  estimated_hours: 12,
  due_date: "2026-05-23"
)
→ req-2-uuid

// Request 3: Frontend
create_request(
  title: "Auth UI pages (login, register, forgot password)",
  description: "Responsive forms with React Hook Form + Zod, loading states, error handling",
  priority: "mid",
  category: "nuevo",
  project_id: "proj-uuid",
  milestone_id: "milestone-uuid",
  assignee_ids: ["dev-2-uuid"],
  estimated_hours: 10,
  due_date: "2026-05-28"
)
→ req-3-uuid
```

### Step 4: Add checklists per request

```
// Request 1 checklist
add_checklist_item(request_id: "req-1-uuid", title: "Migration file created")
add_checklist_item(request_id: "req-1-uuid", title: "RLS policies for all tables")
add_checklist_item(request_id: "req-1-uuid", title: "Types regenerated")

// Request 2 checklist
add_checklist_item(request_id: "req-2-uuid", title: "Login action with rate limiting")
add_checklist_item(request_id: "req-2-uuid", title: "Register action with email verification")
add_checklist_item(request_id: "req-2-uuid", title: "Forgot password flow complete")
add_checklist_item(request_id: "req-2-uuid", title: "Zod schemas validated server-side")

// Request 3 checklist
add_checklist_item(request_id: "req-3-uuid", title: "Login page responsive")
add_checklist_item(request_id: "req-3-uuid", title: "Register page with validation")
add_checklist_item(request_id: "req-3-uuid", title: "Forgot password page")
add_checklist_item(request_id: "req-3-uuid", title: "Loading and error states")
```

### Step 5: Start milestone and execute requests

```
update_milestone(milestone_id: "milestone-uuid", status: "in_progress")

// Start request 1
update_request_status(id: "req-1-uuid", status: "in_progress")
create_github_issue_branch(request_id: "req-1-uuid", base_branch: "develop")
→ feature/10-migration-for-auth-tables

// ... development, checklist updates, PR ...
update_request_status(id: "req-1-uuid", status: "under_review")
create_github_pr(request_id: "req-1-uuid", body: "## Changes\n- Auth tables migration\n- RLS policies")
// ... merged ...
update_request_status(id: "req-1-uuid", status: "resolved")
```

Repeat for requests 2 and 3.

### Step 6: Complete milestone

```
// Verify all requests resolved
list_milestones(project_id: "proj-uuid")
→ All 3 requests in "Autenticación" milestone are "resolved"

update_milestone(milestone_id: "milestone-uuid", status: "completed")
```

---

## Key Takeaways

- All requests created with both `project_id` AND `milestone_id`
- Milestone started (`in_progress`) before its requests
- Each request follows: create → checklist → start → GitHub → review → resolve
- Milestone completed only after ALL requests resolved
