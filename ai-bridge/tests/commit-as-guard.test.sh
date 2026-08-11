#!/usr/bin/env bash
# Exercises the autonomy-aware draft->ready guard in commit-as.sh.
#
# Delegation requires AUTONOMY.md at the repo root (the capability file). setup()
# creates it; the "capability absent" cases delete it to prove the guard gates on
# presence, not just on the autonomy field.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/symlink/scripts/commit-as.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

setup() {
  rm -rf "$TMP/repo"; mkdir -p "$TMP/repo"; cd "$TMP/repo" || exit 1
  git init -q .; git config user.email "t@example.com"; git config user.name "Test Human"
  printf '{ "authorEmail": "t@example.com" }\n' > instance.config.json
  # The capability file: without it every autonomy value is inert (see commit-as.sh).
  printf -- '---\ntype: Reference\n---\n# Delegated authority\n' > AUTONOMY.md
  mkdir -p projects/delegated-proj/tasks projects/gated-proj/tasks projects/noauto-proj/tasks projects/other-proj/tasks
  printf 'type: Project\nautonomy: delegatedmode\nstatus: active\n' > projects/delegated-proj/project.md
  printf 'type: Project\nautonomy: somefuturemode\nstatus: active\n' > projects/other-proj/project.md
  printf 'type: Project\nautonomy: gated\nstatus: active\n' > projects/gated-proj/project.md
  printf 'type: Project\nstatus: active\n' > projects/noauto-proj/project.md
  git add -A >/dev/null; git commit -qm init
}

task() { # <path> <kind> <status>
  printf 'type: Task\nkind: %s\nstatus: %s\n' "$2" "$3" > "$1"
}

check() { # <name> <expected: allow|block> <role> <files-to-stage...>
  local name="$1" expect="$2" role="$3"; shift 3
  git add "$@" >/dev/null
  local out rc
  # Commit the same paths that were staged: the shared-index guard requires a
  # non-human role to name what it commits, and this is the form agents use.
  out="$("$SCRIPT" "$role" "test: $name" -- "$@" 2>&1)"; rc=$?
  local got; if [ "$rc" -eq 0 ]; then got=allow; else got=block; fi
  if [ "$got" = "$expect" ]; then
    printf '  PASS  %-52s (%s, rc=%s)\n' "$name" "$got" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-52s expected %s got %s (rc=%s)\n' "$name" "$expect" "$got" "$rc"
    printf '        output: %s\n' "$(printf '%s' "$out" | head -4 | tr '\n' '|')"
    fail=$((fail+1))
  fi
  git reset -q --hard HEAD >/dev/null 2>&1 || true
}

echo "== autonomy-aware draft->ready guard =="

setup; task projects/delegated-proj/tasks/t1.md build ready
check "delegated + build -> loop may promote" allow project-manager projects/delegated-proj/tasks/t1.md

setup; task projects/gated-proj/tasks/t1.md build ready
check "gated + build -> blocked" block project-manager projects/gated-proj/tasks/t1.md

setup; task projects/delegated-proj/tasks/t1.md research ready
check "delegated + research -> blocked (human-driven)" block project-manager projects/delegated-proj/tasks/t1.md

setup; task projects/noauto-proj/tasks/t1.md build ready
check "no autonomy field -> defaults gated, blocked" block project-manager projects/noauto-proj/tasks/t1.md

setup; task projects/gated-proj/tasks/t1.md build ready
check "human may always promote" allow human projects/gated-proj/tasks/t1.md

setup; task projects/gated-proj/tasks/t1.md build draft
check "no status:ready staged -> untouched" allow project-manager projects/gated-proj/tasks/t1.md

setup; task projects/delegated-proj/tasks/t1.md build ready; task projects/gated-proj/tasks/t2.md build ready
check "mixed batch -> blocked on the gated one" block project-manager projects/delegated-proj/tasks/t1.md projects/gated-proj/tasks/t2.md

setup; printf 'type: Task\nkind: build\nstatus: ready\n' > projects/delegated-proj/tasks/t1.md
git add projects/delegated-proj/tasks/t1.md >/dev/null
git commit -q --author="project-manager <t@example.com>" -m seed >/dev/null
printf 'type: Task\nkind: build\nstatus: in-progress\n' > projects/delegated-proj/tasks/t1.md
check "ready -> in-progress (not an added ready line)" allow project-manager projects/delegated-proj/tasks/t1.md

setup; task "projects/delegated-proj/tasks/task with spaces.md" build ready
check "path with spaces, delegated+build" allow project-manager "projects/delegated-proj/tasks/task with spaces.md"

setup; task "projects/gated-proj/tasks/task with spaces.md" build ready
check "path with spaces, gated -> blocked" block project-manager "projects/gated-proj/tasks/task with spaces.md"

setup; task projects/delegated-proj/tasks/t1.md unset-kind ready
sed -i.bak '/^kind:/d' projects/delegated-proj/tasks/t1.md; rm -f projects/delegated-proj/tasks/t1.md.bak
check "delegated but kind missing -> blocked (fail closed)" block project-manager projects/delegated-proj/tasks/t1.md

