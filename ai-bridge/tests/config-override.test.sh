#!/usr/bin/env bash
#
# config-override.test.sh — instance.config.local.json overrides the TRACKED config,
# for the documented set of per-machine keys, in every script that reads one.
#
# WHY. `instance.config.json` is tracked, so every value in it is a statement both
# clones of a shared bundle read. `reposRoot`, `worktreeRoot` and `boardInstances` are
# absolute paths on ONE machine, so a tracked value cannot be right for both. The
# override exists for exactly those, plus the two identity keys.
#
# The failure this file is built to catch is a HALF-HONOURED override: one reader picks
# it up and another does not, so the loop dispatches against one reposRoot while
# `link-repos.sh` links from another. That is worse than having no override at all,
# because nothing looks broken. So every reader is exercised, and there is a static
# check besides — a new reader added without the two-file lookup fails here rather than
# on someone's machine.
#
# The keys that are NOT overridable are asserted too, and they are the sharper half:
# `defaultOwner` and `people` are only correct while both clones agree, so an override
# is precisely the disagreement that breaks them (`defaultOwner`'s own case lives in
# task-owner.test.sh, where the two-clone fixture is).
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$TPL/symlink/scripts"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/config-override.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
has()    { printf '%s\n' "$2" | grep -q -- "$1" && echo 0 || echo 1; }
hasnt()  { printf '%s\n' "$2" | grep -q -- "$1" && echo 1 || echo 0; }

# Two candidate roots, so "which one did the script use" is answerable from output.
TRACKED_ROOT="$TMP/tracked-repos"; mkdir -p "$TRACKED_ROOT/repo-t/.git"
LOCAL_ROOT="$TMP/local-repos";     mkdir -p "$LOCAL_ROOT/repo-l/.git"

INST="$TMP/_ai-bridge-fixture"; mkdir -p "$INST"
printf 'stub\n' > "$INST/SCHEMA.md"
tracked() { printf '{\n  "org": "o",\n  "reposRoot": "%s"\n}\n' "$TRACKED_ROOT" > "$INST/instance.config.json"; }
local_cfg() { printf '%s\n' "$1" > "$INST/instance.config.local.json"; }
no_local() { rm -f "$INST/instance.config.local.json"; }
tracked

echo "== link-repos.sh: which reposRoot did it link from? =="
no_local
OUT="$( cd "$INST" && bash "$SCRIPTS/link-repos.sh" 2>&1 )"
assert "no local file -> the tracked root"       "$(has 'repo-t' "$OUT")"
assert "…and not the other one"                  "$(hasnt 'repo-l' "$OUT")"
( cd "$INST" && bash "$SCRIPTS/link-repos.sh" --remove >/dev/null 2>&1 )
local_cfg "{ \"reposRoot\": \"$LOCAL_ROOT\" }"
OUT="$( cd "$INST" && bash "$SCRIPTS/link-repos.sh" 2>&1 )"
assert "with the override -> the local root"     "$(has 'repo-l' "$OUT")"
assert "…and the tracked one is not used"        "$(hasnt 'repo-t' "$OUT")"
( cd "$INST" && bash "$SCRIPTS/link-repos.sh" --remove >/dev/null 2>&1 )
# A local file that does not mention the key is not an override.
local_cfg '{ "ownerGithubUser": "example-user-007" }'
OUT="$( cd "$INST" && bash "$SCRIPTS/link-repos.sh" 2>&1 )"
assert "a local file without the key defers"     "$(has 'repo-t' "$OUT")"
( cd "$INST" && bash "$SCRIPTS/link-repos.sh" --remove >/dev/null 2>&1 )

echo
echo "== prune-worktrees.sh: reposRoot and worktreeRoot =="
# Naming a root that does not exist is the cheapest unambiguous probe: the script
# reports the path it resolved, so the message says which file answered.
local_cfg '{ "reposRoot": "/nonexistent-local-root" }'
OUT="$( cd "$INST" && bash "$SCRIPTS/prune-worktrees.sh" 2>&1 )"; RC=$?
assert "the overridden reposRoot is the one used" "$(has 'nonexistent-local-root' "$OUT")"
assert "…and it refuses rather than guessing"    "$([[ $RC -ne 0 ]] && echo 0 || echo 1)"
no_local
OUT="$( cd "$INST" && bash "$SCRIPTS/prune-worktrees.sh" 2>&1 )"
assert "without the override, the tracked root"  "$(hasnt 'nonexistent-local-root' "$OUT")"
# worktreeRoot: an overridden path that does not exist is reported by name.
local_cfg '{ "worktreeRoot": "/nonexistent-local-wt" }'
OUT="$( cd "$INST" && bash "$SCRIPTS/prune-worktrees.sh" 2>&1 )"
assert "the overridden worktreeRoot is used"     "$(has 'nonexistent-local-wt' "$OUT")"
# Absent from both, the documented fallback still applies: <reposRoot>/_wt.
no_local
OUT="$( cd "$INST" && bash "$SCRIPTS/prune-worktrees.sh" 2>&1 )"
assert "absent worktreeRoot -> <reposRoot>/_wt"  "$(has '_wt' "$OUT")"

