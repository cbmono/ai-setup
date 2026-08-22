#!/usr/bin/env bash
#
# task-owner.test.sh — the ownership gate that lets two humans share one bundle.
#
# WHY. Two humans each clone the bundle and each run their own `/pm-loop`. Without
# an owner, both loops see the same `ready` task and both dispatch it: two agents,
# two worktrees, two PRs for one slice of work. `owner` (task, else project, else
# this clone's `ownerGithubUser`) is what makes each loop dispatch only its own.
#
# The REFUSALS are the product, so most of this file asserts them:
#   · an unowned task still clears — this must be a no-op for the single-human
#     instances that exist today, where no document carries an `owner` at all;
#   · with a tracked `defaultOwner`, TWO clones of one bundle disagree in exactly the
#     right way: the same unowned task clears on one and refuses on the other. That
#     assertion is the point of `defaultOwner` — without it, the last step of the chain
#     resolves to "mine" on both clones and both loops dispatch the same task;
#   · a `defaultOwner` in the LOCAL file is ignored, because two clones that can
#     disagree about it reintroduce the bug it exists to fix;
#   · a login that is not a login refuses (exit 2) rather than being compared — and the
#     sharp case is fail-OPEN: the loose pattern accepted `alice-` and `alice--ops`, so
#     the SAME typo in `defaultOwner` and `ownerGithubUser` compared equal and CLEARED;
#   · a task owned by someone else does NOT clear;
#   · a task owned by someone else does not clear on a clone with no
#     `ownerGithubUser` either — an unconfigured clone cannot prove the name is its
#     own, so it fails closed rather than guessing;
#   · a value neither side can read (malformed username, unreadable frontmatter)
#     refuses instead of being compared;
#   · an `owner:` in the BODY is not frontmatter and is ignored;
#   · a repeated `owner:` key is judged from the FIRST value, never the later one.
#
# Fixture logins are PLACEHOLDERS VERIFIED UNCLAIMED on github.com
# (`gh api users/example-user-007` → 404). This repo is public, so a fixture must not
# name a live account: `alice`, `bob` and `jane-doe` all exist, and an example that
# names a stranger is an example someone copies. Verify any new one the same way.
#
# `assert()` uses exit-code semantics: 0 is a PASS, matching the other harnesses.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/symlink/scripts/task-owner.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/task-owner-fixture.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
has()    { printf '%s\n' "$2" | grep -q -- "$1" && echo 0 || echo 1; }

INST="$TMP/_ai-bridge-fixture"

# A minimal instance root: the script requires SCHEMA.md + instance.config.json,
# exactly as validate-bundle.sh does.
reset() { # [<tracked ownerGithubUser>] [<tracked defaultOwner>]
  rm -rf "$INST"; mkdir -p "$INST/projects/p1/tasks" "$INST/projects/p2/tasks"
  printf 'schema stub\n' > "$INST/SCHEMA.md"
  {
    printf '{\n  "org": "o"'
    [ "${1:-}" = "" ] || printf ',\n  "ownerGithubUser": "%s"' "$1"
    [ "${2:-}" = "" ] || printf ',\n  "defaultOwner": "%s"' "$2"
    printf '\n}\n'
  } > "$INST/instance.config.json"
  proj p1; proj p2
}
proj() { # <slug> [<owner>]
  { printf -- '---\ntype: Project\ntitle: %s\n' "$1"
    [ "${2:-}" = "" ] || printf 'owner: %s\n' "$2"
    printf 'status: active\ntimestamp: 2026-01-01T00:00:00Z\n---\n\n# Context\n'
  } > "$INST/projects/$1/project.md"
}
task() { # <slug> <id> [<owner>]
  { printf -- '---\ntype: Task\ntitle: %s\nkind: build\n' "$2"
    [ "${3:-}" = "" ] || printf 'owner: %s\n' "$3"
    printf 'status: ready\ntimestamp: 2026-01-01T00:00:00Z\n---\n\n# Context\n'
  } > "$INST/projects/$1/tasks/$2.md"
}
run() { ( cd "$INST" && bash "$SCRIPT" "$@" 2>&1 ); }
rc()  { ( cd "$INST" && bash "$SCRIPT" "$@" >/dev/null 2>&1 ); echo $?; }

echo "== backwards compatibility: no owner anywhere =="

