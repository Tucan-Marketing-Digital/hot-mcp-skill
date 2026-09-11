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

### Qué es global y qué es por proyecto

Tres piezas, y no van todas al mismo lugar:

| Pieza | Dónde | Por qué |
|---|---|---|
| Skill `hot-mcp-workflows` | **Global** | Conocimiento puro, igual en todos los repos |
| Agente `project-manager` | **Global** | Igual |
| Servidor MCP `hot-platform` | **Global** (alcance usuario) | La API key es personal, no del repo |
| `project-manager.config.json` | **Por proyecto** | UUID del proyecto, repos y rama base son específicos del repo |

O sea: se instala **una vez por persona**, y lo único que cada repo necesita es su
archivo de configuración — que el propio agente crea en el primer uso.

El config tiene dos niveles y se leen los dos:

- `~/.claude/project-manager.config.json` → solo `defaults` (ej. `base_branch`)
- `<repo>/.claude/project-manager.config.json` → los `projects` de ese repo

El del proyecto gana sobre el global en cualquier clave que ambos definan. Los datos
de proyecto nunca van al global.

### Servidor MCP

La skill **maneja** el servidor MCP de HOT — sin él no tiene con qué hablar.
Configuralo una vez por máquina:

```bash
claude mcp add -s user -t http hot-platform \
  https://mcp.hot.tucanmd.com/mcp \
  -H "Authorization: Bearer <tu-api-key>"
```

La API key se genera en HOT → Ajustes → API keys.

Con `-s project` se escribe en el `.mcp.json` del repo y queda versionado — la key
se comparte con todo el que clone, así que normalmente no es lo que querés.
`install.sh` detecta si el servidor ya está en alguno de los dos lugares y avisa si
falta.

### Poner en marcha un proyecto nuevo

1. `cd tu-repo`
2. Pedile a Claude: *"Usá el project-manager para listar mis solicitudes del proyecto X"*
3. El agente no encuentra `.claude/project-manager.config.json`, lo crea y se detiene
   pidiéndote el nombre del proyecto y sus repos
4. Respondés, el agente lo persiste, y a partir de ahí arranca solo

No hace falta correr `install.sh` por repo si ya lo instalaste global. Hacelo solo si
querés fijar la skill a una versión distinta en ese repo.

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
