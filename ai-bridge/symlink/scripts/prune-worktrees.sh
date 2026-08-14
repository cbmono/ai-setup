#!/usr/bin/env bash
# prune-worktrees.sh — safely reclaim finished git worktrees.
#
# WHERE IT LOOKS. Two roots, both scanned, because a worktree may sit in either:
#   · `worktreeRoot` from instance.config.json (a leading ~ is expanded) — where
#     agent worktrees live now, deliberately OUTSIDE any synced folder. Worktrees
#     must not live under a Dropbox/iCloud path: sync rewrites and deletes files
#     inside them mid-run, which has produced phantom test failures and a phantom
#     review blocker. `worktreeRoot` is the single source of truth for the path —
#     the dispatch briefs name the config key, not a literal.
#   · <reposRoot>/_wt — the legacy root, still scanned so nothing stranded there
#     is orphaned. `reposRoot` is typically inside the synced folder, which is
#     exactly why worktrees moved out of it.
# An instance with no `worktreeRoot` key keeps the old behaviour (legacy root
# only), so this is safe to ship ahead of the config change.
#
# WHAT IT DECIDES. Three outcomes, not two:
#   REMOVE       done automatically, on a PM tick. Permitted ONLY for a worktree
#                that is all of: on a real branch, tree fully clean, and its PR
#                merged/closed (or its branch already merged into the default
#                branch).
#   RECLAIMABLE  finished as far as can be told, but NOT removed automatically —
#                reported so the PM can surface it, and removed only when a human
#                runs `--reclaim`.
#   KEEP         left alone, under every flag.
#
# WHY A DETACHED HEAD IS NEVER AUTO-REMOVED  ← read this before widening the script
# This header used to claim removal "can never lose committed work" because "the
# branch ref and every committed object survive". That is true only for a worktree
# ON A BRANCH. A detached-HEAD worktree has no branch ref: commits made in it are
# reachable only from that worktree's own HEAD and its per-worktree reflog, and
# `git worktree remove` deletes both — after which nothing points at them. So the
# one class the script cannot classify from a branch name is also the one class
# whose commits it can destroy irrecoverably. Detached worktrees are therefore
# report-only, unconditionally, however confidently the SHA→PR lookup below
# classifies them (owner decision, 2026-08-14). The lookup's job is to stop the
# false NEGATIVE — a squash-merged PR's head SHA is never an ancestor of the
# default branch, so the ancestor test alone kept such worktrees forever — and to
# make the board report accurate, NOT to widen what gets deleted unattended.
#
# PR state comes from `gh`, by branch where there is one and by SHA where there is
# not (`gh api repos/{owner}/{repo}/commits/<sha>/pulls`, falling back to a PR
# search). With no gh, or offline, it falls back to git: is HEAD already merged
# into the default branch. Every unknown degrades to KEEP.
#
# THE GUARDS, each one paid for by an incident:
#   · uncommitted work — any tracked modification, or any untracked file that is
#     not recognised review scaffolding, keeps the worktree under every flag. A
#     manual sweep once found 88 lines of uncommitted README work in a "finished"
#     worktree. Ignored build artifacts (node_modules/, dist/, .pnpm-store) never
#     count as work; recognised scaffolding (probe/baseline files) makes a
#     worktree RECLAIMABLE at most, never auto-removable — so a misclassified
#     name can cost a report line, never a deletion.
#   · no commits yet — HEAD still at origin/<default>. A worktree created the
#     standard way is trivially "merged into the default branch", because a commit
#     is its own ancestor. On 2026-08-04 that removed three running agents'
#     worktrees minutes after they were created.
#   · recently active — anything touched within PRUNE_ACTIVE_MINUTES (default 120)
#     is assumed to have a live agent in it. A clean tree is NOT evidence of an
#     idle worktree: an agent that has not written a file yet is indistinguishable
#     from an abandoned checkout, and that is exactly the window the 2026-08-04
#     dispatches were destroyed in. Set PRUNE_ACTIVE_MINUTES=0 to disable.
#   · unrecoverable commits — a detached HEAD whose commits are on no ref, and
#     which no merged/closed PR accounts for, is kept even under `--reclaim`.
#     Rescue it to a branch first (`git branch <name> <sha>`).
#   · locked — `git worktree lock` is honoured as an explicit "do not touch".
#
# Removal uses `--force`: the tree is verified clean of real changes first, and
# --force only lets git clear ignored artifacts (some git versions refuse
# otherwise). Note that it also clears ignored review scaffolding.
#
# Run from a control-panel instance root (reads `reposRoot` and `worktreeRoot`
# from instance.config.json). Generic: no org/repo/path literals.
#
# Usage:  scripts/prune-worktrees.sh [--dry-run|-n] [--reclaim]
#
# Verified by scripts/test-prune-worktrees.sh, which builds one throwaway
# worktree per decision class and asserts every outcome. Run it after any change
# here — this script cannot be exercised safely by hand.
set -euo pipefail

