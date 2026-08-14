#!/usr/bin/env bash
# link-repos.sh — refresh `repos/`, a symlink-per-repo view of reposRoot inside
# this instance.
#
# The control panel and the product repos are PHYSICAL PEERS on disk: the instance
# is never a parent of a repo, because nesting would drag its control-panel
# CLAUDE.md into the cascade of every product-repo session. This gives you the
# convenience of the nested layout without the nesting — one symlink per repo under
# `repos/`, so `ls repos/`, `cd repos/<name>` and editors that open only ONE folder
# all reach the group's repos from inside the instance.
#
# It is a VIEW, not a work location. Role agents still work in their own worktree
# under <reposRoot>/_wt/ (see the project-manager agent), and `repos/` is
# gitignored — install.sh manages that line.
#
# WHAT GETS LINKED: every directory directly under `reposRoot` that contains a
# `.git` and whose name does NOT start with `_`. That one underscore rule skips
# both sibling instances (`_ai-bridge-<group>`) and the worktree root (`_wt`), so
# the view never fills with transient agent worktrees. The instance that holds the
# view is skipped by resolved path as well, whatever it is named — a link back to
# it would make `repos/<instance>/repos/...` recurse forever.
#
# Idempotent and self-pruning: a link whose target is gone, or is no longer a git
# repo, is removed. It only ever creates, replaces or removes SYMLINKS inside
# `repos/`; a real file or directory there is reported and left alone.
#
# Run from a control-panel instance root (reads `reposRoot` from
# instance.config.json). Generic: no org/repo/path literals.
#
# Usage:  scripts/link-repos.sh [--dry-run|-n] [--remove]
#           --remove   delete the links and the (then empty) repos/ dir
set -euo pipefail
shopt -s nullglob

DRY_RUN=0; REMOVE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --remove)     REMOVE=1 ;;
    *) echo "usage: $0 [--dry-run|-n] [--remove]" >&2; exit 2 ;;
  esac
done

CONFIG=instance.config.json
if [[ ! -f "$CONFIG" ]]; then
  echo "link-repos: run from a control-panel instance root (no $CONFIG here)." >&2
  exit 1
fi

INSTANCE=$(pwd -P)
VIEW="$INSTANCE/repos"

# Resolve a link's target to an absolute path (a hand-made one may be relative).
link_target() {
  local tgt; tgt=$(readlink "$1")
  case "$tgt" in /*) printf '%s' "$tgt" ;; *) printf '%s' "$VIEW/$tgt" ;; esac
}

# --- --remove: tear the view down (needs no reposRoot, so it still works when
# --- the config is gone or broken). Only symlinks go; anything real is kept.
if [[ $REMOVE -eq 1 ]]; then
  if [[ ! -d "$VIEW" ]]; then
    echo "link-repos: no repos/ view here — nothing to remove."
    exit 0
  fi
  gone=0
  for link in "$VIEW"/*; do
    if [[ ! -L "$link" ]]; then
      echo "  keep    repos/$(basename "$link") (real file/dir — not ours to delete)"
      continue
    fi
    if [[ $DRY_RUN -eq 1 ]]; then echo "  would   unlink repos/$(basename "$link")"
    else rm "$link"; echo "  unlink  repos/$(basename "$link")"; fi
    gone=$((gone+1))
  done
  # Only succeeds when empty, so a kept real entry preserves the directory.
  [[ $DRY_RUN -eq 1 ]] || rmdir "$VIEW" 2>/dev/null || true
  printf 'link-repos: %d link(s) removed.%s\n' "$gone" \
    "$([[ $DRY_RUN -eq 1 ]] && echo ' (dry-run — nothing changed)')"
  exit 0
fi

# reposRoot from config; expand a leading ~ to $HOME (same idiom as
# prune-worktrees.sh — no jq dependency). The `|| true` matters: with `set -o
# pipefail`, grep finding nothing would abort the script here, so a config with no
# reposRoot key at all would exit 1 silently instead of reaching the explanation
# below — the exact case a fresh instance can be in.
REPOS_ROOT=$(grep -o '"reposRoot"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" \
  | sed 's/.*:[[:space:]]*"//; s/"$//' || true)
REPOS_ROOT=${REPOS_ROOT/#\~/$HOME}

# A fresh instance ships a PLACEHOLDER reposRoot, so "not set yet" is the expected
# state on a first stamp, not a failure. Exit 0 with an explanation: install.sh
# calls this script, and an unconfigured instance must still install cleanly.
if [[ -z "$REPOS_ROOT" || ! -d "$REPOS_ROOT" ]]; then
  echo "  skip  repos/ view — reposRoot ('$REPOS_ROOT') is unset or missing."
  echo "        Set it in $CONFIG, then run scripts/link-repos.sh."
  exit 0
fi
# Canonicalize so the instance-identity check below compares resolved paths.
REPOS_ROOT=$(cd "$REPOS_ROOT" && pwd -P)

if [[ "$REPOS_ROOT" == "$INSTANCE" ]]; then
  echo "  skip  repos/ view — reposRoot is the instance itself (check $CONFIG)." >&2
  exit 0
fi

[[ $DRY_RUN -eq 1 ]] || mkdir -p "$VIEW"
linked=0; unchanged=0; kept=0; pruned=0

# --- pass 1: create or refresh a link per repo -----------------------------
for d in "$REPOS_ROOT"/*/; do
  d=${d%/}
  name=$(basename "$d")
  case "$name" in _*) continue ;; esac              # sibling instances, _wt
  [[ -e "$d/.git" ]] || continue                    # not a repo
  [[ "$(cd "$d" && pwd -P)" != "$INSTANCE" ]] || continue   # never link the holder

  link="$VIEW/$name"
  if [[ -L "$link" ]]; then
    if [[ "$(link_target "$link")" == "$d" ]]; then
      unchanged=$((unchanged+1)); continue
    fi
  elif [[ -e "$link" ]]; then
    echo "  keep    repos/$name (a real file/dir is there — not replacing it)" >&2
    kept=$((kept+1)); continue
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  would   link repos/$name -> $d"
  else
    # -n is required: without it, `ln -sf` on an existing symlink-to-directory
    # creates the new link INSIDE the target repo instead of replacing the link.
    ln -sfn "$d" "$link"
    echo "  link    repos/$name -> $d"
  fi
  linked=$((linked+1))
done

# --- pass 2: prune links whose repo is gone, renamed, or no longer a repo ---
for link in "$VIEW"/*; do
  [[ -L "$link" ]] || continue
  [[ -e "$(link_target "$link")/.git" ]] && continue
  if [[ $DRY_RUN -eq 1 ]]; then echo "  would   prune repos/$(basename "$link") (target gone)"
  else rm "$link"; echo "  prune   repos/$(basename "$link") (target gone)"; fi
  pruned=$((pruned+1))
done

printf 'link-repos: %d linked, %d unchanged, %d pruned, %d kept.%s\n' \
  "$linked" "$unchanged" "$pruned" "$kept" \
  "$([[ $DRY_RUN -eq 1 ]] && echo ' (dry-run — nothing changed)')"
