#!/usr/bin/env bash
#
# retire-machinery.test.sh — install.sh removes a machinery symlink whose target the
# template no longer ships, and nothing else.
#
# WHY. Removing a capability from symlink/ (the /todo feature was the first) leaves every
# already-stamped instance with a symlink into a path that no longer exists. That is worse
# than an absent file: a dangling command still registers, and a SessionStart hook whose
# script has vanished exits 127 on every launch. Nothing else in the template noticed —
# the link loop only iterates files that DO exist.
#
# The negative properties are the point, and they are what this file mostly asserts:
#   · a real file is never removed, however dead it looks;
#   · a symlink pointing somewhere OTHER than this template is never removed, even when
#     it dangles — it is not ours to judge;
#   · a link that still resolves is left alone;
#   · seed content is never removed. A `todos.md` surviving a retired feature is the
#     human's own writing.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

TPLSRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/retire-fixture.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }

# A copy of the template, so removing a machinery file here cannot touch the real one.
TPL="$TMP/tpl"; mkdir -p "$TPL"
( cd "$TPLSRC" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$TPL/$(dirname "$f")"; cp "$TPLSRC/$f" "$TPL/$f" 2>/dev/null || true
done
chmod +x "$TPL/install.sh" "$TPL"/symlink/scripts/*.sh 2>/dev/null || true

INST="$TMP/group/_ai-bridge-group"; mkdir -p "$INST"
bash "$TPL/install.sh" "$INST" >"$TMP/out1" 2>&1
assert "a fresh instance stamps"            "$(yes_if test -f "$INST/instance.config.json")"

# Add a machinery file, stamp it in, then retire it from the template.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TPL/symlink/scripts/doomed.sh"
bash "$TPL/install.sh" "$INST" >"$TMP/out2" 2>&1
assert "the new machinery file is linked"   "$(yes_if test -L "$INST/scripts/doomed.sh")"
assert "…and it resolves"                   "$(yes_if test -e "$INST/scripts/doomed.sh")"

# Decoys that must survive the sweep.
printf 'my own notes\n' > "$INST/scripts/mine.sh"                    # a real file
ln -s "$TMP/nowhere-at-all"  "$INST/scripts/foreign-dangling"        # dangles, NOT ours
ln -s "$TPL/symlink/scripts/commit-as.sh" "$INST/scripts/still-good" # ours, resolves

rm "$TPL/symlink/scripts/doomed.sh"
bash "$TPL/install.sh" "$INST" >"$TMP/out3" 2>&1
RC=$?

assert "install.sh still exits 0"           "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "the dangling link is removed"       "$(no_if test -L "$INST/scripts/doomed.sh")"
assert "…and it is reported"                "$(yes_if grep -q 'retire scripts/doomed.sh' "$TMP/out3")"
assert "a real file is NOT removed"         "$(yes_if grep -q 'my own notes' "$INST/scripts/mine.sh")"
assert "a foreign dangling link survives"   "$(yes_if test -L "$INST/scripts/foreign-dangling")"
assert "a resolving link of ours survives"  "$(yes_if test -e "$INST/scripts/still-good")"
# Seed content outlives a retired feature: it is the human's writing, not machinery.
printf 'a note I wrote\n' > "$INST/leftover-seed.md"
bash "$TPL/install.sh" "$INST" >"$TMP/out4" 2>&1
assert "seed-shaped content is untouched"   "$(yes_if grep -q 'a note I wrote' "$INST/leftover-seed.md")"
# Idempotent: a second sweep with nothing to do says nothing and still exits 0.
assert "a repeat run retires nothing"       "$(no_if grep -q 'retire ' "$TMP/out4")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
