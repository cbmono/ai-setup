#!/usr/bin/env bash
#
# Exercises the board pair: scripts/write-snapshot.sh (writer) and
# scripts/build-board.sh (renderer).
#
# The properties that matter are the negative ones, in this order:
#   · THE OFF SWITCH. No SNAPSHOT.json ⇒ the writer writes nothing and exits 0, the
#     board omits that instance entirely, and an `install.sh` re-run after `rm` does
#     NOT resurrect the file (the FIRST_STAMP property, same as AWAITING.md). Get any
#     of those wrong and "delete the file to take this instance off the board" stops
#     being true, which is the one promise the whole feature rests on.
#   · THE FIELD ALLOWLIST IS A DATA-GOVERNANCE BOUNDARY, not a format. The board's
#     HTML can be published to a URL, so the snapshot must carry strictly less than
#     AWAITING.md does: no task `description:`, no document body, no open-question or
#     blocker TEXT (a count and a verb instead), no author identity, and no path
#     outside the bundle. These cases assert the ABSENCE of each, plus that no key
#     outside the documented set is emitted at all — so a field added without reading
#     the header fails here rather than on a published page.
#   · UNTRUSTED TEXT REACHES AN HTML SINK. A task title is human-written free text
#     that ends up in markup, so an HTML-metacharacter title must appear escaped and
#     ZERO times raw, and a `javascript:`/`data:` PR URL must render as inert text
#     rather than a link — the writer already refuses to collect one, and the board
#     does not trust it to have done so.
#   · ZERO EXTERNAL REQUESTS. No <script> anywhere, no `@import`, no `src`/`url()`
#     fetch, and every http(s) href is a PR link. A board is a reporting page; it has
#     no business phoning anywhere, and a published one must not be able to.
#   · A BROKEN INSTANCE CANNOT BLANK THE BOARD. A malformed snapshot is a visible
#     note and exit 0, with the other instances still rendered.
#
# The fixture builds its own instances in a temp dir, so these assertions describe
# this test's content rather than whatever the real bundles happen to hold today. The
# hostile snapshot is HAND-WRITTEN on purpose: the writer cannot produce a
# `javascript:` PR URL, and the renderer's defence has to be tested independently of
# the writer's.
#
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
WRITER="$TPL/symlink/scripts/write-snapshot.sh"
BOARD="$TPL/symlink/scripts/build-board.sh"
BRIDGE_INSTALL="$TPL/install.sh"
for f in "$WRITER" "$BOARD" "$BRIDGE_INSTALL"; do
  [[ -f "$f" ]] || { echo "snapshot.test: missing $f" >&2; exit 2; }
done
# build-board.sh needs python3 by design (see its header): parsing arbitrary JSON and
# HTML-escaping are the two things a hand-rolled awk reader gets wrong on exactly the
# input this test feeds it. A machine without it cannot run the board at all, so say
# that rather than reporting green on half a feature.
command -v python3 >/dev/null 2>&1 || {
  echo "snapshot.test: needs python3 (build-board.sh does too — see its header)." >&2; exit 2; }

# `cd`+`pwd` normalises the path: TMPDIR carries a trailing slash on macOS, so the raw
# mktemp result contains `//` — which Python's Path() collapses, silently making the
# "no filesystem path on the page" assertion below match nothing either way.
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/snapshot-fixture.XXXXXX")" && pwd)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
has()    { printf '%s\n' "$2" | grep -qF -- "$1" && echo 0 || echo 1; }
hasnt()  { printf '%s\n' "$2" | grep -qF -- "$1" && echo 1 || echo 0; }
fhas()   { grep -qF -- "$1" "$2" && echo 0 || echo 1; }
fhasnt() { grep -qF -- "$1" "$2" && echo 1 || echo 0; }
eq()     { [[ "$1" == "$2" ]] && echo 0 || echo 1; }

# Strings that must never leave a task document. Each is planted in exactly one place
# the snapshot is forbidden to read, so a leak names its own source.
SECRET_DESC="SECRET-TASK-DESCRIPTION"
SECRET_BODY="SECRET-DOCUMENT-BODY"
SECRET_QUESTION="SECRET-QUESTION-TEXT"
SECRET_BLOCKER="SECRET-BLOCKER-REASON"
SECRET_EMAIL="secret-person@example.com"
OUT_OF_BUNDLE="/tmp/SECRET-OUT-OF-BUNDLE-ROOT"
# An HTML-metacharacter title, and the two forms it may appear in on the page.
HOSTILE_TITLE='<script>alert(1)</script> & <b>bold</b>'
HOSTILE_ESCAPED='&lt;script&gt;alert(1)&lt;/script&gt;'

