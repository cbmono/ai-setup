#!/usr/bin/env bash
#
# derived-indexes.test.sh — the `index.md` files are derived, so they are gitignored;
# `knowledge/index.md` is NOT, and that exclusion is the interesting half.
#
# WHY. Every `/pm-loop` tick rewrites the root `index.md` and each project's, from
# the documents they summarise. On a bundle shared by two humans, each running their
# own loop, that is a merge conflict on every push over a file whose every line is
# re-derivable — the same argument that made `AWAITING.md` and `SNAPSHOT.json`
# derived-and-ignored. `knowledge/index.md` is deliberately excluded: it is the KB's
# curated lookup surface, it changes only when the KB changes rather than every tick,
# and every agent is told to scan it, so a fresh clone needs it to exist.
#
# The properties asserted, in order of how easy each is to break:
#   · `knowledge/index.md` is NOT ignored — a bare `index.md` pattern would have
#     swallowed it, and the failure would be silent until an agent found nothing;
#   · a per-project `index.md` IS ignored, at the one nesting level it occurs;
#   · install.sh adds both lines — to a fresh stamp AND to an instance whose
#     .gitignore predates them — and they are deliberately NOT in seed/.gitignore,
#     which is itself an active .gitignore over the template's own seed/ directory;
#   · a .gitignore line is INERT for an already-tracked file, so the installer
#     reports the exact `git rm --cached` rather than silently doing nothing;
#   · and it stays quiet when there is nothing tracked to report.
#
# `assert()` uses exit-code semantics: 0 is a PASS, matching the other harnesses.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/derived-indexes.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
has()    { printf '%s\n' "$2" | grep -q -- "$1" && echo 0 || echo 1; }
hasnt()  { printf '%s\n' "$2" | grep -q -- "$1" && echo 1 || echo 0; }

echo "== the lines are NOT in seed/.gitignore, and that is deliberate =="
# seed/.gitignore is an ACTIVE .gitignore inside the template's own seed/ directory,
# so a `/index.md` line there matches `ai-bridge/seed/index.md` and stops the template
# from tracking its own seed file. It broke the upgrade.sh fixture, which re-inits a
# repo over a copy of seed/. So the lines live in install.sh, and this asserts the trap
# stays closed — against git's own answer, not the pattern text.
assert "seed/.gitignore has no /index.md line" \
  "$(no_if grep -qxF '/index.md' "$TPL/seed/.gitignore")"
assert "…and the seed's own index.md is trackable" \
  "$(no_if git -C "$TPL/.." check-ignore --no-index -q ai-bridge/seed/index.md)"
assert "…and it says why, so nobody 'fixes' it" \
  "$(yes_if grep -q 'ACTIVE .gitignore' "$TPL/seed/.gitignore")"
# A bare `index.md` line would match at every depth, knowledge/ included.
assert "no bare 'index.md' pattern in the seed" \
  "$(no_if grep -qx 'index.md' "$TPL/seed/.gitignore")"

echo
echo "== a live instance: git's own answer, not the pattern text =="
INST="$TMP/g/_ai-bridge-g"; mkdir -p "$INST"
bash "$TPL/install.sh" "$INST" >/dev/null 2>&1
assert "a FRESH stamp gets the root line"   "$(yes_if grep -qxF '/index.md' "$INST/.gitignore")"
assert "…and the per-project line"          "$(yes_if grep -qxF '/projects/*/index.md' "$INST/.gitignore")"
( cd "$INST" && git init -q . && git config user.email t@e.st && git config user.name t )
mkdir -p "$INST/projects/p1" "$INST/knowledge"
printf 'root\n'  > "$INST/index.md"
printf 'proj\n'  > "$INST/projects/p1/index.md"
printf 'kb\n'    > "$INST/knowledge/index.md"
ignored() { ( cd "$INST" && git check-ignore -q "$1" ); }
assert "the root index.md is ignored"       "$(yes_if ignored index.md)"
assert "a project's index.md is ignored"    "$(yes_if ignored projects/p1/index.md)"
assert "knowledge/index.md is NOT ignored"  "$(no_if ignored knowledge/index.md)"
assert "a project's log.md is NOT ignored"  "$(no_if ignored projects/p1/log.md)"
# `git add -A` must not sweep the derived ones in — that is the property the loop
# and /new-project both rely on when they name a directory as a pathspec.
( cd "$INST" && git add -A >/dev/null 2>&1 )
STAGED="$( cd "$INST" && git diff --cached --name-only )"
assert "git add -A skips the root index"    "$(hasnt '^index\.md$' "$STAGED")"
assert "…and the project index"             "$(hasnt 'projects/p1/index\.md' "$STAGED")"
assert "…but stages the KB index"           "$(has 'knowledge/index\.md' "$STAGED")"

