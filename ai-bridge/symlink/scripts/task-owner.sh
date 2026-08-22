#!/usr/bin/env bash
#
# task-owner.sh — resolve WHOSE a task is, so an instance shared by two humans
# dispatches only its own human's work.
#
#   Usage: scripts/task-owner.sh <task-path>     # verdict for one task
#          scripts/task-owner.sh --self          # print this clone's human, informationally
#
# Exit codes — 0 is the ONLY clearance; every other code is a refusal:
#
#   0  this task is this clone's human's — the loop may dispatch it
#   1  it is someone else's — the loop must NOT dispatch it (their loop will)
#   2  cannot answer: usage error, not an instance root, unreadable/malformed
#      frontmatter, or a configured value that is not a GitHub username
#
# RESOLUTION ORDER (the same three steps every doc naming `owner` must state):
#
#   1. the task's own `owner:`            (projects/<slug>/tasks/<id>.md)
#   2. else the owning project's `owner:` (projects/<slug>/project.md)
#   3. else this clone's own human        (`ownerGithubUser`, below)
#
# So **no `owner:` anywhere means every task is this clone's** — which is exactly
# the behaviour of a single-human instance, and why this is a no-op for one.
# Absence is never an error at any of the three steps.
#
# THIS CLONE'S HUMAN comes from `ownerGithubUser`, read from
# `instance.config.local.json` first (gitignored, per-machine) and then from
# `instance.config.json` (tracked, shared). **If the key is absent from both, this
# clone has no configured human** — unowned tasks still clear (step 3 above resolves
# to "nobody in particular, so mine"), and a task naming an owner refuses, because
# an unconfigured clone cannot prove the name is its own. That is the fail-closed
# direction: the cost of refusing is a task waiting one tick, the cost of clearing
# is two loops dispatching the same task twice.
#
# The value is a **GitHub username**, never an email — public, stable, and it keeps
# addresses out of tracked documents, which is also the standing no-customer-PII
# rule applied to identity. Comparison is case-insensitive, as GitHub's own is.
#
# WHAT THIS GATES, AND WHAT IT DOES NOT.
# It gates **dispatch** — the loop handing work to a role agent. It does NOT gate
# promotion: a shared board means either human may promote any task `draft → ready`,
# whoever owns it. Gating promotion would be gating the wrong verb, and it is the
# natural mistake to make here.
#
# IT IS NOT A LOCK. Git is not a lock, and neither is this. It stops two loops
# double-dispatching the SAME task; it does not stop two loops acting in the same
# tick window on tasks they each own, or two humans pushing the control panel at
# once. Those stay ordinary git conflicts, resolved the ordinary way.
#
# GENERIC TEMPLATE FILE — symlinked from the `ai-bridge` template; do not edit per
# instance. It reads no org, repo or path literal.
#
# Verified by ai-bridge/tests/task-owner.test.sh.
set -euo pipefail

CONFIG="instance.config.json"
LOCAL_CONFIG="instance.config.local.json"

usage() {
  echo "Usage: $(basename "$0") <task-path>" >&2
  echo "       $(basename "$0") --self" >&2
  exit 2
}

mode="task"
target=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --self) mode="self"; shift ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) [ -z "$target" ] || { echo "error: unexpected argument '$1'" >&2; usage; }
       target="$1"; shift ;;
  esac
done
[ "$mode" = "self" ] || [ -n "$target" ] || usage

[ -f SCHEMA.md ] && [ -f "$CONFIG" ] || {
  echo "error: run from a control-panel instance root (SCHEMA.md + $CONFIG)." >&2
  exit 2
}

# Portable extraction of a JSON string value (no jq dependency), matching the
# parse commit-as.sh uses for authorEmail. A missing file is silence, not an error.
json_string() { # <file> <key>
  [ -f "$1" ] || return 0
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n1
}