echo
echo "== index-kb.sh: reposRoot (behind a stubbed codegraph) =="
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/codegraph"; chmod +x "$TMP/bin/codegraph"
local_cfg '{ "reposRoot": "/nonexistent-local-root" }'
OUT="$( cd "$INST" && PATH="$TMP/bin:$PATH" bash "$SCRIPTS/index-kb.sh" 2>&1 )"
assert "the overridden reposRoot is the one used" "$(has 'nonexistent-local-root' "$OUT")"
no_local
OUT="$( cd "$INST" && PATH="$TMP/bin:$PATH" bash "$SCRIPTS/index-kb.sh" 2>&1 )"
assert "without it, the tracked root is used"     "$(hasnt 'nonexistent-local-root' "$OUT")"
# codegraphSkip is NOT overridable: it names repos, which both clones share. Assert
# the extraction line itself, not proximity — the file mentions both names elsewhere.
assert "codegraphSkip is extracted from \$CONFIG only" \
  "$(grep -n 'codegraphSkip' "$SCRIPTS/index-kb.sh" | grep -v '^[0-9]*:#' \
     | grep -q 'CONFIG_SKIP=.*"\$CONFIG"' && echo 0 || echo 1)"

echo
echo "== build-board.sh: boardInstances =="
if command -v python3 >/dev/null 2>&1; then
  mk_inst() { mkdir -p "$1"; printf '{"group":"%s","counts":{"projects":0,"tasks":0,"awaiting":0},"projects":[]}\n' "$2" > "$1/SNAPSHOT.json"; }
  mk_inst "$TMP/inst-tracked" tracked-group
  mk_inst "$TMP/inst-local"   local-group
  printf '{\n  "org": "o",\n  "boardInstances": ["%s"]\n}\n' "$TMP/inst-tracked" > "$INST/instance.config.json"
  no_local
  ( cd "$INST" && bash "$SCRIPTS/build-board.sh" --out "$TMP/b1.html" >/dev/null 2>&1 )
  assert "no local file -> the tracked list"     "$(has 'tracked-group' "$(cat "$TMP/b1.html" 2>/dev/null)")"
  local_cfg "{ \"boardInstances\": [\"$TMP/inst-local\"] }"
  ( cd "$INST" && bash "$SCRIPTS/build-board.sh" --out "$TMP/b2.html" >/dev/null 2>&1 )
  B2="$(cat "$TMP/b2.html" 2>/dev/null)"
  assert "with the override -> the local list"   "$(has 'local-group' "$B2")"
  assert "…and not the tracked one"              "$(hasnt 'tracked-group' "$B2")"
  # An unreadable local file must not blank the board: the tracked list still answers.
  local_cfg '{ not json at all'
  ( cd "$INST" && bash "$SCRIPTS/build-board.sh" --out "$TMP/b3.html" >"$TMP/b3.out" 2>&1 )
  assert "an unreadable local file falls back"   "$(has 'tracked-group' "$(cat "$TMP/b3.html" 2>/dev/null)")"
  assert "…and says so without claiming more"    "$(has 'ignoring it' "$(cat "$TMP/b3.out")")"
  no_local
  tracked
else
  echo "  (python3 absent — build-board cases skipped)"
fi

echo
echo "== static: every reader of an overridable key does the two-file lookup =="
# The drift guard. A reader added later that parses only instance.config.json makes the
# override a half-truth, which is the failure mode this file exists for.
for pair in "link-repos.sh:reposRoot" "index-kb.sh:reposRoot" \
            "prune-worktrees.sh:reposRoot" "prune-worktrees.sh:worktreeRoot" \
            "build-board.sh:boardInstances" "commit-as.sh:authorEmail" \
            "task-owner.sh:ownerGithubUser"; do
  f="${pair%%:*}"; k="${pair##*:}"
  assert "$f reads $k, and knows the local file" \
    "$( grep -q "$k" "$SCRIPTS/$f" && grep -q 'instance.config.local.json' "$SCRIPTS/$f" && echo 0 || echo 1 )"
done
# And the two keys that must NOT be overridable are read from the tracked file only.
assert "task-owner.sh reads defaultOwner from the tracked config" \
  "$(grep -q 'json_string "\$CONFIG" defaultOwner' "$SCRIPTS/task-owner.sh" && echo 0 || echo 1)"
assert "…and never from the local one" \
  "$(grep -q 'LOCAL_CONFIG" defaultOwner' "$SCRIPTS/task-owner.sh" && echo 1 || echo 0)"
assert "commit-as.sh reads people from the tracked config" \
  "$(grep -q 'TRACKED_CONFIG' "$SCRIPTS/commit-as.sh" && echo 0 || echo 1)"
assert "…and never people from the local one" \
  "$(grep -q 'LOCAL_CONFIG.*people\|people.*LOCAL_CONFIG' "$SCRIPTS/commit-as.sh" && echo 1 || echo 0)"

echo
echo "== the overridable set is documented in ONE place =="
SCHEMA="$TPL/symlink/SCHEMA.md"
assert "SCHEMA.md has the override section" \
  "$(grep -q '^## Per-machine config overrides' "$SCHEMA" && echo 0 || echo 1)"
for k in ownerGithubUser authorEmail reposRoot worktreeRoot boardInstances defaultOwner people; do
  assert "…and names $k"  "$(grep -q "\`$k\`" "$SCHEMA" && echo 0 || echo 1)"
done
assert "…and states the worktreeRoot fallback" \
  "$(grep -q '<reposRoot>/_wt' "$SCHEMA" && echo 0 || echo 1)"
assert "…and that worktreeRoot must not sit inside reposRoot" \
  "$(grep -q 'never sit inside' "$SCHEMA" && echo 0 || echo 1)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