setup
sed -i.bak 's/^autonomy: delegatedmode$/autonomy: delegatedmode unexpected/' projects/delegated-proj/project.md; rm -f projects/delegated-proj/project.md.bak
git add projects/delegated-proj/project.md >/dev/null; git commit -qm "malformed autonomy" >/dev/null
task projects/delegated-proj/tasks/t1.md build ready
check "malformed autonomy value -> blocked (fail closed)" block project-manager projects/delegated-proj/tasks/t1.md

# --- the capability file is the on/off switch -------------------------------
setup; rm -f AUTONOMY.md; task projects/delegated-proj/tasks/t1.md build ready
check "no AUTONOMY.md -> delegated project still blocked" block project-manager projects/delegated-proj/tasks/t1.md

setup; rm -f AUTONOMY.md; task projects/gated-proj/tasks/t1.md build draft
check "no AUTONOMY.md, no promotion staged -> untouched" allow project-manager projects/gated-proj/tasks/t1.md

# Guard checks that delegation is POSSIBLE, not which mode delegates what — that
# distinction is AUTONOMY.md's, so any non-gated mode passes the script's check.
setup; task projects/other-proj/tasks/t1.md build ready
check "AUTONOMY.md + non-gated mode + build -> allowed" allow project-manager projects/other-proj/tasks/t1.md

setup; rm -f AUTONOMY.md; task projects/other-proj/tasks/t1.md build ready
check "non-gated mode but no AUTONOMY.md -> blocked" block project-manager projects/other-proj/tasks/t1.md

echo
echo "== shared-index guard: an agent must name what it commits =="

# raw() runs the script with arbitrary trailing args (check() always appends
# pathspecs, which is exactly what these cases need to vary).
raw() { # <name> <expected: allow|block> <role> [args...]
  local name="$1" expect="$2" role="$3"; shift 3
  local out rc
  out="$("$SCRIPT" "$role" "test: $name" "$@" 2>&1)"; rc=$?
  local got; if [ "$rc" -eq 0 ]; then got=allow; else got=block; fi
  if [ "$got" = "$expect" ]; then
    printf '  PASS  %-52s (%s, rc=%s)\n' "$name" "$got" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-52s expected %s got %s (rc=%s)\n' "$name" "$expect" "$got" "$rc"
    printf '        output: %s\n' "$(printf '%s' "$out" | head -4 | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

setup; task projects/gated-proj/tasks/t1.md build draft; git add projects/gated-proj/tasks/t1.md >/dev/null
raw "agent role, no paths, no --all-staged -> blocked" block project-manager

setup; task projects/gated-proj/tasks/t1.md build draft; git add projects/gated-proj/tasks/t1.md >/dev/null
raw "agent role + --all-staged -> allowed (explicit opt-out)" allow project-manager --all-staged

setup; task projects/gated-proj/tasks/t1.md build draft; git add projects/gated-proj/tasks/t1.md >/dev/null
raw "human is exempt from naming paths" allow human

setup; task projects/gated-proj/tasks/t1.md build draft; git add projects/gated-proj/tasks/t1.md >/dev/null
raw "'--' with no paths after it -> usage error" block project-manager --

setup; task projects/gated-proj/tasks/t1.md build draft; git add projects/gated-proj/tasks/t1.md >/dev/null
raw "--all-staged AND paths -> refused as ambiguous" block project-manager --all-staged -- projects/gated-proj/tasks/t1.md

# The actual bug this guard exists to prevent: agent A commits its own file while
# agent B has an unrelated file staged in the same shared working tree. A's commit
# must contain ONLY A's file, and B's must still be staged afterwards.
setup
printf 'mine\n' > mine.txt; printf 'sibling in progress\n' > sibling.txt
git add mine.txt sibling.txt >/dev/null
if "$SCRIPT" software-engineer "test: commit only my own path" -- mine.txt >/dev/null 2>&1; then
  committed="$(git show --name-only --format= HEAD | tr -d ' ')"
  still_staged="$(git diff --cached --name-only)"
  if [ "$committed" = "mine.txt" ] && [ "$still_staged" = "sibling.txt" ]; then
    printf '  PASS  %-52s (committed=%s, still staged=%s)\n' \
      "sibling's staged file is NOT swept in" "$committed" "$still_staged"; pass=$((pass+1))
  else
    printf '  FAIL  %-52s committed=[%s] still_staged=[%s]\n' \
      "sibling's staged file is NOT swept in" "$committed" "$still_staged"; fail=$((fail+1))
  fi
else
  printf '  FAIL  %-52s script exited non-zero\n' "sibling's staged file is NOT swept in"; fail=$((fail+1))
fi

# Pathspec scoping of the promotion guard: a sibling's staged promotion into a
# GATED project must not block an agent committing an unrelated path of its own.
setup
task projects/gated-proj/tasks/sibling.md build ready      # sibling's illegal promotion
printf 'mine\n' > mine.txt
git add projects/gated-proj/tasks/sibling.md mine.txt >/dev/null
raw "sibling's staged promotion does not block my paths" allow project-manager -- mine.txt

# ...but the same promotion inside MY pathspec is still refused.
setup
task projects/gated-proj/tasks/t1.md build ready
git add projects/gated-proj/tasks/t1.md >/dev/null
raw "promotion inside my own pathspec is still blocked" block project-manager -- projects/gated-proj/tasks/t1.md

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