# The three live single-human instances carry no `owner` and no `ownerGithubUser`.
# This case is the whole no-op guarantee.
reset; task p1 t1
assert "no owner, no ownerGithubUser -> clears"   "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
assert "…and says the task names no owner"       "$(has 'names no owner' "$(run projects/p1/tasks/t1.md)")"
reset example-user-007; task p1 t1
assert "no owner, self configured -> clears"     "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"

echo
echo "== the project is the normal place to set it =="

reset example-user-007; proj p1 example-user-007; task p1 t1
assert "project owner = me -> clears"            "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
assert "…and names the project as the source"    "$(has 'projects/p1/project.md' "$(run projects/p1/tasks/t1.md)")"

reset example-user-007; proj p1 example-user-008; task p1 t1
assert "project owner = someone else -> refuses" "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"
assert "…and names the other owner"              "$(has "owned by 'example-user-008'" "$(run projects/p1/tasks/t1.md)")"
assert "…and does not tell you to dispatch it"   "$(has 'do not dispatch it here' "$(run projects/p1/tasks/t1.md)")"

# One project each: the shared-board case this exists for.
reset example-user-007; proj p1 example-user-007; proj p2 example-user-008; task p1 mine; task p2 theirs
assert "mine clears on a two-owner board"        "$([[ "$(rc projects/p1/tasks/mine.md)" == 0 ]] && echo 0 || echo 1)"
assert "theirs refuses on the same board"        "$([[ "$(rc projects/p2/tasks/theirs.md)" == 1 ]] && echo 0 || echo 1)"

echo
echo "== a task overrides its project, in both directions =="

reset example-user-007; proj p1 example-user-008; task p1 t1 example-user-007
assert "task owner = me beats project = them"    "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
assert "…and names the task as the source"       "$(has 'tasks/t1.md' "$(run projects/p1/tasks/t1.md)")"

reset example-user-007; proj p1 example-user-007; task p1 t1 example-user-008
assert "task owner = them beats project = me"    "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"

echo
echo "== fail closed when the clone is unconfigured =="

# An owned task on a clone with no ownerGithubUser: refusing costs a tick, clearing
# costs a double dispatch. The tie goes to refusing, and it says how to fix it.
reset; proj p1 example-user-008; task p1 t1
assert "owned task, no ownerGithubUser -> refuses" "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"
assert "…and names the key to set"                 "$(has 'ownerGithubUser' "$(run projects/p1/tasks/t1.md)")"
assert "…and points at the LOCAL file"             "$(has 'instance.config.local.json' "$(run projects/p1/tasks/t1.md)")"

echo
echo "== the local override wins, and its absence changes nothing =="

reset example-user-008; proj p1 example-user-007; task p1 t1
assert "tracked self=example-user-008, task=example-user-007 -> refuses"  "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"
printf '{ "ownerGithubUser": "example-user-007" }\n' > "$INST/instance.config.local.json"
assert "local override flips it to clears"        "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
assert "…and --self reports the local value"      "$(has 'self: example-user-007 (from instance.config.local.json)' "$(run --self)")"
rm -f "$INST/instance.config.local.json"
assert "removing it restores the tracked answer"  "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"
assert "…and --self reports the tracked value"    "$(has 'self: example-user-008 (from instance.config.json)' "$(run --self)")"
# A local file that does not mention the key is not an override.
printf '{ "authorEmail": "someone@example.com" }\n' > "$INST/instance.config.local.json"
assert "a local file without the key defers"      "$(has 'self: example-user-008 (from instance.config.json)' "$(run --self)")"
reset; assert "no key anywhere -> --self says none" "$(has 'self: <none>' "$(run --self)")"

echo
echo "== the tracked defaultOwner: the third step of the resolution =="

reset example-user-007 example-user-007; task p1 t1
assert "defaultOwner = me -> clears"             "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
assert "…and names defaultOwner as the source"  "$(has 'defaultOwner' "$(run projects/p1/tasks/t1.md)")"

reset example-user-007 example-user-008; task p1 t1
assert "defaultOwner = someone else -> refuses"  "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"

# Ordered: a document that names an owner outranks the config default.
reset example-user-007 example-user-008; proj p1 example-user-007; task p1 t1
assert "a project owner beats defaultOwner"      "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
reset example-user-007 example-user-008; task p1 t1 example-user-007
assert "a task owner beats defaultOwner"         "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
reset example-user-007 example-user-007; proj p1 example-user-008; task p1 t1
assert "…in the refusing direction too"          "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"

