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
has()    { printf '%s\n' "$2" | grep -q -- "$1" && echo 0 || echo 1; }
hasnt()  { printf '%s\n' "$2" | grep -q -- "$1" && echo 1 || echo 0; }

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

# --- a ROOT-level machinery file, which the first version of the sweep could not see.
# machinery_paths() places SCHEMA.md, AUTONOMY.md and CONVENTIONS.md directly at the
# instance root and more under agents/. The sweep originally scanned only .claude/ and
# scripts/, so it missed exactly the most load-bearing files — and this harness mirrored
# that scope, which is why it passed. Raised in review on PR #62.
printf 'root machinery\n' > "$TPL/symlink/DOOMED-ROOT.md"
mkdir -p "$TPL/symlink/agents"
printf 'nested machinery\n' > "$TPL/symlink/agents/doomed-nested.md"
bash "$TPL/install.sh" "$INST" >"$TMP/out5" 2>&1
assert "a root machinery file links"        "$(yes_if test -L "$INST/DOOMED-ROOT.md")"
assert "a nested one links too"             "$(yes_if test -L "$INST/agents/doomed-nested.md")"
rm "$TPL/symlink/DOOMED-ROOT.md" "$TPL/symlink/agents/doomed-nested.md"
bash "$TPL/install.sh" "$INST" >"$TMP/out6" 2>&1
assert "a dangling ROOT link is swept"      "$(no_if test -L "$INST/DOOMED-ROOT.md")"
assert "…and reported"                      "$(yes_if grep -q 'retire DOOMED-ROOT.md' "$TMP/out6")"
assert "a dangling nested link is swept"    "$(no_if test -L "$INST/agents/doomed-nested.md")"
# A repos/ link points at reposRoot, not into symlink/, so a whole-instance scan must
# still leave it alone — this is what makes widening the scan safe.
mkdir -p "$TMP/elsewhere" && ln -sfn "$TMP/elsewhere" "$INST/repos-decoy"
bash "$TPL/install.sh" "$INST" >"$TMP/out7" 2>&1
assert "a link outside symlink/ survives"   "$(yes_if test -L "$INST/repos-decoy")"

# --- an instance path containing glob metacharacters (SC2295).
# `${dst#$TARGET/}` expands TARGET as a PATTERN, so a `[` in the path strips nothing,
# `rel` stays absolute, `ours` tests a doubled path and returns false — the dead link is
# silently kept. Quoting it fixes that, and only this fixture can tell the difference.
ODD="$TMP/od[d]group/_ai-bridge-odd"; mkdir -p "$ODD"
bash "$TPL/install.sh" "$ODD" >"$TMP/out8" 2>&1
printf 'doomed again\n' > "$TPL/symlink/DOOMED-TWICE.md"
bash "$TPL/install.sh" "$ODD" >"$TMP/out9" 2>&1
assert "glob-y path: the link is created"   "$(yes_if test -L "$ODD/DOOMED-TWICE.md")"
rm "$TPL/symlink/DOOMED-TWICE.md"
bash "$TPL/install.sh" "$ODD" >"$TMP/out10" 2>&1
assert "glob-y path: the link is swept"     "$(no_if test -L "$ODD/DOOMED-TWICE.md")"

# --- retired SEED content: reported with an rm, never removed.
# The asymmetry with the machinery sweep above is the whole point. A symlink into this
# template whose target is gone has one possible meaning; a seed file the human has owned
# since it was copied does not — `todos.md` is literally their notes. install.sh's safety
# property is that it only links and seeds-if-absent, so it may report and must not delete.
SEEDY="$TMP/group/_ai-bridge-seedy"; mkdir -p "$SEEDY"
bash "$TPL/install.sh" "$SEEDY" >/dev/null 2>&1
printf 'my private notes\n' > "$SEEDY/retired-thing.md"
printf 'retired-thing.md\tthe X feature was removed\n' > "$TPL/RETIRED"
OUT="$(bash "$TPL/install.sh" "$SEEDY" 2>&1)"
assert "retired seed content is reported"    "$(has 'stale retired-thing.md' "$OUT")"
assert "…with its reason"                    "$(has 'the X feature was removed' "$OUT")"
assert "…and the exact rm command"           "$(has 'rm .*_ai-bridge-seedy/retired-thing.md' "$OUT")"
assert "…and is NOT deleted"                 "$(yes_if grep -q 'my private notes' "$SEEDY/retired-thing.md")"
# A manifest entry for a file the instance does not have must stay quiet — most entries
# will be irrelevant to most instances, forever.
assert "an absent entry says nothing" \
  "$(hasnt 'stale ' "$(bash "$TPL/install.sh" "$INST" 2>&1)")"
# Comments, blanks and a reason-less line must all parse without noise.
printf '# a comment\n\nretired-thing.md\n' > "$TPL/RETIRED"
OUT2="$(bash "$TPL/install.sh" "$SEEDY" 2>&1)"
assert "a reason-less entry still reports"   "$(has 'stale retired-thing.md' "$OUT2")"
assert "…with a default reason"              "$(has 'no longer shipped by the template' "$OUT2")"
assert "…and comments are not reported"      "$(hasnt 'stale # a comment' "$OUT2")"
# Absence of the manifest is silence, not an error — the AUTONOMY.md convention.
rm -f "$TPL/RETIRED"
RC=0; OUT3="$(bash "$TPL/install.sh" "$SEEDY" 2>&1)" || RC=$?
assert "no manifest: exits 0"                "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "no manifest: reports nothing"        "$(hasnt 'stale ' "$OUT3")"
assert "no manifest: file still there"       "$(yes_if grep -q 'my private notes' "$SEEDY/retired-thing.md")"
# A dangling SYMLINK at a manifested path belongs to the sweep, not to this list.
: > "$TPL/RETIRED"; printf 'linky.md\tretired\n' >> "$TPL/RETIRED"
ln -sfn "$TMP/gone-forever" "$SEEDY/linky.md"
OUT4="$(bash "$TPL/install.sh" "$SEEDY" 2>&1)"
assert "a symlink is not reported as stale"  "$(hasnt 'stale linky.md' "$OUT4")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
