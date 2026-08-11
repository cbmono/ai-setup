#!/usr/bin/env bash
#
# commit-as.sh — commit to THIS control-panel instance repo under a per-agent
# author identity, for provenance in the autonomous PM loop.
#
#   Usage: scripts/commit-as.sh <role> "<commit message>" [git args...] -- <path>...
#          scripts/commit-as.sh <role> "<commit message>" --all-staged [git args...]
#
# The author NAME is the role; the author EMAIL is shared so the host (e.g.
# GitHub) still links commits to the human's account, while `git log --format=%an`
# / `git shortlog -sn` separate work per agent.
#
# NAME THE PATHS YOU ARE COMMITTING, after a `--`. Several agents run
# concurrently against ONE working tree, so the index is shared state: a role that
# commits "whatever is staged" silently absorbs whatever a sibling agent staged a
# second earlier, and that sibling's work lands under the wrong author. This has
# happened repeatedly in practice. Passing paths makes git commit only those,
# leaving everyone else's staged changes staged and intact.
#
# So for every role except `human`, one of the two forms above is REQUIRED:
#   - `-- <path>...`  commit exactly these paths (strongly preferred), or
#   - `--all-staged`  commit the whole index, an explicit "I checked, it's all mine".
# `human` is exempt: a person committing interactively can see the index.
# Never `git add -A` in a shared instance — stage by explicit path.
#
# GENERIC TEMPLATE FILE — symlinked from the `ai-bridge` template; do not
# edit per instance. The shared author email is resolved, in order, from:
#   1. $CONTROL_PLANE_AUTHOR_EMAIL          (explicit override)
#   2. "authorEmail" in <repo-root>/instance.config.json
#   3. `git config user.email`
#
# SCOPE: this control-panel instance repo ONLY. Target product repos may forbid
# AI attribution — never use this there; commit with the repo's normal identity.
set -euo pipefail

VALID_ROLES=(project-manager software-engineer devops-engineer qa-reviewer cataloguer human)

usage() {
  echo "Usage: $(basename "$0") <role> \"<commit message>\" [git args...] -- <path>..." >&2
  echo "       $(basename "$0") <role> \"<commit message>\" --all-staged [git args...]" >&2
  echo "Roles: ${VALID_ROLES[*]}" >&2
  exit 2
}

[ "$#" -ge 2 ] || usage
role="$1"; shift
message="$1"; shift

case " ${VALID_ROLES[*]} " in
  *" $role "*) ;;
  *) echo "error: unknown role '$role'" >&2; usage ;;
esac

[ -n "$message" ] || { echo "error: empty commit message" >&2; usage; }

# Split the remaining args into: git passthrough args, an --all-staged opt-out,
# and the pathspecs after `--`. Everything after the first `--` is a path, which
# is git's own convention, so callers need no new mental model.
git_args=()
paths=()
all_staged=0
seen_dashdash=0
for arg in "$@"; do
  if [ "$seen_dashdash" -eq 1 ]; then
    paths+=("$arg")
  elif [ "$arg" = "--" ]; then
    seen_dashdash=1
  elif [ "$arg" = "--all-staged" ]; then
    all_staged=1
  else
    git_args+=("$arg")
  fi
done

if [ "$seen_dashdash" -eq 1 ] && [ "${#paths[@]}" -eq 0 ]; then
  echo "error: '--' given with no paths after it" >&2
  usage
fi

if [ "$all_staged" -eq 1 ] && [ "${#paths[@]}" -gt 0 ]; then
  echo "error: pass either --all-staged or '-- <path>...', not both" >&2
  usage
fi

repo_root="$(git rev-parse --show-toplevel)"

# Resolve the shared author email (see header).
config_email=""
config_file="$repo_root/instance.config.json"
if [ -f "$config_file" ]; then
  # Portable extraction of the JSON string value for "authorEmail" (no jq dependency).
  config_email="$(sed -n 's/.*"authorEmail"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config_file" | head -n1)"
