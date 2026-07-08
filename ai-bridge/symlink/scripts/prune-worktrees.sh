#!/usr/bin/env bash
# prune-worktrees.sh — safely reclaim finished git worktrees under <reposRoot>/_wt.
#
# For each worktree under _wt whose tree is CLEAN (nothing uncommitted), decide by
# its branch's PR state (via `gh`, falling back to git when gh is absent/offline):
#   · PR merged            → remove   (task done)
#   · PR closed (unmerged) → remove   (task abandoned/superseded)
#   · PR open              → keep     (in flight)
#   · no PR / gh offline   → remove only if the branch is already merged into the
#                            repo's default branch; otherwise keep.
# Dirty worktrees are always kept — only they risk losing uncommitted work. The
# clean check uses `git status --porcelain` (no --ignored), so it flags tracked
# modifications and untracked NON-ignored files, but not ignored build artifacts
# (node_modules/, dist/, .pnpm-store). Removal therefore uses `--force`: at that
# point the tree is verified clean of real changes, and --force only lets git
# clear those ignored artifacts (some git versions refuse otherwise).
# Removing a clean worktree deletes just its working directory + build artifacts;
# the branch ref and every committed object survive in the repo (re-checkout with
# `git worktree add` if ever needed), so this can never lose committed work.
#
# Run from a control-panel instance root (reads `reposRoot` from
# instance.config.json). Generic: no org/repo/path literals.
#
# Usage:  scripts/prune-worktrees.sh [--dry-run|-n]
set -euo pipefail

DRY_RUN=0
case "${1:-}" in --dry-run|-n) DRY_RUN=1 ;; "") ;; *) echo "usage: $0 [--dry-run|-n]" >&2; exit 2 ;; esac

CONFIG=instance.config.json
if [[ ! -f "$CONFIG" ]]; then
  echo "prune-worktrees: run from a control-panel instance root (no $CONFIG here)." >&2
  exit 1
fi

# reposRoot from config; expand a leading ~ to $HOME.
REPOS_ROOT=$(grep -o '"reposRoot"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" \
  | sed 's/.*:[[:space:]]*"//; s/"$//')
REPOS_ROOT=${REPOS_ROOT/#\~/$HOME}
if [[ -z "$REPOS_ROOT" || ! -d "$REPOS_ROOT" ]]; then
  echo "prune-worktrees: reposRoot ('$REPOS_ROOT') not found — check $CONFIG." >&2
  exit 1
fi

WT_ROOT="$REPOS_ROOT/_wt"
if [[ ! -d "$WT_ROOT" ]]; then
  echo "prune-worktrees: no $WT_ROOT — nothing to do."
  exit 0
fi

HAVE_GH=0; command -v gh >/dev/null 2>&1 && HAVE_GH=1

# Resolve a repo's default branch offline: prefer recorded origin/HEAD, else the
# first common name that exists as a remote-tracking ref.
default_branch() {
  local repo=$1 def c
  def=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || true
  if [[ -z "$def" ]]; then
    for c in main master next develop; do
      git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$c" && { def=$c; break; }
    done
  fi
  printf '%s' "$def"
}

# PR state for a branch: prints merged|closed|open|none|unknown.
# open wins over merged wins over closed when a branch has several PRs.
pr_state() {
  local repo=$1 br=$2 states
  [[ $HAVE_GH -eq 1 ]] || { printf unknown; return; }
  states=$( (cd "$repo" && gh pr list --head "$br" --state all --json state --jq '[.[].state]|join(" ")') 2>/dev/null ) || { printf unknown; return; }
  [[ -z "$states" ]] && { printf none; return; }
  case " $states " in
    *OPEN*)   printf open ;;
    *MERGED*) printf merged ;;
    *CLOSED*) printf closed ;;
    *)        printf none ;;
  esac
}

removed=0; kept=0

for repo in "$REPOS_ROOT"/*/; do
  repo=${repo%/}
  [[ "$repo" == "$WT_ROOT" ]] && continue
  [[ -e "$repo/.git" ]] || continue

  def=$(default_branch "$repo")
  [[ -n "$def" ]] || { echo "SKIP repo (no default branch): $repo" >&2; continue; }

  while IFS= read -r line; do
    [[ "$line" == "worktree "* ]] || continue
    wt=${line#worktree }
    case "$wt" in "$WT_ROOT"/*) ;; *) continue ;; esac
    [[ -d "$wt" ]] || continue

    br=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')

    # Dirty tree → never touch (only uncommitted changes are unrecoverable).
    if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
      echo "KEEP (dirty)      $wt  [$br]"; kept=$((kept+1)); continue
    fi

    decision=keep; why=unmerged
    case "$(pr_state "$repo" "$br")" in
      open)   decision=keep;   why="pr open" ;;
      merged) decision=remove; why="pr merged" ;;
      closed) decision=remove; why="pr closed" ;;
      none|unknown)
        # git-only fallback (gh absent/offline): remove only if HEAD is already
        # merged into the repo's default branch. Anything else is kept — we do no
        # upstream-gone/unpushed guessing here: once remote-tracking refs are
        # pruned, `@{u}` no longer resolves, so that heuristic is unreliable.
        sha=$(git -C "$wt" rev-parse HEAD 2>/dev/null || echo '')
        if [[ -n "$sha" ]] && git -C "$repo" merge-base --is-ancestor "$sha" "origin/$def" 2>/dev/null; then
          decision=remove; why="merged into $def"
        fi
        ;;
    esac

    if [[ "$decision" == remove ]]; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "WOULD REMOVE      $wt  [$br]  ($why)"
      else
        # --force is safe: the tree is verified clean above, so this only lets git
        # clear ignored build artifacts (node_modules/, dist/) it would else refuse.
        git -C "$repo" worktree remove --force "$wt" && echo "REMOVED           $wt  [$br]  ($why)"
      fi
      removed=$((removed+1))
    else
      echo "KEEP ($why)       $wt  [$br]"; kept=$((kept+1))
    fi
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null)

  [[ $DRY_RUN -eq 1 ]] || git -C "$repo" worktree prune 2>/dev/null || true
done

echo "---"
[[ $HAVE_GH -eq 1 ]] || echo "(gh not found — used git-only merge detection; squash-merged branches may be kept)"
printf 'prune-worktrees: %d removable, %d kept.%s\n' "$removed" "$kept" \
  "$([[ $DRY_RUN -eq 1 ]] && echo ' (dry-run — nothing changed)')"