echo "== shell portability of the shipped scripts =="
# These two scripts get symlinked into instances on machines this repo never sees, so
# a GNU-only regex escape is a silent wrong ANSWER rather than an error: `\b` in an ERE
# degrades count_questions to its 1-item fallback on a grep that does not implement it.
# NOTE, honestly: this machine's /usr/bin/grep is BSD grep 2.6.0-FreeBSD, which DOES
# support \b — verified, including that it is a true word boundary and not a literal
# `b`. So no runtime fixture can demonstrate the difference here, and asserting one
# would be a test that passes for the wrong reason. The portable POSIX bracket form is
# used instead, and THIS is the assertion that holds the line: a static check that the
# escape has not come back. It is the only form of this test that can actually fail.
# Comment lines are stripped first: the fix's own comment NAMES the escape it removed,
# and that prose is the record of why. Only executable lines are checked.
no_gnu_escape() { # <file> <escape letter>
  sed 's/^[[:space:]]*#.*$//' "$1" | grep -q "\\\\$2" && return 1 || return 0
}
for f in "$WRITER" "$BOARD"; do
  assert "no GNU-only \\b escape in $(basename "$f")" "$(yes_if no_gnu_escape "$f" b)"
  assert "no GNU-only \\s escape in $(basename "$f")" "$(yes_if no_gnu_escape "$f" s)"
done

# ---------------------------------------------------------------- fixture instances
new_instance() { # <dir> — the minimum the writer requires of an instance root
  mkdir -p "$1"
  : > "$1/SCHEMA.md"
  cat > "$1/instance.config.json" <<CFG
{
  "org": "fixture-org",
  "reposRoot": "$OUT_OF_BUNDLE",
  "worktreeRoot": "$OUT_OF_BUNDLE/_wt",
  "authorEmail": "$SECRET_EMAIL"
}
CFG
}

ALPHA="$TMP/group/_ai-bridge-alpha"     # full content, and the one the writer runs in
BETA="$TMP/group/_ai-bridge-beta"       # malformed snapshot
GAMMA="$TMP/group/_ai-bridge-gamma"     # no snapshot at all — off the board
DELTA="$TMP/group/_ai-bridge-delta"     # hand-written hostile snapshot
new_instance "$ALPHA"; new_instance "$BETA"; new_instance "$GAMMA"; new_instance "$DELTA"

mkdir -p "$ALPHA/projects/ci/tasks" "$ALPHA/projects/ci/phases" \
         "$ALPHA/projects/empty" "$ALPHA/projects/finished/tasks"

cat > "$ALPHA/projects/ci/project.md" <<PRJ
---
type: Project
title: CI hardening
description: make the pipeline boring again
kind: build
status: active
autonomy: gated
---
# Context
$SECRET_BODY
PRJ
cat > "$ALPHA/projects/ci/phases/phase-1.md" <<'PH'
---
type: Phase
title: Groundwork
order: 1
status: done
---
PH
cat > "$ALPHA/projects/ci/phases/phase-2.md" <<'PH'
---
type: Phase
title: Rollout
order: 2
status: active
---
PH

# draft + open questions  ⇒ awaiting "answer", carrying the COUNT and not the text
cat > "$ALPHA/projects/ci/tasks/task-001.md" <<TSK
---
type: Task
title: '$HOSTILE_TITLE'
kind: build
status: draft
assignee: software-engineer
phase: projects/ci/phases/phase-1.md
description: $SECRET_DESC
open_questions: [ "Q1: $SECRET_QUESTION", "Q2: $SECRET_QUESTION again" ]
acceptance_criteria: []
pr: []
---
# Notes
$SECRET_BODY
TSK
# in-review + a PR  ⇒ awaiting "merge"
cat > "$ALPHA/projects/ci/tasks/task-002.md" <<TSK
---
type: Task
title: Bump the pinned toolchain
kind: build
status: in-review
assignee: software-engineer
open_questions: []
pr: [ "https://github.com/acme/monorepo/pull/2725" ]
---
TSK
# blocked  ⇒ awaiting "unblock", the VERB and never the reason
cat > "$ALPHA/projects/ci/tasks/task-003.md" <<TSK
---
type: Task
title: Rotate the publish token
kind: build
status: blocked
assignee: devops-engineer
description: blocked because $SECRET_BLOCKER
open_questions: []
---
# Notes
$SECRET_BLOCKER
TSK
# refined draft, no questions  ⇒ awaiting "approve" (the promote gate; a task already
# at `ready` awaits nothing — it is waiting on a dispatch, not on a human)
cat > "$ALPHA/projects/ci/tasks/task-004.md" <<'TSK'
---
type: Task
title: Add a smoke test
kind: build
status: draft
assignee: qa-reviewer
open_questions: []
acceptance_criteria: [ "it runs in CI" ]
---
TSK
# in-progress  ⇒ in_flight, awaiting nothing
cat > "$ALPHA/projects/ci/tasks/task-005.md" <<'TSK'
---
type: Task
title: Cache the dependency store
kind: build
status: in-progress
assignee: software-engineer
---
TSK

