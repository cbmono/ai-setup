#!/usr/bin/env bash
# Exercises the autonomy-aware draft->ready guard in commit-as.sh.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/symlink/scripts/commit-as.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

setup() {
  rm -rf "$TMP/repo"; mkdir -p "$TMP/repo"; cd "$TMP/repo"
  git init -q .; git config user.email "t@example.com"; git config user.name "Test Human"
  printf '{ "authorEmail": "t@example.com" }\n' > instance.config.json
  mkdir -p projects/yolo-proj/tasks projects/gated-proj/tasks projects/noauto-proj/tasks
  printf 'type: Project\nautonomy: yolo\nstatus: active\n' > projects/yolo-proj/project.md
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
  out="$("$SCRIPT" "$role" "test: $name" 2>&1)"; rc=$?
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

setup; task projects/yolo-proj/tasks/t1.md build ready
check "yolo + build -> loop may promote" allow project-manager projects/yolo-proj/tasks/t1.md

setup; task projects/gated-proj/tasks/t1.md build ready
check "gated + build -> blocked" block project-manager projects/gated-proj/tasks/t1.md

setup; task projects/yolo-proj/tasks/t1.md research ready
check "yolo + research -> blocked (human-driven)" block project-manager projects/yolo-proj/tasks/t1.md

setup; task projects/noauto-proj/tasks/t1.md build ready
check "no autonomy field -> defaults gated, blocked" block project-manager projects/noauto-proj/tasks/t1.md

setup; task projects/gated-proj/tasks/t1.md build ready
check "human may always promote" allow human projects/gated-proj/tasks/t1.md

setup; task projects/gated-proj/tasks/t1.md build draft
check "no status:ready staged -> untouched" allow project-manager projects/gated-proj/tasks/t1.md

setup; task projects/yolo-proj/tasks/t1.md build ready; task projects/gated-proj/tasks/t2.md build ready
check "mixed batch -> blocked on the gated one" block project-manager projects/yolo-proj/tasks/t1.md projects/gated-proj/tasks/t2.md

setup; printf 'type: Task\nkind: build\nstatus: ready\n' > projects/yolo-proj/tasks/t1.md
git add projects/yolo-proj/tasks/t1.md >/dev/null
git commit -q --author="project-manager <t@example.com>" -m seed >/dev/null
printf 'type: Task\nkind: build\nstatus: in-progress\n' > projects/yolo-proj/tasks/t1.md
check "ready -> in-progress (not an added ready line)" allow project-manager projects/yolo-proj/tasks/t1.md

setup; task "projects/yolo-proj/tasks/task with spaces.md" build ready
check "path with spaces, yolo+build" allow project-manager "projects/yolo-proj/tasks/task with spaces.md"

setup; task "projects/gated-proj/tasks/task with spaces.md" build ready
check "path with spaces, gated -> blocked" block project-manager "projects/gated-proj/tasks/task with spaces.md"

setup; task projects/yolo-proj/tasks/t1.md unset-kind ready
sed -i.bak '/^kind:/d' projects/yolo-proj/tasks/t1.md; rm -f projects/yolo-proj/tasks/t1.md.bak
check "yolo but kind missing -> blocked (fail closed)" block project-manager projects/yolo-proj/tasks/t1.md

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