DRY_RUN=0; RECLAIM=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1 ;;
    --reclaim)    RECLAIM=1 ;;
    -h|--help)    sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) echo "usage: $0 [--dry-run|-n] [--reclaim]" >&2; exit 2 ;;
  esac
  shift
done

CONFIG=instance.config.json
if [[ ! -f "$CONFIG" ]]; then
  echo "prune-worktrees: run from a control-panel instance root (no $CONFIG here)." >&2
  exit 1
fi

# A string value from the flat config, with a leading ~ expanded to $HOME.
config_path() { # <key>
  local v
  v=$(grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$CONFIG" 2>/dev/null \
    | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//') || true
  printf '%s' "${v/#\~/$HOME}"
}

# Canonicalize (resolve symlinks) so path matching lines up with the resolved
# paths `git worktree list --porcelain` emits — otherwise a symlinked root makes
# the "$root"/* match miss every worktree and the prune becomes a silent no-op.
# ($TMPDIR is symlinked on macOS, so this also bites the fixture harness.)
canon() { ( cd "$1" 2>/dev/null && pwd -P ); }

REPOS_ROOT=$(config_path reposRoot)
if [[ -z "$REPOS_ROOT" || ! -d "$REPOS_ROOT" ]]; then
  echo "prune-worktrees: reposRoot ('$REPOS_ROOT') not found — check $CONFIG." >&2
  exit 1
fi
REPOS_ROOT=$(canon "$REPOS_ROOT")

# Scan roots, in order: the configured worktreeRoot, then the legacy <reposRoot>/_wt.
ROOTS=(); ROOT_LABELS=()
add_root() { # <path> <label>
  local p=$1 r
  [[ -n "$p" && -d "$p" ]] || return 0
  r=$(canon "$p"); [[ -n "$r" ]] || return 0
  local existing
  for existing in ${ROOTS+"${ROOTS[@]}"}; do [[ "$existing" == "$r" ]] && return 0; done
  ROOTS+=("$r"); ROOT_LABELS+=("$2")
}

WT_CONFIGURED=$(config_path worktreeRoot)
if [[ -n "$WT_CONFIGURED" && ! -d "$WT_CONFIGURED" ]]; then
  echo "prune-worktrees: worktreeRoot ('$WT_CONFIGURED') does not exist — skipping it." >&2
fi
add_root "$WT_CONFIGURED" worktreeRoot
add_root "$REPOS_ROOT/_wt" legacy
if [[ ${#ROOTS[@]} -eq 0 ]]; then
  echo "prune-worktrees: no worktree root exists (worktreeRoot in $CONFIG, or $REPOS_ROOT/_wt) — nothing to do."
  exit 0
fi
for i in "${!ROOTS[@]}"; do
  printf 'prune-worktrees: scan root  %s  (%s)\n' "${ROOTS[i]}" "${ROOT_LABELS[i]}"
done

# Is a path inside one of the scan roots?
in_scan_root() {
  local p=$1 r
  for r in "${ROOTS[@]}"; do case "$p" in "$r"/*) return 0 ;; esac; done
  return 1
}
# Is a path itself a scan root (so: never a candidate repo)?
is_scan_root() {
  local p=$1 r
  for r in "${ROOTS[@]}"; do [[ "$p" == "$r" ]] && return 0; done
  return 1
}

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

# Reduce a space-separated list of PR states to one verdict:
# open wins over merged wins over closed when several PRs match.
rank_states() {
  case " ${1:-} " in
    *OPEN*)   printf open ;;
    *MERGED*) printf merged ;;
    *CLOSED*) printf closed ;;
    *)        printf none ;;
  esac
}

# PR state for a BRANCH: merged|closed|open|none|unknown.
pr_state_for_branch() {
  local repo=$1 br=$2 states
  [[ $HAVE_GH -eq 1 && -n "$br" ]] || { printf unknown; return; }
  states=$( (cd "$repo" && gh pr list --head "$br" --state all --json state \
    --jq '[.[].state]|join(" ")') 2>/dev/null ) || { printf unknown; return; }
  rank_states "$states"
}

# PR state for a SHA — the capability a detached HEAD needs and `--head` cannot
# give: `gh pr list --head HEAD` looks up a branch literally named "HEAD" and
# always matches nothing, which is how every detached worktree used to reach the
# ancestor-only fallback. `commits/<sha>/pulls` associates a commit with its PR
# even after a squash merge, when the SHA is on no ref at all. Falls back to a
# PR search, then to unknown (which degrades to KEEP).
pr_state_for_sha() {
  local repo=$1 sha=$2 states
  [[ $HAVE_GH -eq 1 && -n "$sha" ]] || { printf unknown; return; }
  states=$( (cd "$repo" && gh api "repos/{owner}/{repo}/commits/$sha/pulls" \
    --jq '[.[] | if .merged_at then "MERGED" elif .state == "open" then "OPEN" else "CLOSED" end] | join(" ")') 2>/dev/null ) \
    || states=$( (cd "$repo" && gh pr list --search "$sha" --state all --json state \
         --jq '[.[].state]|join(" ")') 2>/dev/null ) \
    || { printf unknown; return; }
  rank_states "$states"
}

# Is this untracked path recognised review scaffolding rather than work? Kept
# deliberately narrow, and note the blast radius: a name matching here can only
# move a worktree from KEEP to RECLAIMABLE (report-only), never to an automatic
# removal, because auto-removal separately requires a fully clean tree.
is_scaffolding() {
  local b; b=$(basename "${1%/}")
  case "$b" in
    probe|probe-*|probe.*|probe_*) return 0 ;;
    baseline|baseline-*|baseline.*|baseline_*) return 0 ;;
    mutant|mutant-*|mutants|*.orig|*.rej|*.log|*.tmp|*~) return 0 ;;
    .DS_Store|.bun-cache*|.pnpm-store*|node_modules|__pycache__) return 0 ;;
    .venv|.venv-*|venv|venv-*) return 0 ;;
  esac
  return 1
}

# clean | scaffolding | work.  `git status --porcelain` (no --ignored) already
# hides ignored build artifacts; of what remains, only untracked entries can ever
# be scaffolding — a modification to a TRACKED file is always work.
tree_state() {
  local wt=$1 st line path
  st=$(git -C "$wt" status --porcelain 2>/dev/null) || { printf work; return; }
  [[ -n "$st" ]] || { printf clean; return; }
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "${line:0:2}" == '??' ]] || { printf work; return; }
    path=${line:3}
    path=${path%\"}; path=${path#\"}
    is_scaffolding "$path" || { printf work; return; }
  done <<< "$st"
  printf scaffolding
}

# Has anything in the worktree been touched in the last PRUNE_ACTIVE_MINUTES?
# A liveness signal, because reachability and cleanliness are not one: an agent
# that has not written a file yet looks exactly like an abandoned checkout.
# Deliberately non-recursive — a recursive find over node_modules costs seconds
# per worktree, and a live agent touches the root or a top-level file anyway.
recently_active() {
  local wt=$1 mins=${PRUNE_ACTIVE_MINUTES:-120}
  [[ "$mins" =~ ^[0-9]+$ ]] || mins=120
  [[ "$mins" -gt 0 ]] || return 1
  [[ -n "$(find "$wt" -maxdepth 1 -mmin "-$mins" 2>/dev/null | head -1)" ]]
}

# Is this SHA reachable from any ref (branch, remote-tracking, tag)? If not, the
# only thing pointing at it is the worktree's own HEAD, and removing the worktree
# leaves nothing that can find it again.
on_some_ref() {
  local repo=$1 sha=$2
  [[ -n "$sha" ]] || return 1
  [[ -n "$(git -C "$repo" for-each-ref --contains "$sha" --count=1 --format='%(refname)' 2>/dev/null)" ]]
}

removed=0; reclaimable=0; kept=0; stale=0
SEEN_WT=$'\n'

# Decide and act on one worktree. Reads the porcelain record vars set by the loop
# below (wt/head/ref/detached/locked/prunable) plus repo/def/def_sha.
classify() {
  [[ -n "$wt" ]] || return 0
  in_scan_root "$wt" || return 0
  SEEN_WT+="$wt"$'\n'

  local label; if [[ $detached -eq 1 ]]; then label="detached@${head:0:8}"; else label="$ref"; fi

  # Registered but its directory is gone: nothing to remove, and `worktree prune`
  # below clears the administrative entry.
  if [[ $prunable -eq 1 || ! -d "$wt" ]]; then
    printf 'STALE             %s  [%s]  (directory gone — worktree prune clears it)\n' "$wt" "$label"
    stale=$((stale+1)); return 0
  fi
  if [[ $locked -eq 1 ]]; then keep locked "$label"; return 0; fi

  local tree; tree=$(tree_state "$wt")
  if [[ "$tree" == work ]]; then keep "uncommitted work" "$label"; return 0; fi
  if recently_active "$wt"; then keep "recently active" "$label"; return 0; fi
  # A worktree still at origin/<default> has committed nothing, so it cannot be
  # finished work — however trivially "merged" the ancestor test finds it.
  if [[ -n "$def_sha" && "$head" == "$def_sha" ]]; then keep "no commits yet" "$label"; return 0; fi

  local state
  if [[ $detached -eq 1 ]]; then state=$(pr_state_for_sha "$repo" "$head")
  else state=$(pr_state_for_branch "$repo" "$ref"); fi

  local finished=0 why=""
  case "$state" in
    open)   keep "pr open" "$label"; return 0 ;;
    merged) finished=1; why="pr merged" ;;
    closed) finished=1; why="pr closed" ;;
    none|unknown)
      if [[ -n "$head" ]] && git -C "$repo" merge-base --is-ancestor "$head" "origin/$def" 2>/dev/null; then
        finished=1; why="merged into $def"
      fi ;;
  esac

  if [[ $finished -eq 0 ]]; then
    if [[ $detached -eq 1 ]] && ! on_some_ref "$repo" "$head"; then
      # The irrecoverable class: detached, commits on no ref, no PR accounting for
      # them. Kept even under --reclaim; rescue to a branch first.
      keep "unmerged; commits on NO ref — rescue with: git -C $repo branch <name> $head" "$label"
    else
      keep unmerged "$label"
    fi
    return 0
  fi

  # Finished. Auto-removal needs all three: a real branch, a fully clean tree,
  # and the finished verdict above. Anything else is report-only.
  local hold=""
  [[ $detached -eq 1 ]] && hold="detached HEAD"
  [[ "$tree" == scaffolding ]] && hold="${hold:+$hold, }untracked scaffolding"
  if [[ -z "$hold" ]]; then
    remove "$why" "$label"
  elif [[ $RECLAIM -eq 1 ]]; then
    remove "$why; $hold" "$label"
  else
    local note="$why; $hold"
    if [[ $detached -eq 1 ]] && ! on_some_ref "$repo" "$head"; then
      note="$note, commits on no ref"
    fi
    printf 'RECLAIMABLE       %s  [%s]  (%s — report-only; rerun with --reclaim)\n' "$wt" "$label" "$note"
    reclaimable=$((reclaimable+1))
  fi
}

keep() { printf 'KEEP (%s)  %s  [%s]\n' "$1" "$wt" "$2"; kept=$((kept+1)); }

remove() { # <why> <label>
  if [[ $DRY_RUN -eq 1 ]]; then
    printf 'WOULD REMOVE      %s  [%s]  (%s)\n' "$wt" "$2" "$1"; removed=$((removed+1))
  # --force is safe here: the tree is verified clean of real changes above, so it
  # only lets git clear ignored artifacts (node_modules/, dist/) it would else
  # refuse — and, deliberately under --reclaim, ignored review scaffolding.
  elif git -C "$repo" worktree remove --force "$wt"; then
    printf 'REMOVED           %s  [%s]  (%s)\n' "$wt" "$2" "$1"; removed=$((removed+1))
  else
    printf 'FAILED to remove  %s  [%s]  (%s)\n' "$wt" "$2" "$1" >&2; kept=$((kept+1))
  fi
}

for repo in "$REPOS_ROOT"/*/; do
  repo=${repo%/}
  is_scan_root "$repo" && continue
  [[ -e "$repo/.git" ]] || continue

  def=$(default_branch "$repo")
  [[ -n "$def" ]] || { echo "SKIP repo (no default branch): $repo" >&2; continue; }

  # The git-only fallback (below) tests against origin/$def; refresh it so a stale
  # local ref doesn't misreport merged branches as unmerged. Only when there's no
  # gh (the only time that fallback runs) — offline, this just no-ops.
  [[ $HAVE_GH -eq 0 ]] && git -C "$repo" fetch --prune origin "$def" 2>/dev/null || true

  def_sha=$(git -C "$repo" rev-parse "origin/$def" 2>/dev/null || echo '')

  # Parse `worktree list --porcelain` records rather than asking the worktree what
  # branch it is on: the porcelain reports `detached` explicitly, where
  # `rev-parse --abbrev-ref HEAD` returns the literal string "HEAD" and invites
  # exactly the branch-shaped lookup that never matches.
  wt=""; head=""; ref=""; detached=0; locked=0; prunable=0
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) wt=${line#worktree }; head=""; ref=""; detached=0; locked=0; prunable=0 ;;
      "HEAD "*)     head=${line#HEAD } ;;
      "branch "*)   ref=${line#branch }; ref=${ref#refs/heads/} ;;
      detached)     detached=1 ;;
      locked|"locked "*)     locked=1 ;;
      prunable|"prunable "*) prunable=1 ;;
      "")           classify; wt="" ;;
    esac
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null; printf '\n')

  [[ $DRY_RUN -eq 1 ]] || git -C "$repo" worktree prune 2>/dev/null || true