# A GitHub username: 1-39 of [A-Za-z0-9-]. Anything else is not a username, and a
# value we cannot read is not a value we may compare against — refuse (exit 2)
# rather than guess, or a typo would silently make every owned task "someone
# else's" and quietly stall the board.
valid_user() { printf '%s' "$1" | grep -qE '^[A-Za-z0-9][A-Za-z0-9-]{0,38}$'; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

self="$(json_string "$LOCAL_CONFIG" ownerGithubUser)"
self_src="$LOCAL_CONFIG"
if [ -z "$self" ]; then
  self="$(json_string "$CONFIG" ownerGithubUser)"
  self_src="$CONFIG"
fi
if [ -n "$self" ] && ! valid_user "$self"; then
  echo "error: \"ownerGithubUser\" in $self_src is not a GitHub username: '$self'" >&2
  echo "       Expected 1-39 characters of [A-Za-z0-9-]. Refusing rather than" >&2
  echo "       comparing against a value we cannot read." >&2
  exit 2
fi

if [ "$mode" = "self" ]; then
  if [ -n "$self" ]; then
    echo "self: $self (from $self_src)"
  else
    echo "self: <none> (no \"ownerGithubUser\" in $LOCAL_CONFIG or $CONFIG)"
  fi
  exit 0
fi

# Accept an absolute path as well as one relative to the instance root — the loop
# passes agents absolute task paths. Both sides are canonicalised with `pwd -P`
# before the strip, because a plain string comparison fails wherever a prefix is
# symlinked (on macOS `/var` is a link to `/private/var`, which is exactly where a
# test fixture lands): the path would stay absolute, the `projects/<slug>/` match
# would miss, and the project fallback would silently never run — a task would read
# as unowned and clear. "$root" is also QUOTED inside the prefix operator: unquoted
# it is matched as a GLOB, so an instance path containing [ ] * or ? strips nothing,
# the same SC2295 trap install.sh had.
tdir="$(dirname "$target")"
[ -d "$tdir" ] || {
  echo "error: no such task document: $target" >&2
  exit 2
}
abs="$(cd "$tdir" && pwd -P)/$(basename "$target")"
root="$(pwd -P)"
rel="${abs#"$root"/}"
[ -f "$rel" ] || {
  echo "error: no such task document: $target" >&2
  exit 2
}

# Print the frontmatter block. Exit 3 when the file does not open with `---`, exit 4
# when it opens but never closes. Same reader as validate-bundle.sh, for the same
# reason: an unterminated block would otherwise return the whole file, and an
# `owner:` line in the BODY — prose, a note, a quoted example — would be read as
# frontmatter.
fm_block() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

# Only the FIRST `owner:` counts. A document with the key repeated would otherwise
# be judged from the LATER value — the same bug push-state.sh had with `status:`.
# An empty value (`owner:` with nothing after it) reads as absent, so a scaffold
# carrying the bare key still falls through to the project. awk, not `sed | head`:
# the reader consumes its whole input, so no early-exiting stage can SIGPIPE the
# one before it under `pipefail`.
owner_from() {
  printf '%s\n' "$1" | awk '
    !got && /^owner:[[:space:]]*/ {
      v = $0
      sub(/^owner:[[:space:]]*/, "", v)
      sub(/[[:space:]]*#.*$/, "", v)
      sub(/^["'"'"']/, "", v); sub(/["'"'"']$/, "", v)
      sub(/[[:space:]]+$/, "", v)
      print v; got = 1
    }'
}

# Sets $owner. A plain function, NOT a command substitution: a refusal here has to
# stop the script, and `exit 2` inside `$(...)` only leaves the subshell.
owner=""
resolve_owner() { # <file> <what-it-is>
  local rc=0 fm
  fm="$(fm_block "$1")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "error: $1 has no readable YAML frontmatter, so the $2 owner cannot be" >&2
    echo "       resolved — refusing rather than assuming it is unowned." >&2
    exit 2
  fi
  owner="$(owner_from "$fm")"
}

resolve_owner "$rel" task
owner_src="$rel"

# Fall back to the owning project. A path that is not projects/<slug>/... has no
# project to ask, which is not an error: it just leaves the task unowned.
if [ -z "$owner" ]; then
  slug="$(printf '%s\n' "$rel" | sed -n 's#^projects/\([^/][^/]*\)/.*#\1#p')"
  if [ -n "$slug" ] && [ -f "projects/$slug/project.md" ]; then
    resolve_owner "projects/$slug/project.md" project
    owner_src="projects/$slug/project.md"
  fi
fi

if [ -z "$owner" ]; then
  echo "ok: $rel names no owner — this clone's work${self:+ (self: $self)}"
  exit 0
fi

if ! valid_user "$owner"; then
  echo "error: owner '$owner' in $owner_src is not a GitHub username (1-39 of" >&2
  echo "       [A-Za-z0-9-]). Refusing rather than comparing against a value we" >&2
  echo "       cannot read." >&2
  exit 2
fi

if [ -z "$self" ]; then
  echo "refuse: $rel is owned by '$owner', but this clone has no \"ownerGithubUser\"" >&2
  echo "        in $LOCAL_CONFIG or $CONFIG, so it cannot tell whether that is you." >&2
  echo "        Set the key (per-machine, in $LOCAL_CONFIG) and re-run." >&2
  exit 1
fi

if [ "$(lower "$owner")" = "$(lower "$self")" ]; then
  echo "ok: $rel is owned by '$owner' — this clone's human (from $owner_src)"
  exit 0
fi

echo "refuse: $rel is owned by '$owner', not '$self' (from $owner_src)." >&2
echo "        Their loop dispatches it. Report it; do not dispatch it here." >&2
exit 1
