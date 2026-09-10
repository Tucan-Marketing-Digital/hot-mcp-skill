# Example: Milestone Groups

Parallel and sequential milestone execution patterns using `depends_on`, PLUS real organizational
grouping using `create_milestone_group` / `group_id`. These are two different, complementary tools —
see the note below before reading the patterns.

---

## Two Kinds of "Grouping" — Don't Confuse Them

| | `depends_on` | `create_milestone_group` + `group_id` |
|---|---|---|
| What it does | Gates when a milestone can **start** | Organizes milestones into a named, **queryable** container |
| Scope | Between two individual milestones | A project-level entity (`list_milestone_groups`) |
| Affects execution order? | Yes | No |
| Affects `list_milestone_groups` output? | No | Yes |

They're independent and normally used **together**: put all of "Fase 1" in one `create_milestone_group`,
then use `depends_on` to sequence individual milestones inside (or across) that group. The patterns
below focus on `depends_on` for execution shape — assume every milestone in a real project would also
carry a `group_id` for its phase. See **Real-World Example** at the bottom for both combined.

---

## Concept

Milestones can be organized in groups:
- **Sequential**: B depends on A → B starts after A completes
- **Parallel**: A and B have no dependency → can run simultaneously
- **Mixed**: Parallel group feeds into a sequential gate

---

## Pattern 1: Sequential Chain

```
A → B → C (each waits for the previous)
```

```
create_milestone(project_id, name: "Phase 1: Database", ...)
→ milestone-a

create_milestone(project_id, name: "Phase 2: API", depends_on: "milestone-a", ...)
→ milestone-b

create_milestone(project_id, name: "Phase 3: Frontend", depends_on: "milestone-b", ...)
→ milestone-c
```

**Execution**:
```
[████ A ████] → [████ B ████] → [████ C ████]
```

