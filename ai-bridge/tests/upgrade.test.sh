#!/usr/bin/env bash
#
# Exercises ai-bridge/upgrade.sh, plus the one nudge line it added to install.sh.
#
# The properties that matter are the negative ones, in this order:
#   · a default run writes NOTHING (the whole instance is checksummed before and after,
#     symlink targets included) — it only reports;
#   · a HAND-DIVERGED seed file is reported as a conflict and left byte-identical, in
#     report mode AND under --apply. An instance's edits are the only copy of a decision
#     somebody made, and no merge this script can compute is worth losing them;
#   · a claimed port is verified on disk, so PORTED can never be printed for a write that
#     did not land (the bug migrate-bundle.sh once shipped);
#   · a non-instance directory is refused, non-zero, rather than stamped.
#
# The `log.md` and `CLAUDE.md` cases together are a regression test, not decoration: the seed
# file's CURRENT blob is in its git history too, and while it was allowed as a merge-base
# candidate it was often the blob closest to what an instance holds — making the merge a
# no-op and reporting a genuinely hand-diverged file as "nothing to port". `log.md` must stay
# silent (its seed never changed) while `CLAUDE.md` must conflict (its seed did).
#
# The fixture builds its own template in a temp git repo — including its own controlled
# `seed/` content, so these assertions do not move when the real seed files are edited —
# stamps an instance from seed v1, hand-diverges one file, then commits seed v2. That is
# exactly the shape of the problem: the instance's copy is frozen at v1, and only git
# history knows whether v1 is what it still has.
#
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL_SRC="$HERE/.."
[[ -f "$TPL_SRC/upgrade.sh" ]] || { echo "upgrade.test: not found at $TPL_SRC/upgrade.sh" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/upgrade-fixture.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
has()    { printf '%s\n' "$2" | grep -q -- "$1" && echo 0 || echo 1; }
hasnt()  { printf '%s\n' "$2" | grep -q -- "$1" && echo 1 || echo 0; }

# Everything in the instance that a mutation could touch: file contents AND symlink
# targets. .git is excluded — reading history legitimately touches git's own bookkeeping.
snapshot() {
  ( cd "$1" && find . -not -path './.git/*' \( -type f -o -type l \) | sort | while IFS= read -r f; do
      if [[ -L "$f" ]]; then printf 'L %s -> %s\n' "$f" "$(readlink "$f")"
      else printf 'F %s %s\n' "$f" "$(shasum "$f" | awk '{print $1}')"; fi
    done )
}

gc() { git -c user.email=a@b -c user.name=a commit -qm "$1"; }

# ---------------------------------------------------------------- the template, seed v1
TPL="$TMP/tpl"
mkdir -p "$TPL"
cp -R "$TPL_SRC/install.sh" "$TPL_SRC/upgrade.sh" "$TPL_SRC/seed" "$TPL_SRC/symlink" "$TPL/"

# Controlled seed content, so the assertions below describe this test's edits rather than
# whatever the real seed files happen to say today.
printf '# Index\nline A\nline B\nline C\nline D\n' > "$TPL/seed/index.md"
printf '# Todos\nt1\nt2\nt3\nt4\nt5\nt6\nt7\nt8\n'  > "$TPL/seed/todos.md"
printf '# Panel\nintro line\ntail line\n'           > "$TPL/seed/CLAUDE.md"
printf '# Log\n'                                    > "$TPL/seed/log.md"
( cd "$TPL" && git init -q -b main . && git add -A && gc "template, seed v1" )

# Every run below goes through the FIXTURE's copy of the script: `upgrade.sh` derives its
# template — and therefore the seed/ and the git history it judges drift against — from
# its OWN location. Running the repo's copy against the fixture instance silently compares
# it to the real seed files, which is how the first version of this harness lied.
UPGRADE="$TPL/upgrade.sh"

# ---------------------------------------------------------------- an instance, stamped
INST="$TMP/group/_ai-bridge-fixture"
mkdir -p "$INST"
bash "$TPL/install.sh" "$INST" > "$TMP/install1.out" 2>&1

# Documents for steps 2 and 3: one mechanical repair, one that needs a human.
mkdir -p "$INST/knowledge/findings"
printf -- '---\ntype: Finding\ntitle: F1\nstatus: open\ntimestamp: 2026-01-01T00:00:00Z\n---\nbody\n' \
  > "$INST/knowledge/findings/mechanical.md"
printf -- '---\ntype: Finding\ntitle: F2\nstatus: wibble\ntimestamp: 2026-01-01T00:00:00Z\n---\nbody\n' \
  > "$INST/knowledge/findings/needs-human.md"
( cd "$INST" && git init -q -b main . && git add -A && gc "instance init" )

# The instance's own edits, three shapes:
#   CLAUDE.md — the SAME line the seed is about to change  ⇒ must conflict
#   todos.md  — a line far from the seed's change          ⇒ must merge cleanly
#   log.md    — grown past a seed the template never edits ⇒ nothing to port, stay quiet
#   index.md  — untouched, i.e. the seed verbatim          ⇒ portable exactly
sed 's/^intro line$/intro line — HOUSE EDIT/' "$INST/CLAUDE.md" > "$TMP/c" && mv "$TMP/c" "$INST/CLAUDE.md"
printf 'INSTANCE TODO\n' >> "$INST/todos.md"
printf 'an entry the instance wrote\n' >> "$INST/log.md"
cp "$INST/CLAUDE.md" "$TMP/claude.pristine"

# ---------------------------------------------------------------- the template, seed v2
printf 'line E (new in seed v2)\n' >> "$TPL/seed/index.md"
sed 's/^# Todos$/# Todos\nTOP LINE FROM SEED V2/' "$TPL/seed/todos.md" > "$TMP/t" && mv "$TMP/t" "$TPL/seed/todos.md"
sed 's/^intro line$/intro line — TEMPLATE V2/'    "$TPL/seed/CLAUDE.md" > "$TMP/c" && mv "$TMP/c" "$TPL/seed/CLAUDE.md"
( cd "$TPL" && git add -A && gc "template, seed v2" )

echo "== refusing anything that is not an instance root =="
mkdir -p "$TMP/stranger"
set +e; bash "$UPGRADE" "$TMP/stranger" > "$TMP/refuse.out" 2>&1; RC=$?; set -e
assert "exits 2 on a directory that is not an instance" "$([[ $RC -eq 2 ]] && echo 0 || echo 1)"
assert "says what it expected to find"    "$(has 'instance.config.json' "$(cat "$TMP/refuse.out")")"
assert "points at install.sh for a NEW instance" "$(has 'install.sh' "$(cat "$TMP/refuse.out")")"
assert "it did not stamp the stranger"    "$(yes_if test ! -e "$TMP/stranger/SCHEMA.md")"
set +e; bash "$UPGRADE" "$TMP/no-such-dir" >/dev/null 2>&1; RC=$?; set -e
assert "exits 2 on a directory that does not exist" "$([[ $RC -eq 2 ]] && echo 0 || echo 1)"

echo "== a default run reports, and writes nothing =="
# Settle the symlink set first: the FIRST run legitimately links machinery (that is
# install.sh's documented job), so the no-write property is measured from there on.
bash "$UPGRADE" "$INST" > "$TMP/settle.out" 2>&1
BEFORE="$(snapshot "$INST")"
REPORT="$(bash "$UPGRADE" "$INST" 2>&1)"
AFTER="$(snapshot "$INST")"
assert "no file or symlink in the instance changed" "$([[ "$BEFORE" == "$AFTER" ]] && echo 0 || echo 1)"
assert "the mode is stated as report only"  "$(has 'REPORT ONLY' "$REPORT")"
assert "it says nothing was written"        "$(has 'report only — nothing was written' "$REPORT")"
assert "no PORTED label in report mode"     "$(hasnt 'PORTED' "$REPORT")"
assert "the mechanical repair is only WOULD FIX" "$(has 'WOULD FIX' "$REPORT")"
assert "the still-open Finding is untouched on disk" \
  "$(yes_if grep -q '^status: open' "$INST/knowledge/findings/mechanical.md")"

echo "== each seed file is classified on evidence, not on guesswork =="
assert "an untouched seed copy is PORTABLE"         "$(has 'PORTABLE  index.md' "$REPORT")"
assert "…and says it is the seed verbatim"          "$(has 'seed verbatim' "$REPORT")"
assert "a hand edit far from the seed's is PORTABLE" "$(has 'PORTABLE  todos.md' "$REPORT")"
assert "…and says it merges onto the instance's edits" "$(has 'merges cleanly onto' "$REPORT")"
assert "an edit to the same line is a CONFLICT"     "$(has 'CONFLICT  CLAUDE.md' "$REPORT")"
assert "the conflict prints the seed's diff"        "$(has 'TEMPLATE V2' "$REPORT")"
assert "…and hands it to the human"                 "$(has 'port it by hand' "$REPORT")"
assert "a seed the template never edited is silent"  "$(hasnt 'log.md' "$REPORT")"
assert "a file identical to the seed is silent"      "$(hasnt 'README.md' "$REPORT")"
assert "the per-instance workspace file is never treated as drift" \
  "$(hasnt 'code-workspace' "$REPORT")"
assert "the numbered next-steps list offers --apply" "$(has -- '--apply' "$REPORT")"
assert "…and names the human-decision document"      "$(has 'need a decision only you can make' "$REPORT")"

echo "== --apply writes the safe changes, and only those =="
APPLY_RC=0
APPLY="$(bash "$UPGRADE" "$INST" --apply 2>&1)" || APPLY_RC=$?
assert "--apply exits 0 when every write landed" "$([[ $APPLY_RC -eq 0 ]] && echo 0 || echo 1)"
assert "the mode is stated as apply"      "$(has 'mode:     APPLY' "$APPLY")"
assert "index.md is reported PORTED"      "$(has 'PORTED    index.md' "$APPLY")"
assert "index.md is now byte-identical to the current seed" \
  "$(yes_if cmp -s "$TPL/seed/index.md" "$INST/index.md")"
assert "todos.md is reported PORTED"      "$(has 'PORTED    todos.md' "$APPLY")"
assert "todos.md gained the seed's new line"  "$(yes_if grep -q '^TOP LINE FROM SEED V2$' "$INST/todos.md")"
assert "todos.md KEPT the instance's own line" "$(yes_if grep -q '^INSTANCE TODO$' "$INST/todos.md")"
assert "a merged file is backed up first" \
  "$(yes_if sh -c 'ls "$1".bak.* >/dev/null 2>&1' _ "$INST/todos.md")"
assert "a verbatim-seed file needs no backup" \
  "$(sh -c 'ls "$1".bak.* >/dev/null 2>&1' _ "$INST/index.md" && echo 1 || echo 0)"
assert "the schema repair landed"         "$(yes_if grep -q '^status: current' "$INST/knowledge/findings/mechanical.md")"

echo "== a hand-diverged file is never resolved by force =="
assert "CLAUDE.md is still reported CONFLICT under --apply" "$(has 'CONFLICT  CLAUDE.md' "$APPLY")"
assert "CLAUDE.md is byte-identical to before the run" \
  "$(yes_if cmp -s "$TMP/claude.pristine" "$INST/CLAUDE.md")"
assert "no conflict markers were written into it" \
  "$(grep -qE '^(<<<<<<< |>>>>>>> )' "$INST/CLAUDE.md" && echo 1 || echo 0)"
assert "the instance's own wording survived"  "$(yes_if grep -q 'HOUSE EDIT' "$INST/CLAUDE.md")"
assert "no PORTED label was printed for it" \
  "$(printf '%s\n' "$APPLY" | grep -B2 'CLAUDE.md' | grep -q 'PORTED' && echo 1 || echo 0)"
assert "it is still listed as work for the human" "$(has 'port the seed change into CLAUDE.md' "$APPLY")"
assert "no temp file was left behind" \
  "$(find "$INST" -name '.upgrade.*' | grep -q . && echo 1 || echo 0)"

echo "== idempotence =="
SECOND="$(bash "$UPGRADE" "$INST" 2>&1)"
assert "nothing is portable any more"   "$(has '0 portable' "$SECOND")"
assert "nothing was ported"             "$(has '0 ported' "$SECOND")"
assert "no machinery symlink is new"    "$(has 'summary: 0 new machinery symlink' "$SECOND")"
assert "the migration finds nothing to fix" "$(has '0 would be fixed' "$SECOND")"
BEFORE2="$(snapshot "$INST")"
bash "$UPGRADE" "$INST" >/dev/null 2>&1
assert "a repeated report run still writes nothing" \
  "$([[ "$BEFORE2" == "$(snapshot "$INST")" ]] && echo 0 || echo 1)"
THIRD="$(bash "$UPGRADE" "$INST" --apply 2>&1)"
assert "a repeated --apply writes nothing either" \
  "$([[ "$BEFORE2" == "$(snapshot "$INST")" ]] && echo 0 || echo 1)"
assert "…and reports 0 ported"          "$(has '0 ported' "$THIRD")"
assert "the conflict is still reported, not forgotten" "$(has 'CONFLICT  CLAUDE.md' "$THIRD")"

echo "== install.sh nudges toward upgrade.sh, but only when there is something to fix =="
NUDGE="$(bash "$TPL/install.sh" "$INST" 2>&1)"
assert "install.sh still exits 0 with a broken bundle" "$(yes_if bash "$TPL/install.sh" "$INST")"
assert "it points at upgrade.sh"       "$(has 'upgrade.sh' "$NUDGE")"
assert "it says why"                   "$(has 'schema errors' "$NUDGE")"
rm "$INST/knowledge/findings/needs-human.md"
CLEAN="$(bash "$TPL/install.sh" "$INST" 2>&1)"
assert "a clean bundle gets no nudge"  "$(hasnt 'upgrade.sh' "$CLEAN")"
# An instance older than the validator has no validator to run: still silent, still 0.
rm "$TPL/symlink/scripts/validate-bundle.sh"
OLD="$TMP/group/_ai-bridge-old"; mkdir -p "$OLD"
OLD_RC=0
OLD_OUT="$(bash "$TPL/install.sh" "$OLD" 2>&1)" || OLD_RC=$?
assert "no validator, no nudge"        "$(hasnt 'upgrade.sh' "$OLD_OUT")"
assert "no validator, still exits 0"   "$([[ $OLD_RC -eq 0 ]] && echo 0 || echo 1)"

echo "== a template with no git history reports rather than guesses =="
NOGIT="$TMP/tpl-nogit"
cp -R "$TPL" "$NOGIT" && rm -rf "$NOGIT/.git"
printf 'a further seed change\n' >> "$NOGIT/seed/index.md"
NOGIT_OUT="$(bash "$NOGIT/upgrade.sh" "$INST" --apply 2>&1)"
assert "a drifted file with no merge base is UNKNOWN" "$(has 'UNKNOWN   index.md' "$NOGIT_OUT")"
assert "…and is not ported"            "$(hasnt 'PORTED    index.md' "$NOGIT_OUT")"
assert "…and index.md was not written" \
  "$(yes_if cmp -s "$TPL/seed/index.md" "$INST/index.md")"

echo "== the four review findings, as refusals =="

# 1. A directory where a seeded FILE belongs. `-e` is true for it, so the old code fell
#    through to `git hash-object`, whose failure inside an assignment's command
#    substitution aborts the whole run under `set -e` — losing the report for every
#    remaining file. It must classify this one and carry on.
DIRCASE="$TMP/group/_ai-bridge-dircase"
cp -R "$INST" "$DIRCASE"
rm -f "$DIRCASE/index.md" && mkdir -p "$DIRCASE/index.md/somebody-made-this-a-folder"
DIR_RC=0
DIR_OUT="$(bash "$TPL/upgrade.sh" "$DIRCASE" --apply 2>&1)" || DIR_RC=$?
assert "a directory at a seeded path is UNKNOWN" "$(has 'UNKNOWN   index.md' "$DIR_OUT")"
assert "…and is not ported"                      "$(hasnt 'PORTED    index.md' "$DIR_OUT")"
assert "…and the directory is untouched"         "$(yes_if test -d "$DIRCASE/index.md/somebody-made-this-a-folder")"
# The whole point of the guard: one odd path must not cost the report for the others.
# These assert on work that happens strictly AFTER the loop reaches index.md: the per-stage
# `summary:` tally is printed once the loop has classified all nine seed files, and
# "what's left for you" is the last thing the script prints. Asserting on CLAUDE.md or on
# the "4/4" stage HEADER would pass either way, since both come first — that weaker pair
# was in the first draft of this block and hid the abort completely.
assert "…and every other file is still counted"  "$(has 'summary: 7 in sync' "$DIR_OUT")"
assert "…and the run reaches its final summary"  "$(has "what.s left for you" "$DIR_OUT")"
assert "…and the run still exits 0"              "$([[ $DIR_RC -eq 0 ]] && echo 0 || echo 1)"

# 2. install.sh failing is not a success. It is the PREREQUISITE for every later stage,
#    so a 0 exit there lets a caller treat "machinery never installed" as a clean run.
BADTPL="$TMP/tpl-badinstall"
cp -R "$TPL" "$BADTPL"
printf '#!/usr/bin/env bash\necho "  boom"\nexit 7\n' > "$BADTPL/install.sh"
chmod +x "$BADTPL/install.sh"
BAD_RC=0
BAD_OUT="$(bash "$BADTPL/upgrade.sh" "$INST" 2>&1)" || BAD_RC=$?
assert "a failing install.sh is reported"   "$(has 'install.sh exited 7' "$BAD_OUT")"
assert "…and it is listed as manual work"   "$(has 'install.sh failed' "$BAD_OUT")"
assert "…and the run exits NON-zero"        "$([[ $BAD_RC -ne 0 ]] && echo 0 || echo 1)"

# 3. Report-only must not overclaim. install.sh restores an ABSENT seed file by design
#    (its seeds-if-absent contract), so "nothing changes" was false. What report-only
#    really guarantees is that no instance CONTENT is rewritten.
REPORT_OUT="$(bash "$TPL/upgrade.sh" "$INST" 2>&1)"
assert "report mode does not claim nothing changes" \
  "$(hasnt 'nothing changes' "$REPORT_OUT")"
assert "report mode names what install.sh still writes" \
  "$(has 'restores any ABSENT seed file' "$REPORT_OUT")"
# And the claim it DOES make has to hold: a hand-diverged file stays byte-identical.
assert "report mode leaves diverged content alone" \
  "$(yes_if cmp -s "$TMP/claude.pristine" "$INST/CLAUDE.md")"

# 4. AUTONOMY.md is the deletable delegated-autonomy capability, but it lives under
#    symlink/ — so install.sh re-links it unconditionally and a per-instance `rm` is
#    silently undone. Fail-OPEN on the capability that lets agents merge without asking,
#    so the run has to say so out loud.
AUT="$TMP/group/_ai-bridge-autonomy"
cp -R "$INST" "$AUT"
rm -f "$AUT/AUTONOMY.md"
AUT_OUT="$(bash "$TPL/upgrade.sh" "$AUT" 2>&1)"
assert "a re-linked AUTONOMY.md is flagged"  "$(has 'AUTONOMY WAS RE-ENABLED' "$AUT_OUT")"
assert "…with the command to turn it off"    "$(has 'rm .*_ai-bridge-autonomy/AUTONOMY.md' "$AUT_OUT")"
# Non-vacuous: an instance that still has it must NOT get the warning.
STILL_OUT="$(bash "$TPL/upgrade.sh" "$INST" 2>&1)"
assert "…and not warned when it was present" "$(hasnt 'AUTONOMY WAS RE-ENABLED' "$STILL_OUT")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
