#!/usr/bin/env bash
#
# show-todos.sh — SessionStart hook (ai-bridge machinery).
#
# Surfaces the control panel's OPEN todos when a session starts, by printing them
# to stdout (Claude Code adds SessionStart stdout to the session context). Reads
# the single checklist at <project-root>/todos/todos.md.
#
# Self-detecting and safe to run anywhere: if there's no todos.md or no open
# items, it exits 0 silently — so it no-ops cleanly in any non-bridge project that
# happens to inherit this hook.
set -euo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
file="$root/todos/todos.md"
[ -f "$file" ] || exit 0

# Open items = GFM unchecked tasks: lines like "- [ ] ..."
open="$(grep -E '^[[:space:]]*- \[ \]' "$file" 2>/dev/null || true)"
[ -n "$open" ] || exit 0

count="$(printf '%s\n' "$open" | grep -c . )"
echo "📋 This control panel has ${count} open todo(s) (todos/todos.md):"
printf '%s\n' "$open" | sed -E 's/^[[:space:]]*- \[ \][[:space:]]*/  • /'
echo "Surface these to the user first. Add with /todo <text>; close with /todo done <text>."
