# HOT MCP Workflows

**Status**: Production Ready
**Last Updated**: 2026-09-10
**Repo**: `Tucan-Marketing-Digital/hot-mcp-skill`
**Instalación**: ver abajo

---

## Auto-Trigger Keywords

Claude Code automatically discovers this skill when you mention:

### Primary Keywords
- hot mcp
- hot platform
- crear solicitud
- create request
- crear hito
- create milestone
- milestone groups
- create milestone group
- whoami
- who am i
- current user
- triage mcp
- github issue branch
- mcp workflow

### Secondary Keywords
- update request status
- link milestone
- checklist item
- create pr
- project workflow
- request lifecycle
- milestone dependencies
- depends_on
- solicitud hot
- hito hot

### Action Keywords
- list projects
- list requests
- list milestones
- list team
- get request
- get request history
- request history
- add comment
- add checklist
- update milestone
- stale requests
- list stale requests

### Backlog & Readiness Keywords
- backlog state
- mark as ready
- marcar como lista
- solicitud en backlog
- request stuck
- solicitud atascada
- HT001
- HT002
- HT003
- justification note
- nota de justificación
- blocked without note
- change due date reason

### GitHub Integration Keywords
- github issue
- github branch
- github pr
- auto-close issue
- branch naming
- bugfix branch
- feature branch
- improvement branch
- create_github_issue_branch
- create_github_pr

### Assignment & Scheduling Keywords
- asignar solicitud
- assign request
- assignee_ids
- sin asignar
- unassigned request
- fecha límite
- due date
- poner fecha
- estimated_hours
- horas estimadas
- prioridad y fecha
- default due date

### Error/Problem Keywords
- invalid transition
- request status error
- milestone not completing
- orphan request
- missing project_id
- missing milestone_id
- tarea sin asignar
- solicitud sin fecha
- métricas incompletas
- no aparece en vencidas
- no suma XP
- carga del equipo vacía

---

## What This Skill Does

Provides comprehensive workflows and best practices for the HOT Platform MCP tools:

- **Assignment & Scheduling (non-negotiable)** — every request is born with an assignee, a `due_date` and an `estimated_hours`; what each missing field breaks, and the priority-based date defaults
- **Backlog & Readiness (non-negotiable)** — a request in `backlog_state: "backlog"` cannot change `status` at all (`ERRCODE HT003`); the "born ready" criterion, the refine-before-flip checklist, and the mandatory justification notes (`ERRCODE HT001`/`HT002`) for blocking or moving a due date
- **Request Lifecycle** — From creation to resolution with proper state transitions
- **Milestone Management** — Creating, chaining dependencies, tracking completion
- **GitHub Integration** — Issue+branch creation, PR with auto-close, branch naming conventions
- **Checklists** — Acceptance criteria as definition of done
- **Progress Tracking** — Comments, mentions, blocker management
- **Project Planning** — Full lifecycle from milestone groups to sequential execution
- **Anti-Patterns** — Common mistakes with corrections

---

## Instalación

Instala la skill, el agente `project-manager` y su archivo de configuración.

### Global — disponible en todos tus proyectos

```bash
curl -fsSL https://raw.githubusercontent.com/Tucan-Marketing-Digital/hot-mcp-skill/main/install.sh | bash -s -- --global
```

Escribe en `~/.claude/`.

### Por proyecto — solo en el repo actual

```bash
cd tu-proyecto
curl -fsSL https://raw.githubusercontent.com/Tucan-Marketing-Digital/hot-mcp-skill/main/install.sh | bash
```

Escribe en `./.claude/` del proyecto.

### Desde un clon local

```bash
git clone https://github.com/Tucan-Marketing-Digital/hot-mcp-skill.git
bash hot-mcp-skill/install.sh [--global]
```

### Requisito

La skill **maneja** el servidor MCP de HOT — sin él no tiene con qué hablar.
Tu `.mcp.json` necesita el servidor `hot-platform` configurado con una API key
válida:

```json
{
  "mcpServers": {
    "hot-platform": {
      "type": "http",
      "url": "https://mcp.hot.tucanmd.com/mcp",
      "headers": { "Authorization": "Bearer <tu-api-key>" }
    }
  }
}
```

La API key se genera desde HOT, en Ajustes → API keys.

---

## Prerequisites

- HOT Platform MCP server configured in `.mcp.json`
- `gh auth login` completed (for private repo install + GitHub MCP tools)
- GitHub integration connected in HOT settings (for issue+branch+PR tools)

---

## File Structure

```
hot-mcp-workflows/
├── SKILL.md                          # Main entry point (incl. "Every Request Is Born Assigned and Dated", the backlog/readiness gate)
├── README.md                         # This file (auto-discovery)
├── references/
│   ├── tool-catalog.md               # All 25 tools with full params
│   ├── backlog-and-readiness.md      # HT003 status gate, "born ready" criterion, mandatory change notes (HT001/HT002)
│   ├── status-transitions.md         # State machines and rules
│   ├── github-integration.md         # Branch naming, auto-close
│   ├── common-mistakes.md            # Anti-patterns and corrections
│   └── naming-conventions.md         # Categories, priorities, formats
└── examples/
    ├── 01-single-request.md          # Standalone request
    ├── 02-milestone-with-requests.md # One milestone, N requests
    ├── 03-full-project-flow.md       # Complete project lifecycle
    ├── 04-bug-hotfix-flow.md         # Bug/hotfix with GitHub
    ├── 05-milestone-groups.md        # Parallel + sequential patterns
    ├── 06-progress-tracking.md       # Checklists, comments, blockers
    ├── 07-incorrect-usage.md         # What NOT to do
    ├── 08-backlog-grooming.md        # Refining and flipping backlog → ready
    └── 09-blocked-with-reason.md     # Blocking + due_date changes with mandatory notes
```
