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
#   · a task owned by someone else does NOT clear;
#   · a task owned by someone else does not clear on a clone with no
#     `ownerGithubUser` either — an unconfigured clone cannot prove the name is its
#     own, so it fails closed rather than guessing;
#   · a value neither side can read (malformed username, unreadable frontmatter)
#     refuses instead of being compared;
#   · an `owner:` in the BODY is not frontmatter and is ignored;
#   · a repeated `owner:` key is judged from the FIRST value, never the later one.
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
reset() { # [<tracked ownerGithubUser>]
  rm -rf "$INST"; mkdir -p "$INST/projects/p1/tasks" "$INST/projects/p2/tasks"
  printf 'schema stub\n' > "$INST/SCHEMA.md"
  if [ "$#" -ge 1 ] && [ -n "$1" ]; then
    printf '{\n  "org": "o",\n  "ownerGithubUser": "%s"\n}\n' "$1" > "$INST/instance.config.json"
  else
    printf '{\n  "org": "o"\n}\n' > "$INST/instance.config.json"
  fi
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
reset cbmono; task p1 t1
assert "no owner, self configured -> clears"     "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"

echo
echo "== the project is the normal place to set it =="

reset cbmono; proj p1 cbmono; task p1 t1
assert "project owner = me -> clears"            "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
assert "…and names the project as the source"    "$(has 'projects/p1/project.md' "$(run projects/p1/tasks/t1.md)")"

reset cbmono; proj p1 jm; task p1 t1
assert "project owner = someone else -> refuses" "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"
assert "…and names the other owner"              "$(has "owned by 'jm'" "$(run projects/p1/tasks/t1.md)")"
assert "…and does not tell you to dispatch it"   "$(has 'do not dispatch it here' "$(run projects/p1/tasks/t1.md)")"

# One project each: the shared-board case this exists for.
reset cbmono; proj p1 cbmono; proj p2 jm; task p1 mine; task p2 theirs
assert "mine clears on a two-owner board"        "$([[ "$(rc projects/p1/tasks/mine.md)" == 0 ]] && echo 0 || echo 1)"
assert "theirs refuses on the same board"        "$([[ "$(rc projects/p2/tasks/theirs.md)" == 1 ]] && echo 0 || echo 1)"

echo
echo "== a task overrides its project, in both directions =="

reset cbmono; proj p1 jm; task p1 t1 cbmono
assert "task owner = me beats project = them"    "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
assert "…and names the task as the source"       "$(has 'tasks/t1.md' "$(run projects/p1/tasks/t1.md)")"

reset cbmono; proj p1 cbmono; task p1 t1 jm
assert "task owner = them beats project = me"    "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"

echo
echo "== fail closed when the clone is unconfigured =="

# An owned task on a clone with no ownerGithubUser: refusing costs a tick, clearing
# costs a double dispatch. The tie goes to refusing, and it says how to fix it.
reset; proj p1 jm; task p1 t1
assert "owned task, no ownerGithubUser -> refuses" "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"
assert "…and names the key to set"                 "$(has 'ownerGithubUser' "$(run projects/p1/tasks/t1.md)")"
assert "…and points at the LOCAL file"             "$(has 'instance.config.local.json' "$(run projects/p1/tasks/t1.md)")"

echo
echo "== the local override wins, and its absence changes nothing =="

reset jm; proj p1 cbmono; task p1 t1
assert "tracked self=jm, task=cbmono -> refuses"  "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"
printf '{ "ownerGithubUser": "cbmono" }\n' > "$INST/instance.config.local.json"
assert "local override flips it to clears"        "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
assert "…and --self reports the local value"      "$(has 'self: cbmono (from instance.config.local.json)' "$(run --self)")"
rm -f "$INST/instance.config.local.json"
assert "removing it restores the tracked answer"  "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"
assert "…and --self reports the tracked value"    "$(has 'self: jm (from instance.config.json)' "$(run --self)")"
# A local file that does not mention the key is not an override.
printf '{ "authorEmail": "someone@example.com" }\n' > "$INST/instance.config.local.json"
assert "a local file without the key defers"      "$(has 'self: jm (from instance.config.json)' "$(run --self)")"
reset; assert "no key anywhere -> --self says none" "$(has 'self: <none>' "$(run --self)")"

echo
echo "== case-insensitive, like GitHub =="

reset CBMono; proj p1 cbMONO; task p1 t1
assert "owner and self differ only in case"      "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"

echo
echo "== an empty value reads as absent, not as an owner =="

reset cbmono; proj p1 jm
printf -- '---\ntype: Task\nowner:\nstatus: ready\n---\n' > "$INST/projects/p1/tasks/t1.md"
assert "empty task owner falls through to project" "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"
printf -- '---\ntype: Project\nowner:\nstatus: active\n---\n' > "$INST/projects/p1/project.md"
assert "empty project owner falls through to self" "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"

echo
echo "== only the FIRST owner counts (the push-state repeated-key bug) =="

reset cbmono
printf -- '---\ntype: Task\nowner: cbmono\nowner: jm\nstatus: ready\n---\n' > "$INST/projects/p1/tasks/t1.md"
assert "first=me, second=them -> clears"         "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"
printf -- '---\ntype: Task\nowner: jm\nowner: cbmono\nstatus: ready\n---\n' > "$INST/projects/p1/tasks/t1.md"
assert "first=them, second=me -> refuses"        "$([[ "$(rc projects/p1/tasks/t1.md)" == 1 ]] && echo 0 || echo 1)"

echo
echo "== the BODY is not frontmatter =="

reset cbmono
printf -- '---\ntype: Task\nstatus: ready\n---\n\n# Context\nowner: jm\n' > "$INST/projects/p1/tasks/t1.md"
assert "an owner: line in the body is ignored"   "$([[ "$(rc projects/p1/tasks/t1.md)" == 0 ]] && echo 0 || echo 1)"

echo
echo "== unreadable or unusable input refuses (exit 2), never clears =="

reset cbmono
printf 'no frontmatter here\nowner: cbmono\n' > "$INST/projects/p1/tasks/t1.md"
assert "no frontmatter -> exit 2"                "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"
printf -- '---\ntype: Task\nowner: cbmono\nstatus: ready\n' > "$INST/projects/p1/tasks/t1.md"
assert "frontmatter never closed -> exit 2"      "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"

reset cbmono; task p1 t1 'not a username!'
assert "malformed owner value -> exit 2"         "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"
assert "…and says it is not a username"          "$(has 'not a GitHub username' "$(run projects/p1/tasks/t1.md)")"

reset 'not a username!'; task p1 t1 cbmono
assert "malformed ownerGithubUser -> exit 2"     "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"

reset cbmono; proj p1 jm; task p1 t1
printf 'no frontmatter\n' > "$INST/projects/p1/project.md"
assert "unreadable project.md -> exit 2"         "$([[ "$(rc projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"

reset cbmono
assert "a missing task path -> exit 2"           "$([[ "$(rc projects/p1/tasks/nope.md)" == 2 ]] && echo 0 || echo 1)"
assert "no arguments -> exit 2"                  "$([[ "$(rc)" == 2 ]] && echo 0 || echo 1)"
assert "an unknown flag -> exit 2"               "$([[ "$(rc --wat projects/p1/tasks/t1.md)" == 2 ]] && echo 0 || echo 1)"
assert "two paths -> exit 2"                     "$([[ "$(rc a.md b.md)" == 2 ]] && echo 0 || echo 1)"
OUTSIDE="$( ( cd "$TMP" && bash "$SCRIPT" --self >/dev/null 2>&1 ); echo $? )"
assert "outside an instance root -> exit 2"      "$([[ "$OUTSIDE" == 2 ]] && echo 0 || echo 1)"

echo
echo "== absolute paths and awkward paths =="

reset cbmono; proj p1 jm; task p1 t1
ABS="$( ( cd "$INST" && bash "$SCRIPT" "$INST/projects/p1/tasks/t1.md" >/dev/null 2>&1 ); echo $? )"
assert "an absolute task path resolves the project" "$([[ "$ABS" == 1 ]] && echo 0 || echo 1)"

# A path outside projects/ has no project to ask, which is not an error — it is
# simply unowned, i.e. this clone's, which is today's behaviour for everything.
reset cbmono
printf -- '---\ntype: Task\nstatus: ready\n---\n' > "$INST/loose-task.md"
assert "a task outside projects/ is unowned"     "$([[ "$(rc loose-task.md)" == 0 ]] && echo 0 || echo 1)"

# An instance path containing glob metacharacters: "$PWD" must be QUOTED in the
# prefix strip, or the absolute path is not reduced and the project lookup silently
# never happens — the SC2295 trap install.sh already had.
ODD="$TMP/od[d]/_ai-bridge-odd"; mkdir -p "$ODD/projects/p1/tasks"
printf 'stub\n' > "$ODD/SCHEMA.md"
printf '{ "ownerGithubUser": "cbmono" }\n' > "$ODD/instance.config.json"
printf -- '---\ntype: Project\nowner: jm\nstatus: active\n---\n' > "$ODD/projects/p1/project.md"
printf -- '---\ntype: Task\nstatus: ready\n---\n' > "$ODD/projects/p1/tasks/t1.md"
ODDRC="$( ( cd "$ODD" && bash "$SCRIPT" "$ODD/projects/p1/tasks/t1.md" >/dev/null 2>&1 ); echo $? )"
assert "glob-y instance path still finds the project" "$([[ "$ODDRC" == 1 ]] && echo 0 || echo 1)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