fi
AUTHOR_EMAIL="${CONTROL_PLANE_AUTHOR_EMAIL:-${config_email:-$(git config user.email || true)}}"
[ -n "$AUTHOR_EMAIL" ] || {
  echo "error: no author email — set CONTROL_PLANE_AUTHOR_EMAIL, add \"authorEmail\" to" >&2
  echo "       instance.config.json, or run: git config user.email \"...\"" >&2
  exit 2
}

# Shared-index guard: an agent must say WHAT it is committing.
#
# Instances are worked by several concurrent agents against one clone, so the git
# index is shared mutable state. `git add -A` (or any commit of "whatever is
# staged") absorbs a sibling agent's in-progress files and commits them under the
# wrong author — silently, since the result looks like a normal commit. The fix is
# to commit pathspecs: `git commit -- <paths>` touches only those and leaves the
# rest of the index alone.
#
# `human` is exempt (a person can inspect the index). Every other role must pass
# `-- <path>...` or explicitly opt out with `--all-staged`.
if [ "$role" != "human" ] && [ "${#paths[@]}" -eq 0 ] && [ "$all_staged" -eq 0 ]; then
  if ! staged_all="$(git diff --cached --name-only)"; then
    echo "error: could not list staged files (git diff failed) — refusing to commit" >&2
    exit 3
  fi
  echo "error: role '$role' must name the paths it is committing." >&2
  echo "       Several agents share this working tree, so committing the whole index" >&2
  echo "       can absorb another agent's staged files under your authorship." >&2
  echo >&2
  if [ -n "$staged_all" ]; then
    echo "       Currently staged:" >&2
    # Read line by line: paths may contain spaces, so word-splitting would lie
    # about which files are in the index.
    while IFS= read -r staged_entry; do
      [ -n "$staged_entry" ] || continue
      printf '         %s\n' "$staged_entry" >&2
    done <<EOF
$staged_all
EOF
    echo >&2
  fi
  echo "       Commit only your own paths:" >&2
  echo "         $(basename "$0") $role \"$message\" -- <path>..." >&2
  echo "       Or, if you have checked that the entire index is yours:" >&2
  echo "         $(basename "$0") $role \"$message\" --all-staged" >&2
  exit 4
fi