# A project with no tasks at all — must render empty rather than error.
cat > "$ALPHA/projects/empty/project.md" <<'PRJ'
---
type: Project
title: Nothing here yet
description: scaffolded, not started
kind: research
status: active
---
PRJ

# Every task terminal ⇒ the board shows a close PROPOSAL, never an action.
cat > "$ALPHA/projects/finished/project.md" <<'PRJ'
---
type: Project
title: Docs cleanup
kind: build
status: active
---
PRJ
cat > "$ALPHA/projects/finished/tasks/task-001.md" <<'TSK'
---
type: Task
title: Fix the broken links
status: done
assignee: cataloguer
---
TSK

echo "== the off switch: absence, on the writer's side =="
SNAP="$ALPHA/SNAPSHOT.json"
OFF_RC=0; OFF_OUT="$( cd "$ALPHA" && bash "$WRITER" 2>&1 )" || OFF_RC=$?
assert "no SNAPSHOT.json -> exits 0"              "$(eq "$OFF_RC" 0)"
assert "no SNAPSHOT.json -> the file is NOT created" "$(yes_if test ! -e "$SNAP")"
assert "…and it says the instance is off the board"  "$(has 'off the board' "$OFF_OUT")"
assert "…and names the way back in"                  "$(has 'touch SNAPSHOT.json' "$OFF_OUT")"
Q_OUT="$( cd "$ALPHA" && bash "$WRITER" --quiet 2>&1 )" || true
assert "--quiet with no snapshot is completely silent" "$(eq "$Q_OUT" "")"
assert "…and still creates nothing"                   "$(yes_if test ! -e "$SNAP")"

echo "== refusals =="
mkdir -p "$ALPHA/SNAPSHOT.json.d" && mv "$ALPHA/SNAPSHOT.json.d" "$ALPHA/SNAPSHOT.json"
DIR_RC=0; DIR_OUT="$( cd "$ALPHA" && bash "$WRITER" 2>&1 )" || DIR_RC=$?
assert "a directory at that path -> exits 2"     "$(eq "$DIR_RC" 2)"
assert "…and says it refuses to overwrite"       "$(has 'refusing to overwrite' "$DIR_OUT")"
assert "…and the directory is still there"       "$(yes_if test -d "$SNAP")"
rmdir "$SNAP"
mkdir -p "$TMP/stranger"
STR_RC=0; STR_OUT="$( cd "$TMP/stranger" && bash "$WRITER" 2>&1 )" || STR_RC=$?
assert "outside an instance root -> exits 2"     "$(eq "$STR_RC" 2)"
assert "…and names what it expected to find"     "$(has 'instance.config.json' "$STR_OUT")"

echo "== a real snapshot, once the switch is on =="
touch "$SNAP"
RUN_OUT="$( cd "$ALPHA" && SNAPSHOT_NOW=2026-08-22T00:00:00Z bash "$WRITER" 2>&1 )"
assert "the run reports what it wrote"     "$(has 'SNAPSHOT.json' "$RUN_OUT")"
assert "…with the project count"           "$(has '3 project(s)' "$RUN_OUT")"
assert "…and the task count"                "$(has '6 task(s)' "$RUN_OUT")"
assert "…and the awaiting count (5 verbs across 3 projects)" "$(has '5 awaiting' "$RUN_OUT")"
assert "the file is non-empty"              "$(yes_if test -s "$SNAP")"
assert "it parses as JSON"                  "$(yes_if python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$SNAP")"
assert "no temp file was left behind"       "$(yes_if sh -c '! ls "$1".tmp.* >/dev/null 2>&1' _ "$SNAP")"
# SNAPSHOT_NOW is the whole reproducibility story: without it the file differs on every
# run and nothing downstream can be diffed.
cp "$SNAP" "$TMP/first.json"
( cd "$ALPHA" && SNAPSHOT_NOW=2026-08-22T00:00:00Z bash "$WRITER" --quiet )
assert "SNAPSHOT_NOW pins generated_at (byte-identical re-run)" "$(yes_if cmp -s "$TMP/first.json" "$SNAP")"