# Absence is the old behaviour exactly — what keeps this a no-op for the single-human
# instances, which have no such key.
reset example-user-007; task p1 t1
assert "no defaultOwner -> unowned, clears"      "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
reset example-user-007 'not a username!'; task p1 t1
assert "a malformed defaultOwner -> exit 2"      "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"

# NOT overridable per machine. Two clones that can disagree about who owns unowned work
# are two clones that both dispatch it — the bug this key exists to fix.
reset example-user-007 example-user-008; task p1 t1
printf '{ "ownerGithubUser": "example-user-007", "defaultOwner": "example-user-007" }\n' > "$INST/instance.config.local.json"
assert "a LOCAL defaultOwner is ignored"         "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"

echo
echo "== two clones of one bundle: exactly one dispatches an unowned task =="

# The whole point. ONE tracked config (so both clones agree on defaultOwner), two
# different local ownerGithubUser values, one task nothing owns.
reset '' example-user-007; task p1 shared
printf '{ "ownerGithubUser": "example-user-007" }\n' > "$INST/instance.config.local.json"
A_RC="$(rc projects/p1/tasks/shared.md)"
printf '{ "ownerGithubUser": "example-user-008" }\n' > "$INST/instance.config.local.json"
B_RC="$(rc projects/p1/tasks/shared.md)"
assert "clone A (the defaultOwner) dispatches it" "$([[ "$A_RC" == 0 ]] && echo 0 || echo 1)"
assert "clone B does NOT"                         "$([[ "$B_RC" == 1 ]] && echo 0 || echo 1)"
assert "…so exactly one clone clears it"          "$([[ "$A_RC$B_RC" == "01" ]] && echo 0 || echo 1)"

# And the hazard the key closes, as a test rather than as prose: with no defaultOwner,
# BOTH clones clear the same task. Correct on a single-human instance; a double dispatch
# on two clones.
reset ''; task p1 shared
printf '{ "ownerGithubUser": "example-user-007" }\n' > "$INST/instance.config.local.json"
A2="$(rc projects/p1/tasks/shared.md)"
printf '{ "ownerGithubUser": "example-user-008" }\n' > "$INST/instance.config.local.json"
B2="$(rc projects/p1/tasks/shared.md)"
assert "without defaultOwner BOTH clones clear it" "$([[ "$A2$B2" == "00" ]] && echo 0 || echo 1)"

echo
echo "== case-insensitive, like GitHub =="

reset Example-User-007; proj p1 EXAMPLE-user-007; task p1 t1
assert "owner and self differ only in case"      "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"

echo
echo "== an empty value reads as absent, not as an owner =="

reset example-user-007; proj p1 example-user-008
printf -- '---\ntype: Task\nowner:\nstatus: ready\n---\n' > "$INST/projects/p1/tasks/t1.md"
assert "empty task owner falls through to project" "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"
printf -- '---\ntype: Project\nowner:\nstatus: active\n---\n' > "$INST/projects/p1/project.md"
assert "empty project owner falls through to self" "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"

echo
echo "== only the FIRST owner counts (the push-state repeated-key bug) =="

reset example-user-007
printf -- '---\ntype: Task\nowner: example-user-007\nowner: example-user-008\nstatus: ready\n---\n' > "$INST/projects/p1/tasks/t1.md"
assert "first=me, second=them -> clears"         "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
printf -- '---\ntype: Task\nowner: example-user-008\nowner: example-user-007\nstatus: ready\n---\n' > "$INST/projects/p1/tasks/t1.md"
assert "first=them, second=me -> refuses"        "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"

echo
echo "== the BODY is not frontmatter =="

reset example-user-007
printf -- '---\ntype: Task\nstatus: ready\n---\n\n# Context\nowner: example-user-008\n' > "$INST/projects/p1/tasks/t1.md"
assert "an owner: line in the body is ignored"   "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"

echo
echo "== unreadable or unusable input refuses (exit 2), never clears =="

reset example-user-007
printf 'no frontmatter here\nowner: example-user-007\n' > "$INST/projects/p1/tasks/t1.md"
assert "no frontmatter -> exit 2"                "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"
printf -- '---\ntype: Task\nowner: example-user-007\nstatus: ready\n' > "$INST/projects/p1/tasks/t1.md"
assert "frontmatter never closed -> exit 2"      "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"

reset example-user-007; task p1 t1 'not a username!'
assert "malformed owner value -> exit 2"         "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"
assert "…and says it is not a username"          "$(has 'not a GitHub username' "$(run projects/p1/tasks/t1.md)")"

reset 'not a username!'; task p1 t1 example-user-007
assert "malformed ownerGithubUser -> exit 2"     "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"

