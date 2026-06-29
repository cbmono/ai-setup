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

# Two-human-authority guard (SCHEMA.md): only the human promotes draft→ready.
# Block any agent-role commit whose STAGED changes set a task to `status: ready`.
# (The human-approved promotion must be committed under the `human` role.)
if [ "$role" != "human" ]; then
  if git diff --cached -U0 -- projects | grep -qiE '^\+status:[[:space:]]*ready[[:space:]]*$'; then
    echo "error: role '$role' may not promote a task to 'ready' — draft→ready is the" >&2
    echo "       human's authority (SCHEMA.md). If the human approved it, commit as 'human'." >&2
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