echo "== the field allowlist =="
# The documented set, and nothing else.
#
# This PARSES the JSON rather than grepping it. The previous version matched
# `"[A-Za-z_][A-Za-z0-9_]*":`, which only ever sees identifier-shaped keys — a
# perfectly valid `"source-path"` or `"document body"` was invisible to it, so a
# snapshot could carry a field outside the allowlist while this assertion reported
# green. Since the allowlist is a data-governance boundary rather than a format,
# a check that can be walked around is worse than no check: it certifies the
# boundary while not testing it. Recursing over the parsed object also covers keys
# at any depth, which the flat text scan only did by accident.
ALLOWED=' _schema _sensitivity _carries group generated_at counts projects tasks awaiting slug title description kind status autonomy awaiting_close phase_progress done total phases file order id assignee phase in_flight open_questions prs repo number url '
extra_keys() { # <json file> <allowed> -> the keys present but not allowed
  python3 - "$1" "$2" <<'PYK'
import json, sys
allowed = set(sys.argv[2].split())
def keys(v):
    if isinstance(v, dict):
        for k, child in v.items():
            yield k
            yield from keys(child)
    elif isinstance(v, list):
        for child in v:
            yield from keys(child)
with open(sys.argv[1], encoding="utf-8") as fh:
    print(" ".join(sorted(set(keys(json.load(fh))) - allowed)))
PYK
}
EXTRA="$(extra_keys "$SNAP" "$ALLOWED")"
assert "no key outside the documented set is emitted${EXTRA:+ (saw:$EXTRA)}" "$(eq "$EXTRA" "")"
# …and PROVE that check can actually fail. A non-identifier key is exactly the shape
# the old grep could not see, so it is the shape this fixture plants.
printf '%s\n' '{"group":"g","counts":{"tasks":1},"source-path":"/home/someone/bundle"}' > "$TMP/badkey.json"
BADKEY="$(extra_keys "$TMP/badkey.json" "$ALLOWED")"
assert "a non-identifier key IS caught (the old grep missed it)" "$(eq "$BADKEY" "source-path")"
printf '%s\n' '{"group":"g","projects":[{"slug":"s","document body":"leak"}]}' > "$TMP/badkey2.json"
BADKEY2="$(extra_keys "$TMP/badkey2.json" "$ALLOWED")"
assert "…and one with a space, nested inside a list" "$(eq "$BADKEY2" "document body")"
assert "a task description never reaches the snapshot"   "$(fhasnt "$SECRET_DESC" "$SNAP")"
assert "no document body reaches the snapshot"           "$(fhasnt "$SECRET_BODY" "$SNAP")"
assert "open-question TEXT never reaches the snapshot"    "$(fhasnt "$SECRET_QUESTION" "$SNAP")"
assert "…the COUNT does (2 questions on task-001)"        "$(fhas '"open_questions": 2' "$SNAP")"
assert "a blocker reason never reaches the snapshot"      "$(fhasnt "$SECRET_BLOCKER" "$SNAP")"
assert "…the VERB does (unblock)"                         "$(fhas '"awaiting": "unblock"' "$SNAP")"
assert "authorEmail never reaches the snapshot"           "$(fhasnt "$SECRET_EMAIL" "$SNAP")"
assert "no path outside the bundle reaches the snapshot"  "$(fhasnt "$OUT_OF_BUNDLE" "$SNAP")"
assert "the assignee is a ROLE, not a person"             "$(fhas '"assignee": "software-engineer"' "$SNAP")"
assert "the sensitivity note travels with the file"       "$(fhas 'AS SENSITIVE AS THE TASK DOCUMENTS' "$SNAP")"

echo "== derived state the board reads =="
assert "an in-progress task is in_flight"        "$(yes_if grep -qF '"id": "task-005", "title": "Cache the dependency store", "kind": "build", "status": "in-progress", "assignee": "software-engineer", "phase": "", "in_flight": true' "$SNAP")"
assert "an in-review task is NOT in flight"      "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"]=="task-002"][0]
sys.exit(0 if t["in_flight"] is False and t["awaiting"]=="merge" else 1)' "$SNAP")"
assert "a refined draft awaits approve"          "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"]=="task-004"][0]
sys.exit(0 if t["awaiting"]=="approve" else 1)' "$SNAP")"
assert "the hostile title round-trips exactly"   "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"]=="task-001"][0]
sys.exit(0 if t["title"]==sys.argv[2] else 1)' "$SNAP" "$HOSTILE_TITLE")"
assert "a project with no tasks yields an empty list, not an error" "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="empty"][0]
sys.exit(0 if p["tasks"]==[] and p["phases"]==[] else 1)' "$SNAP")"
assert "all-terminal project proposes a close"   "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p={p["slug"]:p for p in d["projects"]}
sys.exit(0 if p["finished"]["awaiting_close"] and not p["empty"]["awaiting_close"] else 1)' "$SNAP")"
assert "phase progress counts done vs total"     "$(fhas '"phase_progress": {"done": 1, "total": 2}' "$SNAP")"