**Use when**: Each phase strictly needs the previous one (e.g., can't build API without DB).

---

## Pattern 2: Parallel Group

```
A ─┐
B ─┤ (all independent, run simultaneously)
C ─┘
```

```
create_milestone(project_id, name: "Auth module", ...)
→ milestone-a (no depends_on)

create_milestone(project_id, name: "Notifications module", ...)
→ milestone-b (no depends_on)

create_milestone(project_id, name: "File storage module", ...)
→ milestone-c (no depends_on)
```

**Execution**:
```
[████ A: Auth ████████]
[████ B: Notifications ████]
[████ C: File Storage ██████]
```

**Use when**: Independent features that different developers can work on simultaneously.

---

## Pattern 3: Fan-out / Fan-in (Diamond)

```
     ┌→ B ─┐
A ───┤     ├──→ D
     └→ C ─┘
```

Phase A completes, then B and C run in parallel, then D waits for both.

```
create_milestone(project_id, name: "Database schema", ...)
→ milestone-a

create_milestone(project_id, name: "Backend API", depends_on: "milestone-a", ...)
→ milestone-b

create_milestone(project_id, name: "Admin panel", depends_on: "milestone-a", ...)
→ milestone-c

create_milestone(project_id, name: "Integration testing", depends_on: "milestone-b", ...)
→ milestone-d
// Note: depends_on only supports ONE dependency per milestone
// D depends on B. For D to also wait for C, manage manually.
```

**Execution**:
```
[████ A ████] → [████ B: API ████████]     → [████ D: Integration ████]
              → [████ C: Admin ██████████]
```

**Important**: `depends_on` supports a single milestone. For multiple dependencies (D waiting for both B and C), you must manage this manually — only start D when both B and C are completed.

### Manual gate pattern for multiple dependencies:

```
// Check both are done before starting D
list_milestones(project_id)
→ milestone-b: "completed" ✓
→ milestone-c: "completed" ✓
→ milestone-d: "pending"

// Both done, safe to start D
update_milestone(milestone_id: "milestone-d", status: "in_progress")
```

---

## Pattern 4: Phased Release

```
Phase 1 (MVP):     A1, A2, A3 (parallel)
Phase 2 (v1.1):    B1, B2 (parallel, after Phase 1)
Phase 3 (v1.2):    C1 (after Phase 2)
```

```
// Phase 1 — parallel milestones
create_milestone(project_id, name: "MVP: Core CRUD", ...)           → a1
create_milestone(project_id, name: "MVP: Auth", ...)                → a2
create_milestone(project_id, name: "MVP: Basic UI", ...)            → a3

// Phase 2 — depends on one Phase 1 milestone (gate)
create_milestone(project_id, name: "v1.1: Reports", depends_on: "a1", ...) → b1
create_milestone(project_id, name: "v1.1: Notifications", depends_on: "a2", ...) → b2

// Phase 3 — depends on Phase 2
create_milestone(project_id, name: "v1.2: Analytics dashboard", depends_on: "b1", ...) → c1
```

**Execution**:
```
Phase 1: [██ A1 ██] [██ A2 ██████] [██ A3 ████]
Phase 2:                            [██ B1 ████████] [██ B2 ██████]
Phase 3:                                              [██ C1 ████████████]
```

---

## Real-World Example: E-commerce Project

This version uses `create_milestone_group` for each phase (so `list_milestone_groups` reflects
real project structure, not just naming) COMBINED with `depends_on` for execution order within
and across phases — the pattern a real plan should follow:

```
whoami() → { id: "my-uuid", role: "admin" }   // resolve self first, for default assignments

// Create the phase containers
create_milestone_group(proj, name: "Foundation")   → group_foundation
create_milestone_group(proj, name: "Core Features") → group_core
create_milestone_group(proj, name: "Integration")   → group_integration
create_milestone_group(proj, name: "Polish")        → group_polish

// Foundation (parallel — same group, no depends_on between them)
create_milestone(proj, name: "Database schema & migrations", group_id: group_foundation) → db
create_milestone(proj, name: "Auth & user management", group_id: group_foundation)       → auth
create_milestone(proj, name: "Supabase Storage setup", group_id: group_foundation)       → storage

// Core features (different group, depends_on reaches back into Foundation)
create_milestone(proj, name: "Product catalog", group_id: group_core, depends_on: db)     → catalog
create_milestone(proj, name: "Shopping cart", group_id: group_core, depends_on: db)       → cart
create_milestone(proj, name: "Image upload", group_id: group_core, depends_on: storage)   → uploads

// Integration (depend on core)
create_milestone(proj, name: "Checkout flow", group_id: group_integration, depends_on: cart) → checkout
create_milestone(proj, name: "Order management", group_id: group_integration, depends_on: checkout) → orders

// Polish (last)
create_milestone(proj, name: "Email notifications", group_id: group_polish, depends_on: orders) → emails
create_milestone(proj, name: "Admin dashboard", group_id: group_polish, depends_on: orders)      → admin
```

```
Foundation:  [██ DB ██] [██ Auth ████] [██ Storage ██]
Core:                   [██ Catalog ████] [██ Cart ████] [██ Uploads ██]
Integration:                               [██ Checkout ████] [██ Orders ████]
Polish:                                                        [██ Emails ██] [██ Admin ██]
```

Later, `list_milestone_groups(proj)` returns the 4 phases directly — no name-parsing needed to
answer "what's in Foundation?" or "is Core Features done?".

---

## Key Takeaways

- `depends_on` accepts ONE milestone UUID (single dependency)
- For multiple dependencies, manually verify all are `completed` before starting
- Parallel milestones = no `depends_on` between them
- `group_id` (via `create_milestone_group`) organizes milestones into a queryable phase — independent of `depends_on`, use both together
- Create ALL milestones (and their group, if any) upfront before populating with requests
- Use `list_milestones` to verify dependency status before advancing; use `list_milestone_groups` to verify phase structure