done

# Directories sitting in a scan root that are NOT registered worktrees of any repo
# under reposRoot. Reported only, never touched: they are usually a rescued or
# hand-copied tree, or a private cache dir. Without this they are invisible — 13
# had accumulated on the opensc instance unnoticed.
# NOTE it also catches a live worktree of a repo OUTSIDE reposRoot (this script
# only enumerates repos under reposRoot), so the line says "inspect" and not
# "delete", and deliberately does not act.
unregistered=0
for root in "${ROOTS[@]}"; do
  for d in "$root"/*/; do
    d=${d%/}
    [[ -d "$d" ]] || continue
    case "$SEEN_WT" in *$'\n'"$d"$'\n'*) continue ;; esac
    printf 'UNREGISTERED      %s  (no worktree of any repo under reposRoot — may be a cache dir, a rescued tree, or a worktree of a repo elsewhere; inspect by hand)\n' "$d"
    unregistered=$((unregistered+1))
  done
done

echo "---"
[[ $HAVE_GH -eq 1 ]] || echo "(gh not found — used git-only merge detection; squash-merged branches may be kept)"
printf 'prune-worktrees: %d removable, %d reclaimable (report-only), %d kept, %d stale, %d unregistered.%s\n' \
  "$removed" "$reclaimable" "$kept" "$stale" "$unregistered" \
  "$([[ $DRY_RUN -eq 1 ]] && echo ' (dry-run — nothing changed)')"
if [[ $reclaimable -gt 0 && $RECLAIM -eq 0 ]]; then
  echo "(the reclaimable set is finished but held back — a detached HEAD is never removed"
  echo " automatically, since its commits are on no branch ref. Run with --reclaim to remove.)"
fi