echo "== the other three instances =="
printf '{ this is not json' > "$BETA/SNAPSHOT.json"
# Hand-written, because the writer will not produce a non-http PR URL — and the board
# is required not to trust that.
cat > "$DELTA/SNAPSHOT.json" <<DELTASNAP
{
  "group": "delta",
  "generated_at": "2026-08-22T00:00:00Z",
  "counts": {"projects": 1, "tasks": 2, "awaiting": 1},
  "projects": [
    {
      "slug": "hostile", "title": "Hostile input", "kind": "build", "status": "active",
      "autonomy": "gated", "awaiting_close": false,
      "phase_progress": {"done": 0, "total": 0}, "phases": [],
      "tasks": [
        {"id": "task-001", "title": "$HOSTILE_TITLE", "kind": "build", "status": "in-review",
         "assignee": "software-engineer", "phase": "", "in_flight": false,
         "awaiting": "merge", "open_questions": 0,
         "prs": [{"repo": "evil/repo", "number": 1, "url": "javascript:alert(document.domain)"},
                 {"repo": "evil/repo", "number": 2, "url": "data:text/html,<script>alert(1)</script>"},
                 {"repo": "acme/monorepo", "number": 3, "url": "https://github.com/acme/monorepo/pull/3"}]},
        {"id": "task-002", "title": "onerror=alert(1) autofocus", "kind": "build",
         "status": "made-up-status", "assignee": "software-engineer", "phase": "",
         "in_flight": false, "awaiting": "", "open_questions": 0, "prs": []}
      ]
    }
  ]
}
DELTASNAP
assert "gamma has no snapshot (the off-switch fixture)" "$(yes_if test ! -e "$GAMMA/SNAPSHOT.json")"

echo "== the board renders, and a broken instance cannot blank it =="
HTML="$TMP/board.html"
B_RC=0; B_ERR="$( cd "$TMP" && bash "$BOARD" --out "$HTML" "$ALPHA" "$BETA" "$GAMMA" "$DELTA" 2>&1 )" || B_RC=$?
assert "exits 0 with a malformed snapshot in the list" "$(eq "$B_RC" 0)"
assert "the run counts the unreadable snapshot"    "$(has '1 unreadable snapshot(s)' "$B_ERR")"
assert "…and says on stderr which instance is off the board" "$(has 'no SNAPSHOT.json (off the board)' "$B_ERR")"
assert "a malformed snapshot becomes a visible note" "$(fhas 'Unreadable snapshot' "$HTML")"
assert "…naming the instance by directory NAME"     "$(fhas '_ai-bridge-beta/SNAPSHOT.json' "$HTML")"
assert "…and not by its path"                      "$(fhasnt '/_ai-bridge-beta' "$HTML")"
assert "…and telling the human how to fix it"       "$(fhas 'write-snapshot.sh' "$HTML")"
assert "alpha is still rendered beside the broken one" "$(fhas 'CI hardening' "$HTML")"
assert "delta is still rendered too"                "$(fhas 'Hostile input' "$HTML")"
assert "an instance with no snapshot is absent entirely" "$(fhasnt '_ai-bridge-gamma' "$HTML")"
assert "…including its group name"                  "$(fhasnt '>gamma ' "$HTML")"
assert "a project with no tasks renders empty, not broken" "$(fhas 'No tasks yet.' "$HTML")"
assert "an unknown status still gets a column"      "$(fhas 'made-up-status' "$HTML")"
assert "the close proposal is shown, never taken"   "$(fhas 'close?' "$HTML")"
assert "no filesystem path reaches the page"        "$(fhasnt "$TMP" "$HTML")"
# Belt and braces, because the check above depends on how the fixture path is spelled:
# an instance is named by its DIRECTORY NAME, so the name must never appear with a
# leading slash (i.e. as the tail of a path) anywhere on the page.
assert "…an instance is identified by name, never by path" "$(fhasnt '/_ai-bridge-alpha' "$HTML")"
assert "…and the name itself is still there"               "$(fhas '_ai-bridge-alpha' "$HTML")"

echo "== untrusted text at an HTML sink =="
RAW_HITS="$(grep -oF -- '<script>alert(1)</script>' "$HTML" | grep -c . || true)"
assert "ZERO raw occurrences of the metacharacter title (saw $RAW_HITS)" "$(eq "$RAW_HITS" 0)"
assert "…and it is present in escaped form"         "$(fhas "$HOSTILE_ESCAPED" "$HTML")"
assert "no <script> tag anywhere in the page"       "$(fhasnt '<script' "$HTML")"
assert "no raw <b> from a title either"             "$(fhasnt '<b>bold</b>' "$HTML")"
assert "an event-handler-shaped title stays text"   "$(fhasnt ' onerror=' "$HTML")"
assert "a javascript: URL is never an href"         "$(fhasnt 'href="javascript:' "$HTML")"
assert "a data: URL is never an href"               "$(fhasnt 'href="data:' "$HTML")"
assert "…the withheld link is inert text instead"   "$(fhas 'link withheld: not http/https' "$HTML")"
assert "…and the http PR link beside it still works" "$(fhas 'href="https://github.com/acme/monorepo/pull/3"' "$HTML")"
# Secrets must not reappear via the board even though the snapshot is clean — the
# renderer reads only the snapshot, and this pins that.
for s in "$SECRET_DESC" "$SECRET_BODY" "$SECRET_QUESTION" "$SECRET_BLOCKER" "$SECRET_EMAIL"; do
  assert "the page carries no '$s'" "$(fhasnt "$s" "$HTML")"
