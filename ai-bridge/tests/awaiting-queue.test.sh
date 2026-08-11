#!/usr/bin/env bash
# Exercises the SessionStart awaiting-you queue in show-awaiting.sh.
#
# AWAITING.md is a deletable capability file, like AUTONOMY.md: its ABSENCE means
# the queue is off, and that must be silent rather than an error. These cases pin
# both halves of the contract — the off switch, and the exact layout the
# project-manager is required to write (the hook greps for the literal
# "## 🔴 Awaiting you" heading and "* " bullets, so a reshape would silently
# empty the nudge instead of failing loudly).
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/symlink/.claude/hooks/show-awaiting.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

setup() { rm -rf "$TMP/inst"; mkdir -p "$TMP/inst"; }

# The layout the project-manager agent is specified to write. Kept verbatim here
# so a drift in either place fails this test.
write_queue() {
  cat > "$TMP/inst/AWAITING.md" <<'EOF'
# Awaiting you

Derived and gitignored — **do not hand-edit**. Rewritten each `/pm-loop` tick
from `projects/*/tasks/*.md`. Delete this file to turn the queue off for good.
Last refreshed: 2026-08-11T10:04:00Z.

## 🔴 Awaiting you (5)
* ✅ **approve** — [Harden CI](/projects/ci/tasks/task-001.md) · refined & clean, promote `draft → ready`
* ❓ **answer** — [Pick a region](/projects/ci/tasks/task-002.md) · Q1: which region?
* 🔀 **merge** — [Bump deps](/projects/deps/tasks/task-004.md) · [monorepo#2725](https://github.com/acme/monorepo/pull/2725)
* ⛔ **unblock** — [Rotate token](/projects/deps/tasks/task-005.md) · needs a new npm token
* 🏁 **close** — [CI hardening](/projects/ci/project.md) · all tasks terminal → `/close-project ci`
EOF
}

check() { # <name> <expected-item-count: 0 = silent>
  local name="$1" expect="$2" out rc
  out="$(CLAUDE_PROJECT_DIR="$TMP/inst" bash "$HOOK" 2>&1)"; rc=$?
  local got
  got="$(printf '%s' "$out" | grep -c '^  • ' || true)"
  if [ "$rc" -eq 0 ] && [ "$got" = "$expect" ]; then
    printf '  PASS  %-52s (%s item(s), rc=%s)\n' "$name" "$got" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-52s expected %s item(s) rc=0, got %s (rc=%s)\n' "$name" "$expect" "$got" "$rc"
    printf '        output: %s\n' "$(printf '%s' "$out" | head -4 | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

# --- absence is the off switch, and it must be silent ----------------------
setup
check "no AWAITING.md -> silent no-op (queue off)" 0

# Proves the hook is safe to inherit in any non-bridge project.
setup; printf 'unrelated project\n' > "$TMP/inst/README.md"
check "non-bridge project -> silent no-op" 0

# A pre-rename leftover must NOT be read: the rename has to be a real cutover,
# not a fallback that keeps a stale board alive.
setup; printf '## 🔴 Awaiting you (9)\n* stale board item\n' > "$TMP/inst/DASHBOARD.md"
check "stale DASHBOARD.md ignored after rename" 0

# --- the layout contract with the project-manager --------------------------
setup; write_queue
check "PM layout -> all five verb items surfaced" 5

setup; printf '# Awaiting you\n\n## 🔴 Awaiting you (0)\n_None._\n' > "$TMP/inst/AWAITING.md"
check "empty queue (_None._) -> silent, not a blank nudge" 0

# Sections after the queue must not bleed in, so a future addition below it
# can't inflate the startup nudge.
setup; write_queue
printf '\n## Notes\n* not an action item\n' >> "$TMP/inst/AWAITING.md"
check "trailing section not counted as items" 5

# Guards the heading contract: reshape it and the nudge empties silently, which
# is exactly the failure this test exists to catch.
setup; write_queue
sed -i.bak 's/^## 🔴 Awaiting you (5)/## Things To Do/' "$TMP/inst/AWAITING.md"
check "renamed heading -> nudge empties (documents the coupling)" 0

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
