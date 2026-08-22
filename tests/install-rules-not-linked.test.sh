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
# Capture the status: without this, the three checks below inspect only the
# pre-existing directory and the uninstall path, so they all pass even when the
# install failed outright and never got as far as looking at rules/.
rc="$(run "$d")"
ok "installer exits 0 with a user-owned rules/"  "$rc" 0
ok "a user's own ~/.claude/rules is untouched" "$(cat "$d/rules/personal.md" 2>/dev/null)" mine
ok "it was not replaced by a symlink"          "$([ -L "$d/rules" ] && echo link || echo real)" real
CLAUDE_CONFIG_DIR="$d" bash "$INSTALL" --uninstall >"$TMP/out" 2>&1
ok "--uninstall leaves it in place"            "$(cat "$d/rules/personal.md" 2>/dev/null)" mine

# --- absence is safe: no rules dir at all must not error --------------------
# Matches the AUTONOMY.md pattern — deleting the capability disables it silently
# rather than breaking the installer for everyone.
# This case needs a repo WITHOUT .claude/rules. The first version got one by
# `mv`-ing the real directory aside and moving it back — which mutates the
# checkout every other agent and test in this repo is reading, and an interrupt
# between the two moves leaves the repository missing a tracked directory. Copy
# instead: a throwaway clone of the tracked tree, deleted from the copy only.
d="$(newdir 3)"
COPY="$TMP/repo-copy"
rm -rf "$COPY"; mkdir -p "$COPY"
# Only what install.sh reads: itself, plus the tracked .claude/ tree it discovers
# via `git ls-files`. Needs to be a git repo for that discovery to work.
( cd "$REPO" && git ls-files .claude install.sh ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$COPY/$(dirname "$f")"
  cp "$REPO/$f" "$COPY/$f" 2>/dev/null || true
done
( cd "$COPY" && git init -q . && git add -A >/dev/null 2>&1 \
  && git -c user.name=t -c user.email=t@t commit -qm fixture >/dev/null 2>&1 )
rm -rf "$COPY/.claude/rules"
( cd "$COPY" && git add -A >/dev/null 2>&1 \
  && git -c user.name=t -c user.email=t@t commit -qm "drop rules" >/dev/null 2>&1 )
CLAUDE_CONFIG_DIR="$d" bash "$COPY/install.sh" >"$TMP/out" 2>&1
ok "installer exits 0 with no rules/ in repo" "$?" 0
ok "…and links nothing named rules"           "$([ -e "$d/rules" ] && echo present || echo absent)" absent
# Prove the real checkout was not disturbed, which is the property the rewrite buys.
ok "the real repo still has .claude/rules"    "$([ -d "$REPO/.claude/rules" ] && echo yes || echo no)" yes

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