done

echo "== zero external requests =="
BAD_HREF=""
while IFS= read -r h; do
  case "$h" in
    http://*|https://*) case "$h" in *"/pull/"*) ;; *) BAD_HREF="$BAD_HREF $h" ;; esac ;;
  esac
done < <(grep -oE 'href="[^"]*"' "$HTML" | sed 's/^href="//; s/"$//')
assert "every http(s) href is a PR link${BAD_HREF:+ (saw:$BAD_HREF)}" "$(eq "$BAD_HREF" "")"
assert "no src= attribute at all"       "$(fhasnt 'src=' "$HTML")"
assert "no @import in the stylesheet"   "$(fhasnt '@import' "$HTML")"
# EVERY url(), not just an absolute one: `url(assets/icon.svg)` is a fetch too, and
# the header promises no CSS resource reference at all. The old pattern also used
# `\s`, which is a GNU extension rather than POSIX ERE — so it was a portability trap
# on top of being too narrow.
no_css_url() { # <html file> -> 0 when no <style> block contains url(
  python3 - "$1" <<'PYU'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
blocks = re.findall(r"<style\b[^>]*>(.*?)</style>", html, re.I | re.S)
sys.exit(0 if all(not re.search(r"url\s*\(", b, re.I) for b in blocks) else 1)
PYU
}
assert "no url() fetch in the stylesheet" "$(yes_if no_css_url "$HTML")"
# Prove the strengthened check fails on a RELATIVE url(), which the old one passed.
printf '%s\n' '<style>.a{background:url(assets/icon.svg)}</style>' > "$TMP/relurl.html"
assert "…and a relative url() is now rejected" "$(eq "$(yes_if no_css_url "$TMP/relurl.html")" 1)"
printf '%s\n' '<style>.a{color:red}</style><p>url(not-in-css)</p>' > "$TMP/txturl.html"
assert "…while url( outside a <style> block is not a false alarm" "$(yes_if no_css_url "$TMP/txturl.html")"
assert "no <link rel=stylesheet>"       "$(fhasnt '<link' "$HTML")"
assert "no <iframe>"                    "$(fhasnt '<iframe' "$HTML")"

echo "== output shape =="
assert "the default output is an Artifact page body (no doctype)" "$(fhasnt '<!doctype' "$HTML")"
assert "…and no <body> tag"              "$(fhasnt '<body' "$HTML")"
assert "…but it does carry a <title>"    "$(fhas '<title>Bridge Board</title>' "$HTML")"
SA="$TMP/standalone.html"
( cd "$TMP" && bash "$BOARD" --standalone --out "$SA" "$ALPHA" ) >/dev/null 2>&1
assert "--standalone opens with a doctype" "$(yes_if sh -c 'head -1 "$1" | grep -qF "<!doctype html>"' _ "$SA")"
assert "…and the content sits in <body>, not <head>" "$(yes_if python3 -c '
import sys,re
t=open(sys.argv[1]).read()
head=t[t.index("<head>"):t.index("</head>")]
body=t[t.index("<body>"):t.index("</body>")]
sys.exit(0 if "<style>" in head and "Bridge Board</h1>" in body and "<h1>" not in head else 1)' "$SA")"
assert "…with exactly one <body> element" "$(eq "$(grep -cF '<body>' "$SA")" 1)"

