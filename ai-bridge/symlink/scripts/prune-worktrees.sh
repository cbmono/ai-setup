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
# only), so this is safe to ship ahead of the config change. Docs that name the
# key must state that fallback: absent `worktreeRoot` means `<reposRoot>/_wt`.
#
# WHAT IT DECIDES. Three outcomes, not two:
#   REMOVE       done automatically, on a PM tick. Permitted ONLY for a worktree
#                that is all of: on a real branch, tree fully clean, and its PR
#                merged/closed (or its branch already merged into the default
#                branch — but see the `no commits yet` guard below: "merged into
#                the default branch" is indistinguishable from "created from the
#                default branch and has not committed yet", so in practice a
#                merged/closed PR is the only evidence that reaches REMOVE).
#   RECLAIMABLE  finished as far as can be told, but NOT removed automatically —
#                reported so the PM can surface it, and removed only when a human
#                a human decides, then removes by hand.
#   KEEP         left alone, under every flag.
#
# LIVENESS, AND WHY THE CALLER STILL HAS A RULE. An earlier version of this header
# said the pruner "CANNOT see a live agent inside a worktree" and that "no check
# can be added for it either; liveness isn't visible from the filesystem". The
# second half of that is no longer true: the `recently active` guard below walks
# the worktree recursively for a recent mtime (39 ms on a 664 MB repo), which is
# exactly such a check. But it is a BEST-EFFORT BACKSTOP with a real window — an
# agent that is thinking, waiting on a review, or running a long command writes
# nothing for longer than PRUNE_ACTIVE_MINUTES (default 120) and then looks idle,
# and nothing in the filesystem distinguishes that from an abandoned checkout.
# So the caller-side rule survives as defence in depth, and remains the PRIMARY
# guard: run this only when your own in-flight count is zero (see the
# project-manager agent's "Reclaim the worktree"). The mtime veto catches the
# dispatch you forgot about; your in-flight count is what you actually rely on.
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
#   · no commits yet — HEAD carries no commit the default branch lacks
#     (`rev-list --count origin/<default>..HEAD` == 0). A worktree created the
#     standard way is trivially "merged into the default branch", because a commit
#     is its own ancestor. On 2026-08-04 that removed three running agents'
#     worktrees minutes after they were created.
#     COUNT, NEVER COMPARE. Two independent attempts ten days apart both reached
#     for `HEAD == origin/<default>` — exact SHA equality (the 2026-08-04 fix,
#     commit 58e368a, written but left dangling and never shipped, and a later
#     re-derivation from scratch). It reads correct and stops recognising a
#     dispatch the moment anything merges to the default branch, i.e. within
#     minutes on an active repo, leaving the destructive case wide open on a stale
#     base — the normal state of every worktree older than the last merge. Two
#     people reaching the same wrong instinct makes this a design trap, not a
#     slip; the correct form counts, and the guard's code comment says so again.
#     NOTE the guard and the "merged into the default branch" test below describe
#     the SAME set: a HEAD is an ancestor of origin/<default> exactly when it has
#     no commits of its own. Git cannot tell a fresh dispatch from a branch whose
#     commits were fast-forwarded into the default branch, so the guard runs first
#     and the tie goes to KEEP, per this script's governing rule: bloat is
#     recoverable, a running agent's uncommitted work is not.
#     BLAST RADIUS, stated honestly, because it is larger than "FF-merges without
#     PRs". The guard runs BEFORE the PR lookup, so ANY zero-commit worktree is a
#     plain KEEP — including one whose PR is merged, and it is not even reported
#     RECLAIMABLE. GitHub's DEFAULT merge strategy is a merge commit, which leaves
#     the merged branch tip an ancestor of the default branch, so a repo that
#     merge-commits loses automatic reclaim ENTIRELY and its finished worktrees
#     must be cleared by hand. A repo that squash-merges is unaffected: a
#     squash-merged branch keeps its own commits, so the guard does not fire and
#     the merged PR reaches REMOVE normally. The direction is safe either way, and
#     the collision above forces the KEEP — this is a documented cost, not a bug
#     to be fixed by moving the guard. Moving it re-arms the 2026-08-04 deletion;
#     the `branch-recycled-name` fixture in the test harness pins its position.
#   · recently active — anything touched within PRUNE_ACTIVE_MINUTES (default 120)
#     is assumed to have a live agent in it. A clean tree is NOT evidence of an
#     idle worktree: an agent that has not written a file yet is indistinguishable
#     from an abandoned checkout, and that is exactly the window the 2026-08-04
#     dispatches were destroyed in. The scan is RECURSIVE (heavy caches pruned):
#     an agent working only inside subdirectories never refreshes the worktree
#     root's mtime, so a root-only check ages a live agent out of the window.
#     Set PRUNE_ACTIVE_MINUTES=0 to disable — which also disables the only
#     liveness signal there is, so do it deliberately.
#   · unrecoverable commits — a detached HEAD whose commits are on no ref, and
#     which no merged/closed PR accounts for, is always kept.
#     Rescue it to a branch first (`git branch <name> <sha>`).
#   · locked — `git worktree lock` is honoured as an explicit "do not touch".
#
# REPORT-ONLY. This script does not remove anything, ever. It classifies and
# prints the `git worktree remove` commands for you to run. The removal path was
# deleted in ai-bridge v2: it had destroyed three running agents' worktrees, and
# no harness mechanism covers worktrees under <reposRoot>/_wt (native isolation
# and its retention sweep only reach worktrees the harness itself created, of the
# SESSION repo — measured, see the worktree-isolation-spike finding). So the
# classification is the valuable half and deletion is the dangerous half; the
# dangerous half is now a human's hand on a printed command.
#
# Run from a control-panel instance root (reads `reposRoot` and `worktreeRoot`
# from instance.config.json). Generic: no org/repo/path literals.
#
# Usage:  scripts/prune-worktrees.sh          # classify and report; never removes
#         scripts/prune-worktrees.sh --dry-run  # accepted, no-op (always dry now)
#
# Verified by ai-bridge/tests/prune-worktrees.test.sh in the ai-setup template
# repo, which builds one throwaway worktree per decision class and asserts every
# outcome. Run it after any change here — this script cannot be exercised safely
# by hand. (The harness lives outside symlink/ deliberately: everything under
# symlink/ is symlinked into every instance, and a test harness is not machinery
# an instance needs.)
set -euo pipefail

