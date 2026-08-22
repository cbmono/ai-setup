#!/usr/bin/env bash
#
# Exercises symlink/scripts/migrate-bundle.sh. The properties that matter most are
# the negative ones: the default run must change nothing on disk, a missing timestamp
# git cannot date must NOT be invented, and a dangling reference must be reported
# rather than rewritten — that decision belongs to /close-project step 6, where the
# task it points at is still readable.
#
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MIGRATE="$HERE/../symlink/scripts/migrate-bundle.sh"
VALIDATE="$HERE/../symlink/scripts/validate-bundle.sh"
[[ -f "$MIGRATE" ]] || { echo "migrate-bundle.test: not found at $MIGRATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/migrate-bundle-fixture.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
B="$TMP/bundle"
mkdir -p "$B"/{objectives,knowledge/findings,knowledge/services}
mkdir -p "$B"/projects/live/tasks
cd "$B"

echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json
echo '# Schema' > SCHEMA.md
TS="2026-01-01T00:00:00Z"

doc() { local p="$1"; shift; mkdir -p "$(dirname "$p")"; printf '%s\n' "$@" > "$p"; }

doc objectives/o.md '---' 'type: Objective' 'title: O' 'status: active' "timestamp: $TS" '---' 'body'
doc projects/live/project.md '---' 'type: Project' 'title: L' 'status: active' "timestamp: $TS" '---' 'body'
# valid, must not be touched
doc knowledge/findings/ok.md '---' 'type: Finding' 'title: OK' 'status: current' "timestamp: $TS" '---' 'body'
doc knowledge/services/ok.md '---' 'type: Service' 'title: OK' 'status: active' "timestamp: $TS" '---' 'body'
# mechanical fixes
doc knowledge/findings/open.md '---' 'type: Finding' 'title: F1' 'status: open' "timestamp: $TS" '---' 'body'
doc knowledge/findings/active.md '---' 'type: Finding' 'title: F2' 'status: active' "timestamp: $TS" '---' 'body'
doc knowledge/findings/nostatus.md '---' 'type: Finding' 'title: F3' "timestamp: $TS" '---' 'body'
doc knowledge/services/current.md '---' 'type: Service' 'title: S1' 'status: current' "timestamp: $TS" '---' 'body'
# NOT a mapping the script knows: it carries a meaning the script cannot read, so it
# must be reported and left alone rather than normalised into a fixed value.
doc knowledge/findings/unsupported.md '---' 'type: Finding' 'title: F5' 'status: wibble' "timestamp: $TS" '---' 'body'
doc knowledge/services/unsupported.md '---' 'type: Service' 'title: S2' 'status: retired' "timestamp: $TS" '---' 'body'
# timestamp from git
doc projects/live/tasks/task-001-nots.md '---' 'type: Task' 'title: T1' 'status: draft' '---' 'body'
# dangling ref — must be reported, never rewritten
doc projects/live/tasks/task-002-dangling.md '---' 'type: Task' 'title: T2' 'status: draft' \
  'depends_on: [ /projects/gone/tasks/task-009.md ]' "timestamp: $TS" '---' 'body'

git init -q -b main . && git add -A && git -c user.email=a@b -c user.name=a commit -qm init

# untracked after the commit: git cannot date it, so it must be SKIPPED not invented
doc knowledge/findings/untracked-nots.md '---' 'type: Finding' 'title: F4' 'status: current' '---' 'body'

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }

# A distinctive mode, to catch a repair that silently rewrites permissions.
chmod 664 knowledge/findings/open.md
MODE_BEFORE="$(stat -f '%Lp' knowledge/findings/open.md 2>/dev/null || stat -c '%a' knowledge/findings/open.md)"

BEFORE="$(find . -name '*.md' -exec shasum {} \; | sort)"
DRY="$(bash "$MIGRATE" 2>&1)"
AFTER_DRY="$(find . -name '*.md' -exec shasum {} \; | sort)"

echo "== the default run reports and changes nothing =="
assert "no file changed by a default run" "$([[ "$BEFORE" == "$AFTER_DRY" ]] && echo 0 || echo 1)"
assert "output says report only"          "$(printf '%s' "$DRY" | grep -q 'report only' && echo 0 || echo 1)"
assert "uses WOULD FIX, not FIXED"        "$(printf '%s' "$DRY" | grep -q 'WOULD FIX' && echo 0 || echo 1)"

echo "== each mechanical class is recognised =="
assert "Finding open -> current"      "$(printf '%s' "$DRY" | grep -q "Finding status 'open' -> current" && echo 0 || echo 1)"
assert "Finding active -> current"    "$(printf '%s' "$DRY" | grep -q "Finding status 'active' -> current" && echo 0 || echo 1)"
assert "Finding with no status"       "$(printf '%s' "$DRY" | grep -q 'Finding has no status' && echo 0 || echo 1)"
assert "Service current -> active"    "$(printf '%s' "$DRY" | grep -q "Service status 'current' -> active" && echo 0 || echo 1)"
assert "missing timestamp from git"   "$(printf '%s' "$DRY" | grep -q 'author date of the commit' && echo 0 || echo 1)"