# The tabs are CSS-only, so their whole behaviour is the pairing between a radio input,
# a panel with the matching id, and a generated rule joining them. Nothing else on the
# page can reveal a drift there: a mismatch renders a board where no panel is ever
# displayed, which looks like "no projects" rather than like a bug.
# Two, not four: beta is malformed and gamma has no snapshot, so neither is an instance
# on the board — which is the same fact the absence assertions above assert, read off
# the tab strip.
assert "one radio input per RENDERED instance (2 of 4)" "$(eq "$(grep -cE 'input type="radio" name="board-instance" id="tab-[0-9]+"' "$HTML")" 2)"
assert "exactly one of them is checked" "$(eq "$(grep -cE 'id="tab-[0-9]+" checked' "$HTML")" 1)"
assert "each tab id has a matching panel" "$(yes_if python3 -c '
import re,sys
t=open(sys.argv[1]).read()
tabs={m for m in re.findall(r"id=\"tab-(\d+)\"", t)}
panels={m for m in re.findall(r"id=\"panel-(\d+)\"", t)}
rules={m for m in re.findall(r"#tab-(\d+):checked ~ #panel-\1\{display:block\}", t)}
sys.exit(0 if tabs and tabs==panels==rules else 1)' "$HTML")"
assert "each label points at its own tab"  "$(yes_if python3 -c '
import re,sys
t=open(sys.argv[1]).read()
labels={m for m in re.findall(r"<label for=\"tab-(\d+)\"", t)}
tabs={m for m in re.findall(r"id=\"tab-(\d+)\"", t)}
sys.exit(0 if labels==tabs else 1)' "$HTML")"

echo "== discovery is explicit, never a glob =="
D1="$( cd "$ALPHA" && bash "$BOARD" --out "$TMP/d1.html" 2>&1 )"
assert "no args, no boardInstances -> just this instance" "$(has '1 instance(s)' "$D1")"
assert "…and the page says where the list came from"      "$(fhas 'this instance' "$TMP/d1.html")"
python3 - "$ALPHA/instance.config.json" "$DELTA" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["boardInstances"]=[".",sys.argv[2]]
json.dump(d,open(p,"w"),indent=2)
PY
D2="$( cd "$ALPHA" && bash "$BOARD" --out "$TMP/d2.html" 2>&1 )"
assert "boardInstances is used when no dirs are named"   "$(has '2 instance(s)' "$D2")"
assert "…and the page says the list came from that key"  "$(fhas 'boardInstances' "$TMP/d2.html")"
assert "named dirs override the config"                  "$(has '1 instance(s)' "$( cd "$ALPHA" && bash "$BOARD" --out "$TMP/d3.html" "$DELTA" 2>&1 )")"
printf 'not json at all' > "$TMP/badcfg-cfg"
cp "$ALPHA/instance.config.json" "$TMP/goodcfg" && cp "$TMP/badcfg-cfg" "$ALPHA/instance.config.json"
D4="$( cd "$ALPHA" && bash "$BOARD" --out "$TMP/d4.html" 2>&1 )"
assert "an unreadable config falls back to this instance" "$(has '1 instance(s)' "$D4")"
assert "…and says so on stderr"                           "$(has 'unreadable' "$D4")"
# A config that PARSES but whose top level is not an object. This is a different
# failure from "not JSON at all" above: json.loads succeeds, so the except clause is
# never reached, and a bare .get() on the result raises AttributeError — which was
# NOT in the caught tuple, so the run ended in a traceback instead of the documented
# fallback. One case per JSON top-level type that has no .get.
for shape in '["a","b"]' '"just-a-string"' '5' 'null' 'true'; do
  printf '%s\n' "$shape" > "$ALPHA/instance.config.json"
  RC=0; OUT="$( cd "$ALPHA" && bash "$BOARD" --out "$TMP/dshape.html" 2>&1 )" || RC=$?
  assert "a config whose top level is $shape falls back, exit 0" "$(eq "$RC" 0)"
  assert "…rendering just this instance"   "$(has '1 instance(s)' "$OUT")"
  assert "…with no Python traceback"       "$(hasnt 'Traceback' "$OUT")"
done
cp "$TMP/goodcfg" "$ALPHA/instance.config.json"
NOSUCH="$( cd "$TMP" && bash "$BOARD" --out "$TMP/d5.html" "$TMP/no-such-instance" 2>&1 )"
assert "a named directory that does not exist is skipped, not fatal" "$(has 'no such directory' "$NOSUCH")"
assert "…and the empty board explains how an instance joins" "$(fhas 'touch SNAPSHOT.json' "$TMP/d5.html")"

echo "== a drifted snapshot cannot blank the board =="
# THE MAJOR CASE. These snapshots are syntactically valid JSON, so the malformed-file
# path above never sees them — the wrong TYPES surface later, at int() and at a sort
# comparison. A bare int("many") raises ValueError before a single byte of output is
# written, so one drifted instance took the whole board down with it, including every
# healthy instance on the same page. That directly contradicts the header's promise
# that a malformed snapshot is a visible card rather than a crash.
#
# Each case therefore asserts BOTH halves: this instance survives, AND the healthy
# instance beside it still renders. A fix that swallows the drift by dropping every
# instance would pass the first half alone.
DRIFT="$TMP/group/_ai-bridge-drift"
mkdir -p "$DRIFT"
drift_case() { # <label> <snapshot json>
  printf '%s\n' "$2" > "$DRIFT/SNAPSHOT.json"
  local rc=0 out
  # rm FIRST. Without this the file survives from the previous case, and both the
  # "an output file is written" and "healthy instance still renders" assertions pass
  # by reading STALE output — green while the run they claim to describe crashed.
  rm -f "$TMP/drift.html"
  out="$( cd "$TMP" && bash "$BOARD" --out "$TMP/drift.html" "$ALPHA" "$DRIFT" 2>&1 )" || rc=$?
  assert "$1: exits 0"                       "$(eq "$rc" 0)"
  assert "$1: an output file is written"      "$(yes_if test -s "$TMP/drift.html")"
  assert "$1: no traceback"                   "$(hasnt 'Traceback' "$out")"
  assert "$1: the healthy instance still renders" "$(fhas 'CI hardening' "$TMP/drift.html")"
}
drift_case "a non-numeric task count" \
  '{"group":"drift","counts":{"tasks":"many","projects":1,"awaiting":0},"projects":[]}'
