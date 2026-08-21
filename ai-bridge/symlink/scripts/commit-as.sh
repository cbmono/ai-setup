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
# happened repeatedly in practice. Naming paths commits only those, leaving
# everyone else's staged changes staged and intact.
#
# What gets committed for a named path is the STAGED content — `git add` it first.
# A working-tree edit made after that `git add` is not committed and stays a
# working-tree edit.
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
# WHY THIS EXISTS, AND WHY NO FIRST-PARTY FEATURE REPLACES IT (v2 audit, 2026-08).
# Native background sessions commit, push their own branch and open draft PRs — a
# different problem. That is work in an isolated worktree of a TARGET repo under one
# identity. This is work in the shared working tree of ONE bundle repo, by several
# concurrent agents, under per-agent authorship. Three things follow that nothing
# upstream provides:
#   1. `git commit -- <path>` has the wrong semantics: it commits WORKING TREE
#      content for that path, not the staged content. Hence the temporary index
#      (GIT_INDEX_FILE + read-tree + update-index --index-info) — the only way to
#      commit exactly the named staged entries while leaving a sibling agent's
#      staged files untouched. Not cleverness; there is no git primitive for it.
#   2. The promotion guard below reads the INDEX for that same reason. If the commit
#      took its content from the working tree, an uncommitted `status: ready` edit
#      could ride along past the guard.
#   3. Per-agent author identity, which is the bundle's provenance record.
# Verdict: keep, unshrunk. The v2 plan's overlap table guessed "shrink hard,
# possibly delete" and was wrong on all three counts.
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

# Build the SELECTED INDEX: HEAD, plus exactly the staged entries for the named
# paths. This is deliberately NOT `git commit -- <paths>`, git's pathspec commit
# form, for two reasons:
#
#   1. That form commits the WORKING TREE content of each named path, ignoring what
#      was staged for it. A file edited after its `git add` would be committed
#      unreviewed, and the staged version silently overwritten.
#   2. The promotion guard below reads the index. If the commit took its content
#      from the working tree instead, the guard would judge a different blob than
#      the one that lands — a `status: draft` index passing the gate while a
#      `status: ready` working tree gets committed.
#
# One temporary index, used for BOTH the guard and the commit, closes both: what is
# validated is byte-for-byte what lands. The shared index is never written, so a
# sibling agent's staged work survives untouched.
selected_index=""
has_head=0
git rev-parse --verify -q HEAD >/dev/null 2>&1 && has_head=1

if [ "${#paths[@]}" -gt 0 ]; then
  selected_index="$(mktemp "${TMPDIR:-/tmp}/commit-as-index.XXXXXX")"
  trap 'rm -f "$selected_index"' EXIT

  # Seed from HEAD (empty on an unborn branch) so unselected paths keep the
  # committed state and no sibling's staged change can leak in.
  if [ "$has_head" -eq 1 ]; then seed=HEAD; else seed=--empty; fi
  if ! GIT_INDEX_FILE="$selected_index" git read-tree "$seed"; then
    echo "error: could not seed a temporary index from HEAD — refusing to commit" >&2
    exit 3
  fi

  # Copy the staged entries (exact blob + mode) for the named paths. Piped, not
  # captured: `git ls-files -z` output is NUL-separated and command substitution
  # drops NUL bytes, which would join paths containing spaces into one bad entry.
  if ! git ls-files --stage -z -- "${paths[@]}" \
       | GIT_INDEX_FILE="$selected_index" git update-index -z --index-info; then
    echo "error: could not copy the staged entries for the named paths — refusing" >&2
    echo "       to commit as role '$role' (fail closed)." >&2
    exit 3
  fi

  # A path staged for DELETION is absent from the index, so the copy above left
  # HEAD's version in place; drop those explicitly or the commit would keep the file.
  if [ "$has_head" -eq 1 ] \
     && ! git diff --cached --name-only -z --diff-filter=D -- "${paths[@]}" \
          | GIT_INDEX_FILE="$selected_index" git update-index -z --force-remove --stdin; then
    echo "error: could not stage the deletions for the named paths — refusing to" >&2
    echo "       commit as role '$role' (fail closed)." >&2
    exit 3
  fi

  # Nothing staged under the named paths. Say so plainly: git's own message would
  # describe the shared WORKING TREE ("nothing added to commit…"), which is both
  # confusing and wrong here — the usual cause is a forgotten `git add`.
  allow_empty=0
  for arg in ${git_args[@]+"${git_args[@]}"}; do
    [ "$arg" = "--allow-empty" ] && allow_empty=1
  done
  if [ "$allow_empty" -eq 0 ] && [ "$has_head" -eq 1 ] \
     && GIT_INDEX_FILE="$selected_index" git diff --cached --quiet HEAD; then
    echo "error: nothing staged under the named path(s):" >&2
    for p in "${paths[@]}"; do printf '         %s\n' "$p" >&2; done
    echo "       Stage your changes by explicit path first, then commit those same paths:" >&2
    echo "         git add -- <path>...   # never 'git add -A' in a shared instance" >&2
    exit 4
  fi