# `--dry-run` is retained only so existing callers and muscle memory keep working:
# this script is always dry, so the flag sets nothing and changes nothing.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) : ;;   # no-op; always report-only
    --reclaim)
      echo "prune-worktrees: --reclaim was removed in ai-bridge v2 — this script never deletes." >&2
      echo "  It prints the exact 'git worktree remove' commands; run the ones you want." >&2
      exit 2 ;;
    -h|--help)    sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) echo "usage: $0 [--dry-run|-n]   (report-only; --reclaim is gone)" >&2; exit 2 ;;
  esac
  shift
done

CONFIG=instance.config.json
if [[ ! -f "$CONFIG" ]]; then
  echo "prune-worktrees: run from a control-panel instance root (no $CONFIG here)." >&2
  exit 1
fi

# A string value from the flat config, with a leading ~ expanded to $HOME.
# `|| true`: with `set -o pipefail`, grep finding no such key would abort the
# script here with no output at all, instead of reaching the explanation below.
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
#
# RECURSIVE, deliberately. This was a root-only check, which misses the common
# case: an agent editing `src/foo/bar.ts` never changes the mtime of the worktree
# root, so a live worktree ages out of the window while work is going on in it.
# The heavy caches are pruned so the walk stays cheap (they are also the
# directories most likely to be freshly written by an install and to claim
# liveness that no agent is providing).
#
# The prune list below is deliberately short, and only names that are
# unambiguously a cache or a generated store: pruning a directory means activity
# inside it does NOT protect the worktree, so every name added here is a small
# step back toward removing a live tree. `dist`, `build`, `target` and `vendor`
# are deliberately absent — they are tracked source in some repos.
LIVENESS_PRUNE=( node_modules .git '.pnpm-store*' '.bun-cache*' .venv venv
                 __pycache__ .pytest_cache .mypy_cache .next .nuxt .turbo
                 .cache .gradle )