drift_case "a non-numeric phase total" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","phase_progress":{"total":"two","done":"one"},"phases":[],"tasks":[]}]}'
drift_case "a non-numeric phase order" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","phase_progress":{"total":2,"done":1},"phases":[{"order":"first","title":"A","status":"active"},{"order":2,"title":"B","status":"done"}],"tasks":[]}]}'
# A non-string group is the TypeError variant: it survives a truthiness test, so it
# reached the awaiting sort still an int and compared int with str there. It needs an
# awaiting item to reach that sort at all, which is why this fixture carries one.
drift_case "a non-string group" \
  '{"group":5,"counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":[{"id":"task-001","title":"T","status":"blocked","awaiting":"unblock","open_questions":0,"prs":[]}]}]}'
# ANCHORED to the tab-label markup on purpose. A bare `fhas 5` passes on any page:
# the stylesheet alone contains "5" 39 times, so it would report green even if the
# coercion dropped the group entirely. The assertion has to name where it appears.
assert "…and the non-string group is rendered as a tab label" \
  "$(yes_if grep -qE '<label for="tab-[0-9]+"[^>]*>5 ' "$TMP/drift.html")"
rm -rf "$DRIFT"

echo "== installer: on by first stamp, off by deletion, forever =="
INST="$TMP/group/_ai-bridge-stamped"
mkdir -p "$INST"
( cd "$INST" && git init -q . ) 2>/dev/null || true
bash "$BRIDGE_INSTALL" "$INST" >"$TMP/i1.out" 2>&1
assert "the first stamp creates SNAPSHOT.json"  "$(yes_if test -f "$INST/SNAPSHOT.json")"
assert "…and says the instance is on the board" "$(fhas 'seed  SNAPSHOT.json' "$TMP/i1.out")"
assert "the seeded snapshot is VALID JSON (no note on a brand-new instance)" \
  "$(yes_if python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$INST/SNAPSHOT.json")"
FRESH="$( cd "$TMP" && bash "$BOARD" --out "$TMP/fresh.html" "$INST" 2>&1 )"
assert "…so a fresh instance renders with no unreadable note" "$(has '0 unreadable snapshot(s)' "$FRESH")"
assert "the seeded .gitignore ignores the snapshot" "$(fhas 'SNAPSHOT.json' "$INST/.gitignore")"
assert "…and the derived board HTML"                "$(fhas 'board.html' "$INST/.gitignore")"
printf 'LOCAL SNAPSHOT CONTENT\n' > "$INST/SNAPSHOT.json"
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
assert "a refresh never clobbers an existing snapshot" "$(fhas 'LOCAL SNAPSHOT CONTENT' "$INST/SNAPSHOT.json")"
rm "$INST/SNAPSHOT.json"
bash "$BRIDGE_INSTALL" "$INST" >"$TMP/i2.out" 2>&1
assert "deletion survives an installer re-run (FIRST_STAMP)" "$(yes_if test ! -e "$INST/SNAPSHOT.json")"
assert "…and the re-run says it is absent by choice" "$(fhas "skip  SNAPSHOT.json (absent by choice" "$TMP/i2.out")"
mkdir -p "$INST/projects/x/tasks"
cat > "$INST/projects/x/project.md" <<'PRJ'
---
type: Project
title: After the rm
kind: build
status: active
---
PRJ
( cd "$INST" && bash "$TPL/symlink/scripts/write-snapshot.sh" --quiet ) || true
assert "the writer never resurrects a deleted snapshot" "$(yes_if test ! -e "$INST/SNAPSHOT.json")"
OFFBOARD="$( cd "$TMP" && bash "$BOARD" --out "$TMP/off.html" "$INST" 2>&1 )"
assert "…and that instance is off the board"           "$(has '0 instance(s)' "$OFFBOARD")"
assert "…with nothing of its content on the page"      "$(fhasnt 'After the rm' "$TMP/off.html")"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
