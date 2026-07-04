#!/usr/bin/env bash
#
# show-awaiting.sh — SessionStart hook (ai-bridge machinery).
#
# Surfaces the "🔴 Awaiting you" items from the generated DASHBOARD.md when a
# session starts, so the human sees what needs a decision (approve / answer /
# merge / unblock) before anything else. Prints to stdout; Claude Code adds
# SessionStart stdout to the session context.
#
# Self-detecting and safe to run anywhere: if there's no DASHBOARD.md (e.g. before
# the first /status or /pm-loop tick has generated it), or the "Awaiting you"
# section has no items, it exits 0 silently — so it no-ops cleanly in any non-bridge
# project that happens to inherit this hook.
set -euo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
file="$root/DASHBOARD.md"
[ -f "$file" ] || exit 0

# Extract the block under the "Awaiting you" heading, up to the next "## " heading.
block="$(awk '
  /^##[[:space:]].*Awaiting you/ { inblk=1; next }
  inblk && /^##[[:space:]]/       { exit }
  inblk                           { print }
' "$file" 2>/dev/null || true)"

# Action items are GFM bullets ("* ..."); ignore the italic description line.
items="$(printf '%s\n' "$block" | grep -E '^[[:space:]]*\* ' || true)"
[ -n "$items" ] || exit 0

count="$(printf '%s\n' "$items" | grep -c .)"
echo "🔔 ${count} item(s) need your input (DASHBOARD.md → Awaiting you):"
printf '%s\n' "$items" | sed -E 's/^[[:space:]]*\*[[:space:]]*/  • /'
echo "Surface these first. Refresh the board with /status; advance work with /pm-loop."