# The exact GitHub rule, not an approximation: a hyphen may sit only BETWEEN
# alphanumerics. The loose form accepted `example-user-007-` and `example-user-007--ops`, and that was
# fail-OPEN — the same typo in `defaultOwner` and in `ownerGithubUser` compared equal
# and CLEARED dispatch instead of refusing. (Raised by review on PR #67.)
for bad in 'example-user-007-' 'example-user-007--ops' '-example-user-007' 'exam.ple' 'example-user-007_ops'; do
  reset example-user-007; task p1 t1 "$bad"
  assert "an owner of '$bad' -> exit 2"          "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"
  # The fail-open shape specifically: the SAME bad value on both sides must not clear
  # just because the two strings happen to match.
  reset "$bad"; task p1 t1 "$bad"
  assert "…and does not clear when self matches" "$([[ "$(rc projects/p1/tasks/t1.md)" != 0 ]] && echo 0 || echo 1)"
  reset example-user-007 "$bad"
  assert "…nor as a defaultOwner"                "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"
done
# Valid shapes must still be accepted: hyphens between alphanumerics, and 39 chars.
reset example-user-007-ops; proj p1 example-user-007-ops; task p1 t1
assert "a hyphenated login is valid"             "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
L39="$(printf 'a%.0s' $(seq 1 39))"
reset "$L39"; proj p1 "$L39"; task p1 t1
assert "a 39-character login is valid"           "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
reset example-user-007 "$(printf 'a%.0s' $(seq 1 40))"
assert "a 40-character defaultOwner -> exit 2"   "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"

reset example-user-007; proj p1 example-user-008; task p1 t1
printf 'no frontmatter\n' > "$INST/projects/p1/project.md"
assert "unreadable project.md -> exit 2"         "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"

reset example-user-007
assert "a missing task path -> exit 2"           "$([[ "$(rc projects/p1/tasks/nope.md)" == 2 ]] && echo 0 || echo 1)"
assert "no arguments -> exit 2"                  "$([[ "$(rc)" == 2 ]] && echo 0 || echo 1)"
assert "an unknown flag -> exit 2"               "$([[ "$(rc --wat projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"
assert "two paths -> exit 2"                     "$([[ "$(rc a.md b.md)" == 2 ]] && echo 0 || echo 1)"
OUTSIDE="$( ( cd "$TMP" && bash "$SCRIPT" --self >/dev/null 2>&1 ); echo $? )"
assert "outside an instance root -> exit 2"      "$([[ "$OUTSIDE" == 2 ]] && echo 0 || echo 1)"

echo
echo "== absolute paths and awkward paths =="

reset example-user-007; proj p1 example-user-008; task p1 t1
ABS="$( ( cd "$INST" && bash "$SCRIPT" "$INST/projects/p1/tasks/t1.md" >/dev/null 2>&1 ); echo $? )"
assert "an absolute task path resolves the project" "$([[ "$ABS" == 1 ]] && echo 0 || echo 1)"

# A path outside projects/ has no project to ask, which is not an error — it is
# simply unowned, i.e. this clone's, which is today's behaviour for everything.
reset example-user-007
printf -- '---\ntype: Task\nstatus: ready\n---\n' > "$INST/loose-task.md"
assert "a task outside projects/ is unowned"     "$([[ "$(rc loose-task.md)" == 0 ]] && echo 0 || echo 1)"

# An instance path containing glob metacharacters: "$PWD" must be QUOTED in the
# prefix strip, or the absolute path is not reduced and the project lookup silently
# never happens — the SC2295 trap install.sh already had.
ODD="$TMP/od[d]/_ai-bridge-odd"; mkdir -p "$ODD/projects/p1/tasks"
printf 'stub\n' > "$ODD/SCHEMA.md"
printf '{ "ownerGithubUser": "example-user-007" }\n' > "$ODD/instance.config.json"
printf -- '---\ntype: Project\nowner: example-user-008\nstatus: active\n---\n' > "$ODD/projects/p1/project.md"
printf -- '---\ntype: Task\nstatus: ready\n---\n' > "$ODD/projects/p1/tasks/t1.md"
ODDRC="$( ( cd "$ODD" && bash "$SCRIPT" "$ODD/projects/p1/tasks/t1.md" >/dev/null 2>&1 ); echo $? )"
assert "glob-y instance path still finds the project" "$([[ "$ODDRC" == 1 ]] && echo 0 || echo 1)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