fi

# Read the index the commit will actually use: the selected index when we built
# one, the shared index otherwise.
gitx() {
  if [ -n "$selected_index" ]; then
    GIT_INDEX_FILE="$selected_index" git "$@"
  else
    git "$@"
  fi
}

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
  # Read through the selected index (when one was built), so this judges exactly
  # what the commit will contain and nothing else: a sibling agent's staged
  # promotion is not this role's to answer for, and its own commit gets checked
  # when it runs. A promotion inside this role's own paths is still refused.
  if ! staged_list="$(gitx diff --cached --name-only -- projects)"; then
    echo "error: could not list staged files (git diff failed) — refusing to commit as" >&2
    echo "       role '$role' (fail closed). Fix the repo state and retry." >&2
    exit 3
  fi
  # Here-doc (not a pipe) so the loop body runs in THIS shell and $violations survives.
  while IFS= read -r staged_file; do
    [ -n "$staged_file" ] || continue

    # Only files whose staged diff ADDS a `status: ready` line.
    if ! gitx diff --cached -U0 -- "$staged_file" \
         | grep -qiE '^\+status:[[:space:]]*ready[[:space:]]*$'; then
      continue
    fi

    # Owning project slug from projects/<slug>/...
    slug="$(printf '%s\n' "$staged_file" | sed -n 's#^projects/\([^/][^/]*\)/.*#\1#p')"

    # Read autonomy from the blob the commit will contain, not the working tree —
    # same source as `kind` below, so the check is consistent with exactly what's
    # being committed (no working-tree/staged TOCTOU). Missing/unparseable → stays
    # `gated` (fail closed).
    autonomy="gated"
    if [ -n "$slug" ]; then
      parsed="$(gitx show ":projects/$slug/project.md" 2>/dev/null \
                | sed -n 's/^autonomy:[[:space:]]*\([A-Za-z][A-Za-z-]*\)[[:space:]]*$/\1/p' | head -n1)"
      [ -n "$parsed" ] && autonomy="$parsed"
    fi

    # Task kind read from the same blob — what is actually being committed.
    kind="$(gitx show ":$staged_file" 2>/dev/null \
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

# Commit the selected index when we built one — the same tree the guard above
# judged. The shared index is left alone, so any other staged change stays staged
# for its own author to commit. No `exec` here: the EXIT trap has to run to remove
# the temporary index.
if [ -n "$selected_index" ]; then
  GIT_INDEX_FILE="$selected_index" git \
    -c "user.name=$author_name" \
    -c "user.email=$AUTHOR_EMAIL" \
    commit --author="$author_name <$AUTHOR_EMAIL>" -m "$message" \
    ${git_args[@]+"${git_args[@]}"}
else
  exec git \
    -c "user.name=$author_name" \
    -c "user.email=$AUTHOR_EMAIL" \
    commit --author="$author_name <$AUTHOR_EMAIL>" -m "$message" \
    ${git_args[@]+"${git_args[@]}"}
fi