echo
echo "== an instance whose .gitignore predates the lines =="
OLD="$TMP/g/_ai-bridge-old"; mkdir -p "$OLD"
bash "$TPL/install.sh" "$OLD" >/dev/null 2>&1
grep -vE '^/(index\.md|projects/\*/index\.md)$' "$OLD/.gitignore" > "$OLD/.gi" && mv "$OLD/.gi" "$OLD/.gitignore"
assert "the lines really were removed"      "$(no_if grep -qxF '/index.md' "$OLD/.gitignore")"
bash "$TPL/install.sh" "$OLD" >/dev/null 2>&1
assert "install.sh re-adds the root line"   "$(yes_if grep -qxF '/index.md' "$OLD/.gitignore")"
assert "…and the per-project line"          "$(yes_if grep -qxF '/projects/*/index.md' "$OLD/.gitignore")"
bash "$TPL/install.sh" "$OLD" >/dev/null 2>&1
COUNT="$(grep -cxF '/index.md' "$OLD/.gitignore")"
assert "a re-run does not duplicate them"   "$([[ "$COUNT" == 1 ]] && echo 0 || echo 1)"

echo
echo "== an already-TRACKED index.md: reported, never touched =="
# A .gitignore line does nothing to a file git already tracks. Silence here would be
# the whole change quietly not happening, so the installer prints the exact command.
TRK="$TMP/g/_ai-bridge-tracked"; mkdir -p "$TRK/projects/p1"
bash "$TPL/install.sh" "$TRK" >/dev/null 2>&1
printf 'root\n' > "$TRK/index.md"; printf 'proj\n' > "$TRK/projects/p1/index.md"
( cd "$TRK" && git init -q . && git config user.email t@e.st && git config user.name t \
  && git add -f index.md projects/p1/index.md >/dev/null && git commit -qm seed )
OUT="$(bash "$TPL/install.sh" "$TRK" 2>&1)"
assert "the tracked root index is reported"  "$(has 'tracked index.md' "$OUT")"
assert "…and the tracked project index"      "$(has 'tracked projects/p1/index.md' "$OUT")"
assert "…with the exact rm --cached command" "$(has 'git rm --cached' "$OUT")"
assert "…and the file is NOT removed"        "$(yes_if grep -q 'root' "$TRK/index.md")"
assert "…and it is still tracked afterwards" "$(yes_if bash -c "cd '$TRK' && git ls-files --error-unmatch index.md")"
# Once untracked, the report must go quiet — it is a to-do, not a permanent banner.
( cd "$TRK" && git rm --cached -q -- index.md 'projects/*/index.md' && git commit -qm untrack )
OUT2="$(bash "$TPL/install.sh" "$TRK" 2>&1)"
assert "after untracking, nothing is reported" "$(hasnt 'tracked index.md' "$OUT2")"
assert "…and the files survive on disk"        "$(yes_if grep -q 'root' "$TRK/index.md")"
# An instance that is not a git repo at all must not error or report.
NOGIT="$TMP/g/_ai-bridge-nogit"; mkdir -p "$NOGIT"
RC=0; OUT3="$(bash "$TPL/install.sh" "$NOGIT" 2>&1)" || RC=$?
assert "a non-repo instance exits 0"           "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "…and reports no tracked indexes"       "$(hasnt 'tracked index.md' "$OUT3")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
