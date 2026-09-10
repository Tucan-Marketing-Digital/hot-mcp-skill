#!/usr/bin/env bash
#
# hot-mcp-workflows — installer
#
#   Project scope (default) — installs into ./.claude/ of the current repo:
#     curl -fsSL https://raw.githubusercontent.com/Tucan-Marketing-Digital/hot-mcp-skill/main/install.sh | bash
#
#   Global scope — installs into ~/.claude/, available in every project:
#     curl -fsSL https://raw.githubusercontent.com/Tucan-Marketing-Digital/hot-mcp-skill/main/install.sh | bash -s -- --global
#
#   From a local clone:
#     bash install.sh [--global]
#
set -euo pipefail

REPO="Tucan-Marketing-Digital/hot-mcp-skill"
BRANCH="main"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'
info() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "${DIM}→${NC} $1"; }

# ── Scope ───────────────────────────────────────────────────────────────────

SCOPE="project"
for arg in "$@"; do
  case "$arg" in
    --global)  SCOPE="global" ;;
    --project) SCOPE="project" ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) fail "Unknown option: $arg (use --global or --project)" ;;
  esac
done

if [ "$SCOPE" = "global" ]; then
  ROOT="$HOME/.claude"
else
  ROOT="$PWD/.claude"
  # A project install only makes sense at a repo root.
  if [ ! -d .git ] && [ ! -f package.json ]; then
    warn "No .git or package.json here — installing into $ROOT anyway"
    warn "If you meant a machine-wide install, re-run with --global"
  fi
fi

echo ""
echo "━━━ hot-mcp-workflows ━━━"
echo "Scope:  $SCOPE"
echo "Target: $ROOT"
echo ""

SKILL_DST="$ROOT/skills/hot-mcp-workflows"
AGENT_DST="$ROOT/agents/project-manager.md"

mkdir -p "$SKILL_DST" "$ROOT/agents" "$ROOT/agent-memory/project-manager"

# ── Source: local clone or remote ───────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/SKILL.md" ]; then
  step "Installing from local clone"
  rm -rf "$SKILL_DST"
  mkdir -p "$SKILL_DST"
  # Everything except the installer itself and the agent (installed separately)
  ( cd "$SCRIPT_DIR" && tar cf - \
      --exclude=install.sh --exclude=agent --exclude=.git --exclude=LICENSE . ) \
    | ( cd "$SKILL_DST" && tar xf - )
  cp "$SCRIPT_DIR/agent/project-manager.md" "$AGENT_DST"
  info "Skill and agent copied"
else
  step "Downloading from $REPO"
  FILES=(
    "SKILL.md" "README.md"
    "references/tool-catalog.md" "references/status-transitions.md"
    "references/github-integration.md" "references/common-mistakes.md"
    "references/naming-conventions.md" "references/backlog-and-readiness.md"
    "examples/01-single-request.md" "examples/02-milestone-with-requests.md"
    "examples/03-full-project-flow.md" "examples/04-bug-hotfix-flow.md"
    "examples/05-milestone-groups.md" "examples/06-progress-tracking.md"
    "examples/07-incorrect-usage.md" "examples/08-backlog-grooming.md"
    "examples/09-blocked-with-reason.md"
  )
  mkdir -p "$SKILL_DST/references" "$SKILL_DST/examples"
  for f in "${FILES[@]}"; do
    curl -fsSL "$RAW/$f" -o "$SKILL_DST/$f" \
      || fail "Download failed: $f — check your connection, or clone the repo and run install.sh locally"
  done
  curl -fsSL "$RAW/agent/project-manager.md" -o "$AGENT_DST" \
    || fail "Failed to download the project-manager agent"
  info "Skill and agent downloaded"
fi

# ── Agent memory ────────────────────────────────────────────────────────────

touch "$ROOT/agent-memory/project-manager/MEMORY.md"

# ── Config ──────────────────────────────────────────────────────────────────

CONFIG="$ROOT/project-manager.config.json"
if [ ! -f "$CONFIG" ]; then
  cat > "$CONFIG" << 'CONF'
{
  "defaults": {
    "base_branch": "develop"
  },
  "projects": {}
}
CONF
  info "Config created"
else
  warn "Config already existed — left untouched"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "━━━ Done ━━━"
echo ""
echo "  $SKILL_DST/"
echo "  $AGENT_DST"
echo "  $CONFIG"
echo ""

if [ "$SCOPE" = "global" ]; then
  echo "Installed globally — available in every project on this machine."
else
  echo "Installed for this project only."
  echo "For a machine-wide install, re-run with --global"
fi

echo ""
echo "Requirement: the hot-platform MCP server must be configured in .mcp.json"
echo "with a valid API key. The skill drives that server — without it, it has"
echo "nothing to talk to."
echo ""
echo "First use — ask Claude:"
echo "  \"Usá el project-manager para listar mis solicitudes del proyecto X\""
echo ""
