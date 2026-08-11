#!/usr/bin/env bash
# Exercises install.sh's adopt_keys() — the ONE place the installer edits a
# user's real ~/.claude/settings.json rather than symlinking it.
#
# The danger it guards: that file can hold permissions, env vars, and plugin
# choices a person tuned by hand. So the contract is narrow and every clause
# below is a case here — it adds only absent keys, never reverts a value the
# user chose, backs up before writing, and leaves a file it can't parse alone.
#
# Runs the installer against a throwaway CLAUDE_CONFIG_DIR, so it never touches
# the real ~/.claude.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$REPO/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

# Fresh throwaway config dir; echoes its path.
newdir() { local d="$TMP/c$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }
run()    { CLAUDE_CONFIG_DIR="$1" bash "$INSTALL" >"$TMP/out" 2>&1; }

ok() { # <name> <condition-description> <actual> <expected>
  if [ "$3" = "$4" ]; then
    printf '  PASS  %-56s (%s)\n' "$1" "$3"; pass=$((pass+1))
  else
    printf '  FAIL  %-56s expected %s, got %s\n' "$1" "$4" "$3"
    printf '        installer said: %s\n' "$(tr '\n' '|' < "$TMP/out" | tail -c 220)"
    fail=$((fail+1))
  fi
}

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed (adopt_keys needs it)"; exit 0; }

# --- absent keys get merged, everything else survives -----------------------
d="$(newdir 1)"
cat > "$d/settings.json" <<'EOF'
{
  "permissions": { "allow": ["Bash(my-own-tool:*)"], "deny": ["Bash(sudo:*)"] },
  "env": { "MY_PATH": "/keep/me" },
  "enabledPlugins": { "mine@somewhere": true }
}
EOF
run "$d"
ok "statusLine merged into existing file"   . "$(jq -r 'has("statusLine")' "$d/settings.json")" true
ok "outputStyle merged into existing file"  . "$(jq -r '.outputStyle' "$d/settings.json")" Brief
ok "user permissions preserved"             . "$(jq -r '.permissions.allow[0]' "$d/settings.json")" 'Bash(my-own-tool:*)'
ok "user deny rules preserved"              . "$(jq -r '.permissions.deny[0]' "$d/settings.json")" 'Bash(sudo:*)'
ok "user env preserved"                     . "$(jq -r '.env.MY_PATH' "$d/settings.json")" /keep/me
ok "user plugins preserved"                 . "$(jq -r '.enabledPlugins["mine@somewhere"]' "$d/settings.json")" true
ok "backup written before edit"             . "$(ls "$d" | grep -c 'settings.json.bak.')" 1

# --- re-running must not re-edit or re-backup ------------------------------
run "$d"
ok "re-run makes no second backup"          . "$(ls "$d" | grep -c 'settings.json.bak.')" 1

# --- the user's own value always wins -------------------------------------
d="$(newdir 2)"
printf '{"outputStyle":"Explanatory","permissions":{"allow":[]}}\n' > "$d/settings.json"
run "$d"
ok "own outputStyle NOT reverted"            . "$(jq -r '.outputStyle' "$d/settings.json")" Explanatory
ok "absent statusLine still added alongside" . "$(jq -r 'has("statusLine")' "$d/settings.json")" true

d="$(newdir 3)"
printf '{"statusLine":{"type":"command","command":"my-own-line"}}\n' > "$d/settings.json"
run "$d"
ok "own statusLine NOT overwritten"          . "$(jq -r '.statusLine.command' "$d/settings.json")" my-own-line

# --- unparseable input must be left exactly as found ----------------------
d="$(newdir 4)"
printf '{ "permissions": { "allow": [] }, }\n' > "$d/settings.json"   # trailing comma
cksum_before="$(cksum < "$d/settings.json")"
run "$d"
ok "malformed settings.json left byte-identical" . "$(cksum < "$d/settings.json")" "$cksum_before"
ok "malformed case makes no backup"             . "$(ls "$d" | grep -c 'settings.json.bak.' || true)" 0
ok "malformed case explains itself"             . "$(grep -c 'could not merge' "$TMP/out")" 1

# --- no settings.json at all: plain symlink, no merge path ----------------
d="$(newdir 5)"
run "$d"
ok "fresh dir symlinks settings.json"        . "$([ -L "$d/settings.json" ] && echo yes || echo no)" yes
ok "symlink points into this repo"           . "$(readlink "$d/settings.json")" "$REPO/.claude/settings.json"
ok "output-styles dir linked too"            . "$(readlink "$d/output-styles")" "$REPO/.claude/output-styles"

# --- only display keys are eligible, forever ------------------------------
# Pins the safety rule itself: if someone adds a permissions/env/plugin key to
# ADOPTABLE_KEYS, this fails rather than silently shipping wider permissions.
keys="$(grep -E '^ADOPTABLE_KEYS=' "$INSTALL" | cut -d'"' -f2)"
ok "ADOPTABLE_KEYS is display-only"          . "$keys" "statusLine outputStyle"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
