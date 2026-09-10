# Example: Bug / Hotfix Flow

Handling a bug report with GitHub integration using the `bug` category.

---

## Scenario

Production bug: "Invoice PDF generation crashes when line items have special characters (ñ, á, é)."

## Flow

### Step 1: Create bug request

```
create_request(
  title: "PDF generation crashes with special characters",
  description: "Invoice PDF generation throws encoding error when line items contain ñ, á, é, or other Latin characters. Stack trace points to font encoding in pdf-lib. Affects all Spanish-language invoices.",
  priority: "high",
  category: "bug",
  project_id: "proj-uuid",
  milestone_id: "milestone-uuid",
  assignee_ids: ["dev-uuid"],
  due_date: "2026-05-16",
  estimated_hours: 3
)
→ req-uuid
```

Note: `category: "bug"` → branch prefix will be `bugfix/`.

### Step 2: Define acceptance criteria

```
add_checklist_item(request_id: "req-uuid", title: "Root cause identified")
add_checklist_item(request_id: "req-uuid", title: "Fix handles all Latin-1 special characters")
add_checklist_item(request_id: "req-uuid", title: "Existing invoices re-generateable without error")
add_checklist_item(request_id: "req-uuid", title: "Test with edge cases: emojis, CJK, long strings")
```

### Step 3: Start work with GitHub

```
update_request_status(id: "req-uuid", status: "in_progress")

create_github_issue_branch(
  request_id: "req-uuid",
  base_branch: "develop"
)
→ Creates:
  - Issue #55 with labels ["bug", "priority: high"]
  - Branch: bugfix/55-pdf-generation-crashes-with-special-ch
```

### Step 4: Document findings

```
add_comment(
  request_id: "req-uuid",
  content: "Root cause: pdf-lib uses WinAnsiEncoding by default which doesn't support characters outside Latin-1 range. Fix: embed custom font with full Unicode support."
)

update_checklist_item(id: "item-1-uuid", is_complete: true)
```

### Step 5: Complete fix and submit PR

```
update_checklist_item(id: "item-2-uuid", is_complete: true)
update_checklist_item(id: "item-3-uuid", is_complete: true)
update_checklist_item(id: "item-4-uuid", is_complete: true)

update_request_status(id: "req-uuid", status: "under_review")

create_github_pr(
  request_id: "req-uuid",
  body: "## Bug Fix\n- Embedded Geist font with full Unicode support in PDF generation\n- Replaced WinAnsiEncoding with custom font encoding\n- Tested with: ñ, á, é, ü, ö, emojis, CJK characters\n\n## Root Cause\npdf-lib default WinAnsiEncoding only supports 256 code points"
)
→ PR with "Closes #55" auto-prepended
```

### Step 6: Merge and resolve

```
// After PR review and merge:
// GitHub auto-closes Issue #55
update_request_status(id: "req-uuid", status: "resolved")
```

---

## Hotfix Variant (production-critical)

For critical production bugs that need `main` as base:

```
create_github_issue_branch(
  request_id: "req-uuid",
  base_branch: "main"    // ← hotfix from main, not develop
)
→ bugfix/55-critical-fix

// After merge to main, also merge back to develop
```

---

## Key Differences from Feature Flow

| Aspect | Feature | Bug |
|--------|---------|-----|
| Category | `nuevo` | `bug` |
| Branch prefix | `feature/` | `bugfix/` |
| GitHub labels | `["feature", ...]` | `["bug", ...]` |
| Base branch | `develop` | `develop` (or `main` for hotfixes) |
| Checklist focus | Implementation criteria | Root cause + regression tests |
| Comments focus | Design decisions | Root cause analysis |
