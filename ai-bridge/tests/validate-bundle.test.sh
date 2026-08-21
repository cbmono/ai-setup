#!/usr/bin/env bash
#
# Exercises symlink/scripts/validate-bundle.sh against a throwaway bundle whose
# every document is a deliberate decision class: valid, invalid enum, missing
# field, dangling structural reference, declared-but-unwritten artifact, and the
# non-concept files that must NOT be validated at all.
#
# That last group is the point of several cases. The first version of the script
# validated `index.md`, `log.md`, `sources/` and `deliverables/` too, and buried 6
# real errors under 77 warnings on a live instance. A validator nobody reads is
# worse than none, so "these files are ignored" is a tested property.
#
# assert() follows the same convention as the other harnesses here: 0 is a PASS.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$HERE/../symlink/scripts/validate-bundle.sh"
[[ -f "$VALIDATOR" ]] || { echo "validate-bundle.test: validator not found at $VALIDATOR" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/validate-bundle-fixture.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
B="$TMP/bundle"
mkdir -p "$B"/{objectives,knowledge/findings}
mkdir -p "$B"/projects/live/{tasks,phases,sources,deliverables}
cd "$B"

echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json
echo '# Schema' > SCHEMA.md

TS="2026-01-01T00:00:00Z"

doc() { # <path> <body...>
  local p="$1"; shift
  mkdir -p "$(dirname "$p")"
  printf '%s\n' "$@" > "$p"
}

# --- valid documents -----------------------------------------------------------
doc objectives/good.md '---' 'type: Objective' 'title: Good' 'status: active' "timestamp: $TS" '---' 'body'
doc projects/live/project.md '---' 'type: Project' 'title: Live' 'kind: build' \
  'objective: /objectives/good.md' 'status: active' "timestamp: $TS" '---' 'body'
doc projects/live/phases/1-a.md '---' 'type: Phase' 'title: A' \
  'project: /projects/live/project.md' 'status: active' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-001-ok.md '---' 'type: Task' 'title: Ok' 'status: ready' \
  'objective: /objectives/good.md' 'phase: /projects/live/phases/1-a.md' "timestamp: $TS" '---' 'body'
doc knowledge/findings/good.md '---' 'type: Finding' 'title: F' 'category: learning' \
  'status: current' "timestamp: $TS" '---' 'body'

# --- one document per failure class -------------------------------------------
doc projects/live/tasks/task-002-bad-status.md '---' 'type: Task' 'title: Bad' \
  'status: activ' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-003-wrong-type-status.md '---' 'type: Task' 'title: Wrong' \
  'status: active' "timestamp: $TS" '---' 'a Task may not be "active" — that is a Project status'
doc projects/live/tasks/task-004-no-timestamp.md '---' 'type: Task' 'title: NoTs' 'status: draft' '---' 'body'
doc projects/live/tasks/task-005-no-type.md '---' 'title: NoType' 'status: draft' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-006-unknown-type.md '---' 'type: Sprint' 'title: Unknown' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-007-dangling.md '---' 'type: Task' 'title: Dangling' 'status: draft' \
  'depends_on: [ /projects/closed/tasks/task-009-gone.md ]' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-008-artifact.md '---' 'type: Task' 'title: Artifact' 'status: draft' \
  'artifacts: [ /projects/live/deliverables/not-written-yet.md ]' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-009-no-frontmatter.md '# just a heading, no frontmatter'

# --- files that must be IGNORED ------------------------------------------------
# Navigation and content. None of these carries frontmatter, and validating them
# is what drowned the first version.
doc projects/live/index.md '# Live — tasks' '* nothing'
doc projects/live/log.md '# Live — log'
doc projects/live/sources/README.md '# sources'
doc projects/live/deliverables/written.md '# a deliverable, not a concept doc'
doc projects/live/HANDOVER.md '# a doc a human dropped in'
doc index.md '# bundle index'
doc log.md '# activity log'

set +e
OUT="$(bash "$VALIDATOR" 2>&1)"; RC=$?
OUT_STRICT="$(bash "$VALIDATOR" --strict 2>&1)"; RC_STRICT=$?
set -e

pass=0; fail=0
assert() { # <label> <0|1>
  if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi
}
saw() { printf '%s\n' "$OUT" | grep -q -- "$1" && echo 0 || echo 1; }
not_seen() { printf '%s\n' "$OUT" | grep -q -- "$1" && echo 1 || echo 0; }

echo "== failure classes are each reported =="
assert "an invalid enum value is an error"        "$(saw "status 'activ' is not valid")"
assert "a valid-elsewhere status is wrong per type" "$(saw "status 'active' is not valid for type Task")"
assert "a missing timestamp is an error"          "$(saw 'missing required field: timestamp')"
assert "a missing type is an error"               "$(saw 'missing required field: type')"
assert "an unknown type is an error"              "$(saw "unknown type 'Sprint'")"
assert "a dangling depends_on is an error"        "$(saw 'dangling reference: /projects/closed/tasks/task-009-gone.md')"
assert "a concept doc with no frontmatter is an error" "$(saw 'no YAML frontmatter')"

echo "== artifacts warn, they do not fail =="
assert "an unwritten declared artifact WARNS"     "$(saw 'declared artifact does not exist yet')"
# The label and the message are on separate lines, so look at the pair.
assert "the artifact finding is labelled WARN, not ERROR" \
  "$(printf '%s\n' "$OUT" | grep -B1 'not-written-yet' | grep -q 'WARN' && echo 0 || echo 1)"
assert "no ERROR mentions the unwritten artifact" \
  "$(printf '%s\n' "$OUT" | grep -B1 'not-written-yet' | grep -q 'ERROR' && echo 1 || echo 0)"

echo "== valid documents are silent =="
for f in objectives/good.md projects/live/project.md projects/live/phases/1-a.md \
         projects/live/tasks/task-001-ok.md knowledge/findings/good.md; do
  assert "no complaint about $f" "$(not_seen "$f")"
done

echo "== non-concept files are never validated =="
for f in 'projects/live/index.md' 'projects/live/log.md' 'projects/live/sources/README.md' \
         'projects/live/deliverables/written.md' 'projects/live/HANDOVER.md' 'index.md' 'log.md'; do
  assert "ignored: $f" "$(printf '%s\n' "$OUT" | grep -E "(ERROR|WARN) +$f\$" | grep -q . && echo 1 || echo 0)"
done

echo "== exit codes =="
assert "errors make it exit 1"                    "$([[ $RC -eq 1 ]] && echo 0 || echo 1)"
assert "--strict also exits non-zero"             "$([[ $RC_STRICT -ne 0 ]] && echo 0 || echo 1)"

echo "== a clean bundle passes, and --strict still passes with no warnings =="
rm -f projects/live/tasks/task-00[2-9]*.md
set +e
CLEAN="$(bash "$VALIDATOR" 2>&1)"; CRC=$?
CLEAN_STRICT_RC=0; bash "$VALIDATOR" --strict >/dev/null 2>&1 || CLEAN_STRICT_RC=$?
set -e
assert "a clean bundle exits 0"                   "$([[ $CRC -eq 0 ]] && echo 0 || echo 1)"
assert "a clean bundle reports 0 errors"          "$(printf '%s\n' "$CLEAN" | grep -q '0 errors, 0 warnings' && echo 0 || echo 1)"
assert "--strict passes when there are no warnings" "$([[ $CLEAN_STRICT_RC -eq 0 ]] && echo 0 || echo 1)"

echo "== refusing to run outside an instance root =="
mkdir -p "$TMP/notabundle" && cd "$TMP/notabundle"
set +e; bash "$VALIDATOR" >/dev/null 2>&1; OUTSIDE=$?; set -e
assert "exits 2 without SCHEMA.md + instance.config.json" "$([[ $OUTSIDE -eq 2 ]] && echo 0 || echo 1)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