echo "== an unestablished status is reported, never normalised =="
assert "an unknown Finding status is held for a human" \
  "$(printf '%s' "$DRY" | grep -q "Finding status 'wibble' is not a mapping" && echo 0 || echo 1)"
assert "an unknown Service status is held for a human" \
  "$(printf '%s' "$DRY" | grep -q "Service status 'retired' is not a mapping" && echo 0 || echo 1)"

echo "== the refusals =="
assert "a date git cannot supply is SKIPPED, not invented" \
  "$(printf '%s' "$DRY" | grep -q 'refusing to invent a date' && echo 0 || echo 1)"
assert "a dangling ref is left to a human"  "$(printf '%s' "$DRY" | grep -q 'HUMAN' && echo 0 || echo 1)"
assert "the dangling ref names /close-project step 6" \
  "$(printf '%s' "$DRY" | grep -q 'close-project step 6' && echo 0 || echo 1)"

echo "== valid documents are not mentioned =="
assert "knowledge/findings/ok.md untouched"  "$(printf '%s' "$DRY" | grep -q 'findings/ok.md' && echo 1 || echo 0)"
assert "knowledge/services/ok.md untouched" "$(printf '%s' "$DRY" | grep -q 'services/ok.md' && echo 1 || echo 0)"

echo "== --apply writes, and only the right things =="
bash "$MIGRATE" --apply >/dev/null 2>&1
assert "Finding open became current"   "$(grep -q '^status: current' knowledge/findings/open.md && echo 0 || echo 1)"
assert "Finding active became current" "$(grep -q '^status: current' knowledge/findings/active.md && echo 0 || echo 1)"
assert "Finding gained a status"       "$(grep -q '^status: current' knowledge/findings/nostatus.md && echo 0 || echo 1)"
assert "Service current became active" "$(grep -q '^status: active' knowledge/services/current.md && echo 0 || echo 1)"
assert "task gained a timestamp"       "$(grep -q '^timestamp: 20' projects/live/tasks/task-001-nots.md && echo 0 || echo 1)"
assert "the dangling ref was NOT rewritten" \
  "$(grep -q '/projects/gone/tasks/task-009.md' projects/live/tasks/task-002-dangling.md && echo 0 || echo 1)"
assert "the untracked file was NOT given a date" \
  "$(grep -q '^timestamp:' knowledge/findings/untracked-nots.md && echo 1 || echo 0)"
assert "a valid Finding kept its status" "$(grep -q '^status: current' knowledge/findings/ok.md && echo 0 || echo 1)"
assert "frontmatter still closes properly" \
  "$([[ "$(grep -c '^---$' knowledge/findings/nostatus.md)" == 2 ]] && echo 0 || echo 1)"
assert "an unknown Finding status survived --apply" \
  "$(grep -q '^status: wibble' knowledge/findings/unsupported.md && echo 0 || echo 1)"
assert "an unknown Service status survived --apply" \
  "$(grep -q '^status: retired' knowledge/services/unsupported.md && echo 0 || echo 1)"
assert "a repaired file keeps its original mode" \
  "$([[ "$(stat -f '%Lp' knowledge/findings/open.md 2>/dev/null || stat -c '%a' knowledge/findings/open.md)" == "$MODE_BEFORE" ]] && echo 0 || echo 1)"
assert "no temp file was left behind" \
  "$(find . -name '.migrate-bundle.*' | grep -q . && echo 1 || echo 0)"

echo "== idempotence =="
SECOND="$(bash "$MIGRATE" 2>&1)"
assert "a second run fixes nothing more" \
  "$(printf '%s' "$SECOND" | grep -q '0 would be fixed' && echo 0 || echo 1)"

echo "== the validator agrees, apart from what needs a human =="
set +e; VOUT="$(bash "$VALIDATE" 2>&1)"; set -e
assert "only the unestablished statuses still fail the enum check" \
  "$([[ "$(printf '%s' "$VOUT" | grep -c 'is not valid for type')" == 2 ]] && echo 0 || echo 1)"
assert "the dangling ref still errors" "$(printf '%s' "$VOUT" | grep -q 'dangling reference' && echo 0 || echo 1)"

echo "== refusing to run outside an instance root =="
mkdir -p "$TMP/x" && cd "$TMP/x"
set +e; bash "$MIGRATE" >/dev/null 2>&1; RC=$?; set -e
assert "exits 2 outside an instance root" "$([[ $RC -eq 2 ]] && echo 0 || echo 1)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