recently_active() {
  local wt=$1 mins=${PRUNE_ACTIVE_MINUTES:-120} args=() n
  [[ "$mins" =~ ^[0-9]+$ ]] || mins=120
  [[ "$mins" -gt 0 ]] || return 1
  # The root's own mtime, checked separately so that a worktree whose directory
  # happens to be NAMED like a cache is not pruned out of its own liveness test.
  if [[ -n "$(find "$wt" -maxdepth 0 -mmin "-$mins" 2>/dev/null)" ]]; then return 0; fi
  for n in "${LIVENESS_PRUNE[@]}"; do args+=( -name "$n" -o ); done
  args+=( -false )
  [[ -n "$(find "$wt" -mindepth 1 \( "${args[@]}" \) -prune -o -mmin "-$mins" -print 2>/dev/null | head -1)" ]]
}

# Does this HEAD carry any commit the default branch does not already have?
#
# COUNTING is the load-bearing part, and the reason this is not the one-liner it
# looks like. DO NOT rewrite this as `[[ "$2" == "$def_sha" ]]`. SHA equality is
# the trap two independent implementations fell into ten days apart: it recognises
# only a dispatch whose base is still the exact tip of the default branch, so a
# single merge anywhere in the repo re-arms the deletion this guard exists to
# prevent, and on an active repo that window closes in minutes. The predicate that
# actually matters is "has this worktree committed anything of its own that would
# be lost", and only a count answers it:
#     git -C <wt> rev-list --count "origin/<default>..<head>"   == 0
#
# Any failure to establish the answer (missing origin ref, unknown sha, empty
# HEAD) fires the guard rather than skipping it: an error must never be what
# authorises a removal, per this script's rule that every unknown degrades to
# KEEP. That path is REACHABLE, contrary to what this comment used to claim.
# `git symbolic-ref --short refs/remotes/origin/HEAD` SUCCEEDS on a dangling
# symbolic ref — verified on git 2.48: point origin/HEAD at a ref that does not
# exist and symbolic-ref still exits 0 with the name, while `show-ref --verify`
# on it exits 1 and the rev-list then exits 128. origin/HEAD goes dangling
# whenever the ref it names disappears without being refreshed (an upstream
# default-branch rename or deletion, a partial fetch, a hand-edited remote),
# until someone runs `git remote set-head origin -a`. Whether a given git
# version repairs it on fetch is not something to rely on — 2.48 did in one
# rename test, which is exactly the kind of behaviour that varies.
# The rule, generally: a ref is verified with `git show-ref --verify`, never by
# `symbolic-ref` having returned something. (default_branch() above uses
# show-ref for its fallback candidates but takes the symbolic-ref answer as-is,
# which is where an unverified name can enter.)
no_own_commits() { # <repo> <sha> <default-branch>
  local n
  [[ -n "$2" && -n "$3" ]] || return 0
  n=$(git -C "$1" rev-list --count "origin/$3..$2" 2>/dev/null) || return 0
  [[ "$n" == 0 ]]
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
CMDS=""
SEEN_WT=$'\n'

# Decide and act on one worktree. Reads the porcelain record vars set by the loop
# below (wt/head/ref/detached/locked/prunable) plus repo/def.
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
  # A worktree that has committed nothing of its own cannot be finished work —
  # however trivially "merged" the ancestor test below finds it. This runs BEFORE
  # the PR lookup on purpose: `gh pr list --head <branch>` matches by branch NAME,
  # so a recycled branch name can return a merged PR for a dispatch created
  # minutes ago, and the two together would remove a live agent's worktree.
  if no_own_commits "$repo" "$head" "$def"; then keep "no commits yet" "$label"; return 0; fi

  local state
  if [[ $detached -eq 1 ]]; then state=$(pr_state_for_sha "$repo" "$head")
  else state=$(pr_state_for_branch "$repo" "$ref"); fi

  local finished=0 why=""
  case "$state" in
    open)   keep "pr open" "$label"; return 0 ;;
    merged) finished=1; why="pr merged" ;;
    closed) finished=1; why="pr closed" ;;
    none|unknown)
      # The git-only fallback, for a repo with no gh or no PR. Kept as a backstop
      # and NOT the primary signal: it is true exactly when `no_own_commits`
      # above is true, so the guard pre-empts it by construction and this arm can
      # only be reached if that guard is removed or errors. That is deliberate —
      # deleting the guard must change a decision loudly (the harness asserts it),
      # not silently fall through to the test that caused the incident.
      if [[ -n "$head" ]] && git -C "$repo" merge-base --is-ancestor "$head" "origin/$def" 2>/dev/null; then
        finished=1; why="merged into $def"
      fi ;;
  esac

  if [[ $finished -eq 0 ]]; then
    if [[ $detached -eq 1 ]] && ! on_some_ref "$repo" "$head"; then
      # The irrecoverable class: detached, commits on no ref, no PR accounting for
      # them. Always kept; rescue to a branch first.
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
    report_removable "$why" "$label"
  else
    local note="$why; $hold"
    if [[ $detached -eq 1 ]] && ! on_some_ref "$repo" "$head"; then
      note="$note, commits on no ref"
    fi
    printf 'RECLAIMABLE       %s  [%s]  (%s — needs a human: check it, then remove by hand)\n' "$wt" "$label" "$note"
    reclaimable=$((reclaimable+1))
  fi
}

