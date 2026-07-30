#!/usr/bin/env bash
#
# commit-as.sh — commit to THIS control-panel instance repo under a per-agent
# author identity, for provenance in the autonomous PM loop.
#
#   Usage: scripts/commit-as.sh <role> "<commit message>" [extra git commit args...]
#
# Stage your changes first (e.g. `git add -A`), then call this. The author NAME
# is the role; the author EMAIL is shared so the host (e.g. GitHub) still links
# commits to the human's account, while `git log --format=%an` /
# `git shortlog -sn` separate work per agent.
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
  echo "Usage: $(basename "$0") <role> \"<commit message>\" [extra git commit args...]" >&2
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

# Two-human-authority guard (SCHEMA.md): draft→ready is the human's gate.
#
# A project may delegate that gate to the loop with `autonomy: yolo` in its
# project.md — and then ONLY for `kind: build` tasks, because SCHEMA.md keeps
# research tasks human-driven even under yolo. So this guard is decided PER TASK
# from the owning project's autonomy plus the task's own kind, instead of
# blocking every agent-role `status: ready` unconditionally — which contradicted
# the autonomy field and left fully-refined yolo build drafts stranded at `draft`.
#
# Fails CLOSED: anything not clearly (yolo AND build) is refused, and an absent
# or unparseable field is treated as `gated` / `unset`.
if [ "$role" != "human" ]; then
  violations=""
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
                | sed -n 's/^autonomy:[[:space:]]*\([A-Za-z][A-Za-z-]*\).*/\1/p' | head -n1)"
      [ -n "$parsed" ] && autonomy="$parsed"
    fi

    # Task kind read from the STAGED blob — what is actually being committed.
    kind="$(git show ":$staged_file" 2>/dev/null \
            | sed -n 's/^kind:[[:space:]]*\([A-Za-z][A-Za-z-]*\).*/\1/p' | head -n1)"
    [ -n "$kind" ] || kind="unset"

    if [ "$autonomy" = "yolo" ] && [ "$kind" = "build" ]; then
      continue
    fi

    violations="${violations}  - ${staged_file} (project '${slug:-?}': autonomy=${autonomy}, kind=${kind})
"
  done <<EOF
$(git diff --cached --name-only -- projects || true)
EOF

  if [ -n "$violations" ]; then
    echo "error: role '$role' may not promote these tasks to 'ready':" >&2
    printf '%s' "$violations" >&2
    echo "       draft→ready is the human's authority (SCHEMA.md). The loop may promote a task" >&2
    echo "       only when its project sets 'autonomy: yolo' AND the task is 'kind: build'" >&2
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

exec git \
  -c "user.name=$author_name" \
  -c "user.email=$AUTHOR_EMAIL" \
  commit --author="$author_name <$AUTHOR_EMAIL>" -m "$message" "$@"
