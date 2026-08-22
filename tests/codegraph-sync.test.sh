#!/usr/bin/env bash
#
# codegraph-sync.test.sh — the refusals and the counting properties of
# .claude/scripts/codegraph-sync.sh.
#
# It shells out to a STUB `codegraph`, never the real one: the real binary would reindex
# the user's actual repositories, which is both slow and a mutation a test has no business
# making. The stub records every invocation, so "did it run sync twice on one repo?" is
# directly observable — which is the question two of these assertions ask.
#
# What matters here, in order:
#   · overlapping roots must not sync one repo twice (with --full that is a full reindex
#     twice), and must not inflate the count;
#   · a `find` failure must not be reported as success — an unreadable directory makes
#     find emit a PARTIAL list and exit non-zero, and neither a here-document nor a pipe
#     surfaces that, so "synced 3 of 30, exit 0" looks exactly like "synced all 30";
#   · it must never run `codegraph init` — indexing a repo is the user's decision;
#   · it must never delete an index — a zero-node one is NAMED, with the uninit command
#     printed for a human, the report-don't-delete stance of prune-worktrees.sh.
#
# ok() compares actual to expected, per this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/.claude/scripts/codegraph-sync.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cgsync-test.XXXXXX")"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-52s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-52s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# A stub codegraph. `status` answers from a per-repo file so a test can make an index look
# empty or unreadable; every call is appended to CALLS for later inspection.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/codegraph" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$PWD" >> "$CALLS"
case "$1" in
  status) if [ -f "$PWD/.codegraph/stub.json" ]; then cat "$PWD/.codegraph/stub.json"; else exit 1; fi ;;
  sync|index) exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/codegraph"
export PATH="$TMP/bin:$PATH"

mkrepo() { # <path> <nodeCount>
  mkdir -p "$1/.codegraph"
  printf '{"lastIndexed":"2026-01-01T00:00:00.000Z","nodeCount":%s}\n' "$2" > "$1/.codegraph/stub.json"
}

W="$TMP/ws"; mkrepo "$W/groupA/repo1" 100; mkrepo "$W/groupA/repo2" 200; mkrepo "$W/groupB/repo3" 300
run() { CALLS="$TMP/calls" bash "$SCRIPT" "$@" 2>"$TMP/err"; }

# --- overlapping roots ------------------------------------------------------
: > "$TMP/calls"; out="$(run "$W" "$W/groupA")"; rc=$?
ok "overlapping roots exit 0"            "$rc" 0
ok "…and count each repo once"           "$(printf '%s' "$out" | sed -n 's/.*: \([0-9]*\) index.*/\1/p')" 3
ok "…and sync each repo once"            "$(grep -c '^sync ' "$TMP/calls")" 3
: > "$TMP/calls"; run "$W" "$W" >/dev/null
ok "the same root twice syncs once each" "$(grep -c '^sync ' "$TMP/calls")" 3
# --full must not reindex twice either — that is the expensive version of the same bug.
: > "$TMP/calls"; run --full "$W" "$W/groupB" >/dev/null
ok "--full reindexes each repo once"     "$(grep -c '^index ' "$TMP/calls")" 3
ok "…and never mixes in a sync"          "$(grep -c '^sync ' "$TMP/calls")" 0

# --- a find failure is not success -----------------------------------------
mkdir -p "$W/blocked/sub"; chmod 000 "$W/blocked"
: > "$TMP/calls"; out="$(run "$W")"; rc=$?
ok "an unreadable dir makes it exit 1"   "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
ok "…and says discovery failed"          "$(grep -q 'FAILED  discovery' "$TMP/err" && echo yes || echo no)" yes
ok "…but still syncs what it did find"   "$(grep -c '^sync ' "$TMP/calls")" 3
chmod 755 "$W/blocked"

# --- the two standing refusals ---------------------------------------------
: > "$TMP/calls"; run "$W" >/dev/null
ok "it never runs codegraph init"        "$(grep -c '^init ' "$TMP/calls")" 0
ok "it never runs uninit"                "$(grep -c '^uninit ' "$TMP/calls")" 0

# A zero-node index is named, not removed: no extractor for that repo, so it can only
# ever answer nothing — but deleting it is a human's call.
mkrepo "$W/groupB/empty" 0
out="$(run "$W")"
ok "a zero-node index is reported EMPTY" "$(printf '%s' "$out" | grep -c 'EMPTY')" 1
ok "…with the uninit command printed"    "$(printf '%s' "$out" | grep -c 'codegraph uninit --force')" 1
ok "…and the index still exists"         "$([ -d "$W/groupB/empty/.codegraph" ] && echo yes || echo no)" yes

# --- a root that isn't there ------------------------------------------------
rc=0; run "$TMP/nope" >/dev/null || rc=$?
ok "a missing root exits non-zero"       "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
ok "…and names it"                       "$(grep -q 'no such directory' "$TMP/err" && echo yes || echo no)" yes

# --- no codegraph on PATH is a no-op, not an error --------------------------
rc=0; ( PATH="/usr/bin:/bin"; CALLS="$TMP/calls" bash "$SCRIPT" "$W" >/dev/null 2>&1 ) || rc=$?
ok "absent codegraph exits 0"            "$rc" 0

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