keep() { printf 'KEEP (%s)  %s  [%s]\n' "$1" "$wt" "$2"; kept=$((kept+1)); }

# Report a worktree as safe to remove, and remember the command for the summary.
#
# Both paths go through `printf %q`, not hand-written quotes: a path containing a
# quote, a newline, a backtick or a `$(...)` would otherwise change what the human
# pastes into their shell. The command is printed, so its escaping is a security
# boundary even though this script runs nothing.
#
# Deliberately WITHOUT `--force`. `tree_state` uses `git status --porcelain`, which
# does not see ignored files, so a worktree whose only remaining content is an
# ignored `.env` or a local config file classifies as clean — and `--force` would
# delete it. Plain `git worktree remove` refuses instead, which hands that judgement
# to the human along with everything else dangerous here. The cost is that genuinely
# disposable artifacts (node_modules/, dist/) also make git refuse; adding `--force`
# then is the human's call, on a tree they can look at.
report_removable() { # <why> <label>
  printf 'REMOVABLE         %s  [%s]  (%s)\n' "$wt" "$2" "$1"
  removed=$((removed+1))
  CMDS="${CMDS}git -C $(printf '%q' "$repo") worktree remove $(printf '%q' "$wt")
"
}

for repo in "$REPOS_ROOT"/*/; do
  repo=${repo%/}
  is_scan_root "$repo" && continue
  [[ -e "$repo/.git" ]] || continue

  def=$(default_branch "$repo")
  [[ -n "$def" ]] || { echo "SKIP repo (no default branch): $repo" >&2; continue; }

  # The zero-commit guard and the git-only fallback both measure against
  # origin/$def; refresh it so a stale local ref doesn't misreport merged
  # branches as unmerged. Only when there's no gh (the only time that fallback
  # runs) — offline, this just no-ops.
  [[ $HAVE_GH -eq 0 ]] && git -C "$repo" fetch --prune origin "$def" 2>/dev/null || true

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

  # No `git worktree prune` here — this script mutates nothing. Entries whose
  # directory is gone are reported STALE, and the summary prints the prune command
  # for a human to run.
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
printf 'prune-worktrees: %d removable, %d reclaimable, %d kept, %d stale, %d unregistered. (report-only — nothing was changed)\n' \
  "$removed" "$reclaimable" "$kept" "$stale" "$unregistered"
if [[ $reclaimable -gt 0 ]]; then
  echo "(reclaimable = finished, but a detached HEAD's commits are on no branch ref, so"
  echo " removing it deletes their only reachability. Check each one before you do.)"
fi
if [[ -n "$CMDS" ]]; then
  echo
  echo "To remove the REMOVABLE set, run these yourself:"
  printf '%s' "$CMDS" | sed 's/^/  /'
  echo
  echo "Then deregister the stale admin entries:  git -C <repo> worktree prune"
fi
