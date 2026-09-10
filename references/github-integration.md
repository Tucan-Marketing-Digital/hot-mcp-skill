# GitHub Integration

How HOT MCP tools integrate with GitHub for full traceability from request to merge.

---

## Architecture

```
HOT Request ──→ GitHub Issue + Branch ──→ Commits ──→ PR (Closes #N) ──→ Merge ──→ Issue auto-closed
     │                   │                                    │
     └───────────────────┴────────────────────────────────────┘
                    request_github_links table
```

Both the MCP tools and the UI platform share the same utilities from `lib/github.ts`:
- `slugify()` — Title normalization
- `mapCategoryToPrefix()` — Category → branch prefix
- `mapCategoryToLabels()` — Category + priority → GitHub labels
- `githubFetch()` — API wrapper with Bearer token auth

---

## Branch Naming Convention

### Auto-generated format

```
{categoryPrefix}/{issueNumber}-{slug}
```

### Category → Prefix mapping

| Request category | Branch prefix | Example |
|-----------------|---------------|---------|
| `nuevo` (default) | `feature/` | `feature/42-user-dashboard` |
| `bug` | `bugfix/` | `bugfix/15-login-timeout` |
| `mejora` | `improvement/` | `improvement/28-cache-optimization` |

### Slug generation rules

1. Lowercase the title
2. Remove accents (NFD normalization)
3. Replace non-alphanumeric characters with dashes
4. Trim leading/trailing dashes
5. Limit to 50 characters

**Input**: `"Rediseño del Dashboard Principal"`
**Slug**: `rediseno-del-dashboard-principal`
**Branch**: `feature/42-rediseno-del-dashboard-principal`

### Custom branch names

Use `custom_branch_name` parameter to override:

```
create_github_issue_branch(
  request_id: "uuid",
  custom_branch_name: "feature/42-custom-name"
)
```

---

## GitHub Labels

Auto-generated from request category + priority:

| Category | Label |
|----------|-------|
| `bug` | `bug` |
| `mejora` | `enhancement` |
| `nuevo` | `feature` |

| Priority | Label |
|----------|-------|
| `high` | `priority: high` |
| `mid` | `priority: mid` |
| `low` | `priority: low` |

**Example**: A `bug` with `high` priority creates labels: `["bug", "priority: high"]`

Additional labels via `extra_labels` parameter (MCP only, not in UI).

---

## Issue Body

### MCP creates:
```
Solicitud HOT: [REQ-XXXXXX](https://app-url/triage/{request_id})

**Prioridad:** high
**Categoría:** nuevo
```

### UI creates:
```
Solicitud: [REQ-XXXXXX](https://app-url/triage/{request_id})
```

Both include a backlink to the HOT request for traceability.

---

## Pull Request Auto-Close

### How it works

Both MCP and UI prepend `Closes #N` to the PR body:

```
Closes #42

## Changes
- Created migration
- Added RLS policies

Solicitud HOT: [REQ-XXXXXX](https://app-url/triage/{request_id})
```

When the PR is merged into the default branch, GitHub automatically closes issue #42.

### Supported closing keywords

GitHub recognizes: `Closes`, `Fixes`, `Resolves` (and their variants). HOT uses `Closes #N`.

### Important

- The PR must merge into the **default branch** (usually `main` or `develop`) for auto-close to work
- Draft PRs don't auto-close until they're marked ready and merged
- If the PR is closed without merging, the issue stays open

---

## Database Persistence

Both MCP and UI write to the `request_github_links` table:

| Column | Set on issue+branch | Set on PR |
|--------|-------------------|-----------|
| `request_id` | Yes | — |
| `created_by` | Yes | — |
| `issue_url` | Yes | — |
| `issue_number` | Yes | — |
| `repo_full_name` | Yes | — |
| `branch_name` | Yes | — |
| `base_branch` | Yes | — |
| `pr_url` | — | Yes |
| `pr_number` | — | Yes |
| `pr_state` | — | Yes (`"open"` or `"draft"`) |

---

## Multi-Repo Projects

Projects can link to multiple GitHub repositories (e.g., `client`, `backend`, `mobile`).

**Single repo**: No need to specify — auto-selected.

**Multiple repos**: Use `repo_label` or `repo_url`:

```
// By label
create_github_issue_branch(request_id: "uuid", repo_label: "backend")

// By URL
create_github_issue_branch(request_id: "uuid", repo_url: "https://github.com/org/backend")
```

---

## Prerequisites Checklist

Before using GitHub tools, verify:

- [ ] User has GitHub OAuth connected in HOT Settings → Integrations
- [ ] Project has at least one linked GitHub repository
- [ ] For `create_github_pr`: branch exists and has commits pushed
- [ ] For multi-repo projects: know which `repo_label` to target

---

## Complete GitHub Flow

```
1. create_request(category: "nuevo", project_id, milestone_id)
2. update_request_status("in_progress")
3. create_github_issue_branch(request_id, base_branch: "develop")
   → Creates: Issue #42 + branch feature/42-slug
4. ... developer works, commits, pushes ...
5. update_request_status("under_review")
6. create_github_pr(request_id, body: "## Changes\n- ...")
   → Creates: PR with "Closes #42" auto-prepended
7. ... PR reviewed and merged ...
   → GitHub auto-closes Issue #42
8. update_request_status("resolved")
```
