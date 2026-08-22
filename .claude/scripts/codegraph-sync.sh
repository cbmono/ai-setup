#!/usr/bin/env bash
#
# codegraph-sync.sh — bring every CodeGraph index under a workspace root up to date.
#
# WHY THIS EXISTS. CodeGraph rebuilds are manual. The `codegraph prompt-hook` registered
# on UserPromptSubmit only *injects context*; it never reindexes — and it is structurally
# blind here anyway, because it receives {prompt, cwd} and the human's sessions run in
# control-panel repos that have no .codegraph at all. Measured 2026-08-22: 21 of 35
# indexes were 41 days stale, and `codegraph status` reported `pendingChanges: {0,0,0}`
# while six days and 35 commits behind. An index that misreports its own freshness is
# worse than no index, because it invites trust it has not earned.
#
# Two things it deliberately does NOT do:
#
#   * It never runs `codegraph init`. Indexing a repo is the user's decision — the same
#     rule the CLAUDE.md guidance states. This only syncs what is already indexed.
#   * It never removes an index. `codegraph uninit` is a one-line manual call; a sweep
#     that deletes indexes is the shape that destroyed three agents' worktrees once
#     already (see ai-bridge/symlink/scripts/prune-worktrees.sh, report-only by design).
#
# Uses `codegraph sync` (incremental, "since last index"), not `codegraph index` (full
# rebuild from scratch) — pass --full to force the latter for one pass.
#
# Usage:
#   codegraph-sync.sh [--full] [--quiet] [root ...]
#
# With no root, defaults to ~/workspace. Exits 0 when every index synced, 1 if any
# failed, 2 on a usage error. Safe to run from cron or a launchd agent.
set -uo pipefail

FULL=0; QUIET=0; ROOTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --full)  FULL=1 ;;
    --quiet|-q) QUIET=1 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "codegraph-sync: unknown option $1" >&2; exit 2 ;;
    *)  ROOTS+=("$1") ;;
  esac
  shift
done
[ ${#ROOTS[@]} -gt 0 ] || ROOTS=("$HOME/workspace")

command -v codegraph >/dev/null 2>&1 || {
  echo "codegraph-sync: codegraph is not on PATH — nothing to do." >&2; exit 0; }

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$1"; }

ok=0; failed=0; empty=0
for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || { echo "codegraph-sync: no such directory: $root" >&2; failed=$((failed+1)); continue; }
  # -maxdepth 4 covers <root>/<group>/<repo>/.codegraph and one nesting level beyond.
  # `-type d` and no -L: an index reached only through a symlink belongs to whoever owns
  # the real path, and syncing it from here would be acting on someone else's repo.
  while IFS= read -r idx; do
    [ -n "$idx" ] || continue
    repo="$(dirname "$idx")"
    rel="${repo#"$HOME"/}"
    before="$(cd "$repo" && codegraph status --json 2>/dev/null | sed -n 's/.*"lastIndexed":"\([^"]*\)".*/\1/p')"
    if [ "$FULL" -eq 1 ]; then ( cd "$repo" && codegraph index . >/dev/null 2>&1 )
    else                       ( cd "$repo" && codegraph sync  . >/dev/null 2>&1 ); fi
    rc=$?
    after="$(cd "$repo" && codegraph status --json 2>/dev/null | sed -n 's/.*"lastIndexed":"\([^"]*\)".*/\1/p')"
    nodes="$(cd "$repo" && codegraph status --json 2>/dev/null | sed -n 's/.*"nodeCount":\([0-9]*\).*/\1/p')"
    if [ "$rc" -ne 0 ] || [ -z "$after" ]; then
      printf '  FAILED  %-46s (exit %s)\n' "$rel" "$rc" >&2; failed=$((failed+1)); continue
    fi
    # A zero-node index extracts nothing from this repo — usually an all-YAML or
    # all-SQL tree, neither of which CodeGraph has an extractor for. Name it: it costs
    # a sync every run and can only ever answer nothing.
    if [ "${nodes:-0}" = "0" ]; then
      say "  EMPTY   $rel  (0 nodes — no extractor for this repo; consider: cd '$repo' && codegraph uninit --force .)"
      empty=$((empty+1)); ok=$((ok+1)); continue
    fi
    if [ "$before" = "$after" ]; then say "  ok      $rel  (already current, $nodes nodes)"
    else                              say "  synced  $rel  ($before -> $after, $nodes nodes)"; fi
    ok=$((ok+1))
  done <<EOF
$(find "$root" -maxdepth 4 -name .codegraph -type d 2>/dev/null | sort)
EOF
done

say ""
say "codegraph-sync: $ok index(es) up to date, $failed failed, $empty empty."
[ "$failed" -eq 0 ]
