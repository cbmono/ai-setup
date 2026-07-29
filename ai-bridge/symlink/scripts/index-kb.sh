#!/usr/bin/env bash
# index-kb.sh — build/refresh a local CodeGraph index for each product repo under
# <reposRoot>, so role agents can navigate code (`codegraph explore` / the codegraph
# MCP) instead of blind-grepping. 100% local — no code leaves the machine.
#
# OPTIONAL integration. Requires the `codegraph` CLI on PATH
# (`npm i -g @colbymchenry/codegraph`); see ai-bridge/README.md "Local code
# intelligence (codegraph, optional)". Safe to re-run — incremental (`sync` after
# the first index).
#
# Run from a control-panel instance root (reads `reposRoot` from
# instance.config.json). Generic: no org/repo/path literals.
#
# Usage:
#   scripts/index-kb.sh                 # index/refresh every product repo
#   scripts/index-kb.sh --with-serena   # also warm Serena's LSP cache (if installed)
#
# Repos skipped by default: worktrees (_wt), instance dirs (_ai-bridge-*), and any
# non-git directory. Add more (infra/assets repos with no useful call graph) via
# `codegraphSkip` in instance.config.json (space-separated) or $CODEGRAPH_SKIP.
set -uo pipefail

WITH_SERENA=0
case "${1:-}" in
  --with-serena) WITH_SERENA=1 ;;
  "") ;;
  *) echo "usage: $0 [--with-serena]" >&2; exit 2 ;;
esac

command -v codegraph >/dev/null 2>&1 || {
  echo "index-kb: codegraph not found on PATH. Install with:" >&2
  echo "  npm i -g @colbymchenry/codegraph" >&2
  exit 1
}

CONFIG=instance.config.json
if [[ ! -f "$CONFIG" ]]; then
  echo "index-kb: run from a control-panel instance root (no $CONFIG here)." >&2
  exit 1
fi

# reposRoot from config; expand a leading ~ to $HOME (same parse as prune-worktrees).
REPOS_ROOT=$(grep -o '"reposRoot"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" \
  | sed 's/.*:[[:space:]]*"//; s/"$//')
REPOS_ROOT=${REPOS_ROOT/#\~/$HOME}
if [[ -z "$REPOS_ROOT" || ! -d "$REPOS_ROOT" ]]; then
  echo "index-kb: reposRoot ('$REPOS_ROOT') not found — check $CONFIG." >&2
  exit 1
fi
# Canonicalize so path handling lines up with symlinked reposRoots.
REPOS_ROOT=$(cd "$REPOS_ROOT" && pwd -P)

# Optional extra skips: config scalar `codegraphSkip` (space-separated) + $CODEGRAPH_SKIP.
CONFIG_SKIP=$(grep -o '"codegraphSkip"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" \
  | sed 's/.*:[[:space:]]*"//; s/"$//') || true
SKIP="${CONFIG_SKIP:-} ${CODEGRAPH_SKIP:-}"

if [[ "$WITH_SERENA" == 1 ]] && ! command -v serena >/dev/null 2>&1; then
  echo "index-kb: --with-serena given but serena not on PATH — skipping Serena." >&2
  WITH_SERENA=0
fi

# Defensive per-repo exclude so heavy dirs never get indexed.
CG_EXCLUDE='{"exclude":["**/node_modules/**","**/dist/**","**/build/**","**/.next/**","**/coverage/**","**/*.min.js","**/*.map"]}'

is_skipped() {
  local name=$1 s
  case "$name" in _wt|_ai-bridge-*) return 0 ;; esac
  for s in $SKIP; do [[ "$name" == "$s" ]] && return 0; done
  return 1
}

indexed=0; skipped=0
for dir in "$REPOS_ROOT"/*/; do
  dir=${dir%/}
  repo=$(basename "$dir")
  [[ -e "$dir/.git" ]] || continue          # not a git repo/worktree → skip
  if is_skipped "$repo"; then echo "-- skip $repo"; skipped=$((skipped+1)); continue; fi

  [[ -f "$dir/codegraph.json" ]] || printf '%s\n' "$CG_EXCLUDE" > "$dir/codegraph.json"

  if [[ -d "$dir/.codegraph" ]]; then
    echo "== [$repo] codegraph sync"
    codegraph sync "$dir" >/dev/null 2>&1 && echo "   synced"
  else
    echo "== [$repo] codegraph init"
    codegraph init "$dir" >/dev/null 2>&1 && echo "   indexed"
  fi
  indexed=$((indexed+1))

  if [[ "$WITH_SERENA" == 1 ]]; then
    echo "== [$repo] serena index"
    yes N | serena project index "$dir" --log-level ERROR >/dev/null 2>&1 && echo "   serena cache warmed"
  fi
done

echo "---"
printf 'index-kb: %d repo(s) indexed, %d skipped.\n' "$indexed" "$skipped"
echo 'Query with: codegraph explore "<question>" -p <repo-path>  (or the codegraph MCP tools).'
