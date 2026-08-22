#!/usr/bin/env bash
# Pins the one property that makes .claude/rules/ safe to ship in this repo:
# the user-wide installer must NEVER link it into the real config dir.
#
# Why it matters: rules are instructions about THIS repo's own files, selected by
# `paths:` globs that are matched relative to the project directory. As
# ~/.claude/rules/ they become USER-level rules loaded in every project on the
# machine, where globs like `install.sh` or `.coderabbit.yaml` would match a
# consumer's unrelated files and hand their session conventions for a repo they
# do not have. It is also the exact surprise the per-entry-symlink design exists
# to avoid — an install that silently changes how Claude behaves elsewhere.
#
# The exclusion is one word in EXCLUDE, which is one careless edit from being
# dropped, and the failure is invisible on the machine that makes it (the rules
# are correct *here*). Hence a test.
#
# Runs against a throwaway CLAUDE_CONFIG_DIR, so it never touches the real ~/.claude.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$REPO/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

newdir() { local d="$TMP/c$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }
run()    { CLAUDE_CONFIG_DIR="$1" bash "$INSTALL" >"$TMP/out" 2>&1; printf '%s' "$?"; }

ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then
    printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else
    printf '  FAIL  %-56s expected %s, got %s\n' "$1" "$3" "$2"
    printf '        installer said: %s\n' "$(tr '\n' '|' < "$TMP/out" | tail -c 220)"
    fail=$((fail+1))
  fi
}

echo "install.sh: .claude/rules/ is never linked user-wide"

# --- the exclusion holds ----------------------------------------------------
d="$(newdir 1)"
rc="$(run "$d")"
ok "installer exits 0"                        "$rc" 0
ok "rules/ NOT created in the config dir"     "$([ -e "$d/rules" ] && echo present || echo absent)" absent
ok "rules/ not mentioned as linked"           "$(grep -c ' rules$' "$TMP/out")" 0

# --- and it is narrow: the real defaults still land -------------------------
for e in agents commands hooks output-styles scripts skills; do
  ok "$e still linked"                        "$([ -L "$d/$e" ] && echo link || echo missing)" link
done
ok "claude-defaults.md still linked"          "$([ -L "$d/claude-defaults.md" ] && echo link || echo missing)" link

# --- idempotent: a re-run must not start linking it -------------------------
rc="$(run "$d")"
ok "re-run exits 0"                           "$rc" 0
ok "re-run still leaves rules/ absent"        "$([ -e "$d/rules" ] && echo present || echo absent)" absent

# --- a stale ~/.claude/rules the user owns is left strictly alone -----------
# The installer must neither adopt nor delete a real rules dir someone created
# themselves: it is not ours to manage, and --uninstall only removes OUR links.
d="$(newdir 2)"
mkdir -p "$d/rules"
printf 'mine\n' > "$d/rules/personal.md"
run "$d" >/dev/null
ok "a user's own ~/.claude/rules is untouched" "$(cat "$d/rules/personal.md" 2>/dev/null)" mine
ok "it was not replaced by a symlink"          "$([ -L "$d/rules" ] && echo link || echo real)" real
CLAUDE_CONFIG_DIR="$d" bash "$INSTALL" --uninstall >"$TMP/out" 2>&1
ok "--uninstall leaves it in place"            "$(cat "$d/rules/personal.md" 2>/dev/null)" mine

# --- absence is safe: no rules dir at all must not error --------------------
# Matches the AUTONOMY.md pattern — deleting the capability disables it silently
# rather than breaking the installer for everyone.
d="$(newdir 3)"
STASH="$TMP/stash"
if [ -d "$REPO/.claude/rules" ]; then
  mv "$REPO/.claude/rules" "$STASH"
  rc="$(run "$d")"
  mv "$STASH" "$REPO/.claude/rules"
  ok "installer exits 0 with no rules/ in repo" "$rc" 0
else
  ok "installer exits 0 with no rules/ in repo" skipped skipped
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