# Two-human-authority guard (SCHEMA.md): draft→ready is the human's gate.
#
# A project may DELEGATE that gate to the loop via `autonomy:` in its project.md —
# but only where the capability exists at all, which is what AUTONOMY.md at the
# repo root is (see "Delegated authority" in SCHEMA.md). No AUTONOMY.md means no
# modes exist, so every `autonomy` value is inert and every agent-role promotion
# is a violation. Delegation also applies ONLY to `kind: build` tasks, because
# SCHEMA.md keeps research human-driven in every mode. So this guard is decided
# PER TASK from three inputs: the capability file's presence, the owning
# project's autonomy, and the task's own kind — rather than blocking every
# agent-role `status: ready` unconditionally, which contradicted the autonomy
# field and left fully-refined build drafts stranded at `draft`.
#
# Fails CLOSED: anything not clearly (capability present AND autonomy delegated
# AND kind build) is refused; an absent or unparseable field reads as `gated` /
# `unset`. It gates on delegation being POSSIBLE, not on which mode delegates
# what — that distinction lives in AUTONOMY.md, which is authoritative.
if [ "$role" != "human" ]; then
  delegation_possible=0
  [ -f "$repo_root/AUTONOMY.md" ] && delegation_possible=1
  violations=""
  # Enumerate staged files under projects/ ONCE. Fail CLOSED if git itself errors
  # (corrupt index, disk error): refuse rather than proceed with an empty list, which
  # would let a promotion through unchecked — the one spot that would otherwise fail open.
  # When pathspecs are given, judge only what this commit will actually contain —
  # a sibling agent's staged promotion is not this role's to answer for (and its
  # own commit gets checked when it runs). Let git do the pathspec matching, then
  # keep the `projects/` entries: same set the commit will include, no more.
  if [ "${#paths[@]}" -gt 0 ]; then
    if ! staged_in_paths="$(git diff --cached --name-only -- "${paths[@]}")"; then
      echo "error: could not list staged files (git diff failed) — refusing to commit as" >&2
      echo "       role '$role' (fail closed). Fix the repo state and retry." >&2
      exit 3
    fi
    staged_list=""
    while IFS= read -r candidate; do
      case "$candidate" in
        projects/*) staged_list="${staged_list}${candidate}
" ;;
      esac
    done <<EOF
$staged_in_paths
EOF
  elif ! staged_list="$(git diff --cached --name-only -- projects)"; then
    echo "error: could not list staged files (git diff failed) — refusing to commit as" >&2
    echo "       role '$role' (fail closed). Fix the repo state and retry." >&2
    exit 3
  fi
  # Here-doc (not a pipe) so the loop body runs in THIS shell and $violations survives.
  while IFS= read -r staged_file; do
    [ -n "$staged_file" ] || continue

    # Only files whose staged diff ADDS a `status: ready` line.
    if ! git diff --cached -U0 -- "$staged_file" \
         | grep -qiE '^\+status:[[:space:]]*ready[[:space:]]*$'; then
      continue
    fi

    # Owning project slug from projects/<slug>/...
    slug="$(printf '%s\n' "$staged_file" | sed -n 's#^projects/\([^/][^/]*\)/.*#\1#p')"

    # Read autonomy from the STAGED blob (index), not the working tree — same source as
    # `kind` below, so the check is consistent with exactly what's being committed (no
    # working-tree/staged TOCTOU). Missing/unparseable → stays `gated` (fail closed).
    autonomy="gated"
    if [ -n "$slug" ]; then
      parsed="$(git show ":projects/$slug/project.md" 2>/dev/null \
                | sed -n 's/^autonomy:[[:space:]]*\([A-Za-z][A-Za-z-]*\)[[:space:]]*$/\1/p' | head -n1)"
      [ -n "$parsed" ] && autonomy="$parsed"
    fi

    # Task kind read from the STAGED blob — what is actually being committed.
    kind="$(git show ":$staged_file" 2>/dev/null \
            | sed -n 's/^kind:[[:space:]]*\([A-Za-z][A-Za-z-]*\)[[:space:]]*$/\1/p' | head -n1)"
    [ -n "$kind" ] || kind="unset"

    if [ "$delegation_possible" -eq 1 ] && [ "$autonomy" != "gated" ] && [ "$kind" = "build" ]; then
      continue
    fi

    violations="${violations}  - ${staged_file} (project '${slug:-?}': autonomy=${autonomy}, kind=${kind}$([ "$delegation_possible" -eq 1 ] || printf ', no AUTONOMY.md'))
"
  done <<EOF
$staged_list
EOF

  if [ -n "$violations" ]; then
    echo "error: role '$role' may not promote these tasks to 'ready':" >&2
    printf '%s' "$violations" >&2
    echo "       draft→ready is the human's authority (SCHEMA.md). The loop may promote a task" >&2
    echo "       only where AUTONOMY.md exists (no file = no delegated modes), the owning" >&2
    echo "       project's 'autonomy' is not 'gated', AND the task is 'kind: build'" >&2
    echo "       (research stays human-driven). If the human approved it, commit as 'human'." >&2
    exit 3
  fi
fi

# 'human' commits under the person's configured git name; agents under the role.
if [ "$role" = "human" ]; then
  author_name="$(git config user.name)"
  [ -n "$author_name" ] || {
    echo "error: role 'human' needs git user.name set (git config user.name \"...\")" >&2
    exit 2
  }
else
  author_name="$role"
fi

# Pathspecs (when given) go last, after `--`, so git commits exactly those and
# leaves any other staged change in the index for its own author to commit.
if [ "${#paths[@]}" -gt 0 ]; then
  exec git \
    -c "user.name=$author_name" \
    -c "user.email=$AUTHOR_EMAIL" \
    commit --author="$author_name <$AUTHOR_EMAIL>" -m "$message" \
    ${git_args[@]+"${git_args[@]}"} -- "${paths[@]}"
else
  exec git \
    -c "user.name=$author_name" \
    -c "user.email=$AUTHOR_EMAIL" \
    commit --author="$author_name <$AUTHOR_EMAIL>" -m "$message" \
    ${git_args[@]+"${git_args[@]}"}
fi
