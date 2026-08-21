#!/usr/bin/env bash
# Exercises symlink/scripts/prune-worktrees.sh — the worktree CLASSIFIER.
# It is report-only since ai-bridge v2: it never removes, it prints commands.
#
# The pruner is the one script in this template that can destroy work, and it has
# done so (three running agents' worktrees, 2026-08-04). It has no safe manual
# test: exercising it by hand means pointing it at real worktrees. So this harness
# builds a throwaway git repo with one worktree per decision class, runs the
# pruner with --dry-run against it, and asserts the decision for every case.
#
# Properties it guarantees, and which any change to the pruner must preserve:
#   1. It never touches the real reposRoot. It builds its own instance dir with
#      its own instance.config.json pointing at a mktemp tree, and asserts every
#      scan root the pruner reports is inside that tree.
#   2. It builds OUTSIDE any synced folder, and refuses to run if $TMPDIR is
#      inside one — a Dropbox-backed fixture can have its files rewritten
#      mid-run (see the dropbox-backed-worktrees finding in the instance KB).
#   3. It runs the pruner with --dry-run only. Nothing is ever removed.
#   4. NO detached-HEAD worktree is ever reported REMOVABLE, with any flags.
#      This is asserted as a blanket property over the whole matrix, not just
#      per case, because that is the class whose commits removal destroys with
#      no ref left pointing at them.
#   5. NO worktree holding untracked scaffolding is ever auto-removed. Also a
#      blanket property: the scaffolding allowlist is a name heuristic, and the
#      thing that bounds its blast radius to a report line is precisely that a
#      recognised name can never reach REMOVE on its own.
#   6. NO worktree with zero commits of its own is ever removed, under any flag.
#      That is a fresh dispatch — the shape that destroyed three running agents'
#      worktrees on 2026-08-04 — and it stays that shape as its base goes stale.
#   7. The zero-commit guard's POSITION in the decision chain is pinned, not just
#      its existence. A guard that exists to pre-empt a later test cannot be
#      detected by any fixture that reaches KEEP through that later test, so
#      moving it is invisible to the rest of this matrix while re-arming the
#      original bug. `branch-recycled-name` is the fixture that sees the move.
#
# `gh` is stubbed (a fake `gh` first on PATH) so PR state is a fixture rather
# than a live network call. The stub answers the two invocations the pruner
# makes; it exits non-zero on any other, so a new gh call shows up as a failure
# instead of silently degrading to "no PR".
#
# Usage:  ai-bridge/tests/prune-worktrees.test.sh
#         PRUNER=/path/to/prune-worktrees.sh ai-bridge/tests/prune-worktrees.test.sh
#         SHOW_ONLY=1 ai-bridge/tests/prune-worktrees.test.sh   # run, no asserts
#
# SHOW_ONLY prints the raw pruner output for every fixture without asserting. It
# is how you see what a given version of the pruner decides — including an older
# one via PRUNER= — which is what established that the pre-fix script's
# detached-HEAD handling was a false negative rather than a false positive.
set -uo pipefail

PRUNER="${PRUNER:-$(cd "$(dirname "$0")/.." && pwd)/symlink/scripts/prune-worktrees.sh}"
SHOW_ONLY="${SHOW_ONLY:-0}"

die() { printf 'prune-worktrees.test: %s\n' "$*" >&2; exit 2; }
[[ -f "$PRUNER" ]] || die "pruner not found at $PRUNER"

# --- fixture root, outside any synced folder ----------------------------------
TMP="$(mktemp -d "${TMPDIR:-/tmp}/prune-fixture.XXXXXX")" || die "mktemp failed"
# Canonicalize: on macOS $TMPDIR is a symlink (/var -> /private/var) and
# `git worktree list --porcelain` prints resolved paths. Comparing an
# unresolved root against resolved worktree paths matches nothing and turns the
# whole sweep into a silent no-op — the same trap the pruner canonicalizes for.
TMP="$(cd "$TMP" && pwd -P)"
case "$TMP" in
  *Dropbox*|*iCloud*|*"Google Drive"*|*OneDrive*)
    rm -rf "$TMP"; die "refusing to build fixtures inside a synced folder ($TMP)" ;;
esac
trap 'rm -rf "$TMP"' EXIT

ORIGIN="$TMP/origin.git"
REPOS="$TMP/repos"
REPO="$REPOS/proj"
LEGACY="$REPOS/_wt"          # legacy root: <reposRoot>/_wt
WTROOT="$TMP/wt"             # configured root: worktreeRoot
INSTANCE="$TMP/instance"
FIXTURES="$TMP/gh-fixtures"

mkdir -p "$REPOS" "$LEGACY" "$WTROOT" "$INSTANCE" "$TMP/bin"

# One definition, used by every scenario that needs the full config back after
# scenario D replaces it — so the two can never drift apart.
write_config() {
  cat > "$INSTANCE/instance.config.json" <<JSON
{
  "org": "fixture-org",
  "reposRoot": "$REPOS",
  "worktreeRoot": "$WTROOT",
  "authorEmail": "fixture@example.com"
}
JSON
}
write_config

# --- the upstream + clone -----------------------------------------------------
g() { git -C "$REPO" "$@"; }

git init -q -b main "$REPO"
g config user.email fixture@example.com
g config user.name  Fixture
g config commit.gpgsign false
printf 'one\n' > "$REPO/tracked.txt"
# Tracked from the first commit so it exists in every worktree, including the ones
# detached at c1: it makes probe-ignored/ an IGNORED path, which is what review
# scaffolding usually is and what `git worktree remove --force` silently clears.
printf 'probe-ignored/\n' > "$REPO/.gitignore"
g add tracked.txt .gitignore; g commit -qm 'c1: tracked file + ignore rule'
C1="$(g rev-parse HEAD)"
printf 'two\n' >> "$REPO/tracked.txt"
g commit -qam 'c2: main tip'
git init -q --bare -b main "$ORIGIN"
g remote add origin "$ORIGIN"
g push -q -u origin main
g remote set-head origin -a >/dev/null
MAIN_SHA="$(g rev-parse origin/main)"

# A SHA that is NOT an ancestor of main and is on no ref: the shape a
# squash-merged PR head has once its remote branch is deleted. This is why the
# old ancestor test reported such worktrees KEEP (unmerged) forever.
orphan_sha() { # <worktree-path> -> creates the worktree detached at a fresh orphan sha
  local path=$1 msg=$2 tmpbr; tmpbr="tmp/$(basename "$path")"
  g branch -q "$tmpbr" main
  git -C "$REPO" worktree add -q --detach "$path" "$tmpbr" >/dev/null
  git -C "$path" config user.email fixture@example.com
  git -C "$path" config user.name Fixture
  printf '%s\n' "$msg" > "$path/feature.txt"
  git -C "$path" add feature.txt
  git -C "$path" commit -qm "$msg"
  g branch -qD "$tmpbr"          # the ref is gone; only this worktree's HEAD holds the sha
  git -C "$path" rev-parse HEAD
}

wt_branch() { # <path> <branch> — new branch at origin/main, no commits yet
  git -C "$REPO" worktree add -q "$1" -b "$2" origin/main >/dev/null
  git -C "$1" config user.email fixture@example.com
  git -C "$1" config user.name Fixture
}

commit_in() { # <path> <file> <msg>
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -qm "$3"
}

# --- the decision-class fixtures ---------------------------------------------
# Names are the assertion keys; keep them non-substrings of one another.
declare -a DETACHED=()
declare -a SCAFFOLDING=()
declare -a ZERO_COMMIT=()

# 0. THE STALE-BASE DISPATCH — built first, so the default branch can be advanced
#    beneath it. On a branch, ZERO commits of its own, clean, NO PR, and its base
#    one commit behind origin/main. This is the 2026-08-04 shape a few minutes
#    later, once anything at all has merged, and it is exactly what a SHA-EQUALITY
#    guard stops recognising: head no longer equals origin/main, so the guard
#    misses, the ancestor test says "merged into main" (a commit is its own
#    ancestor), the tree is clean — and a running agent's worktree is removed.
#    Must be KEPT under every flag. Fixture 7 keeps the equality case covered.
wt_branch "$WTROOT/branch-stale-base" feat/stalebase
ZERO_COMMIT+=("$WTROOT/branch-stale-base")
printf 'three\n' >> "$REPO/tracked.txt"
g commit -qam 'c3: the default branch moves on beneath the stale-base worktree'
g push -q origin main
MAIN_SHA="$(g rev-parse origin/main)"

# From here on the LOCAL default branch is deliberately left BEHIND origin/main.
# The guard must measure against `origin/<default>` — what a worktree is created
# from — and not against a local branch, which is stale in any clone that has not
# pulled. In a fixture where the two are equal the difference is invisible, and a
# pruner measuring against the local ref would judge a fresh dispatch to have
# commits of its own and remove it. Detach first so the branch ref can move
# without a reset and the tree stays clean.
git -C "$REPO" checkout -q --detach
git -C "$REPO" update-ref refs/heads/main "$C1"

# 1. detached at a squash-merged PR head (PR MERGED, sha on no ref, not an
#    ancestor of main). The false negative that kept oscos-qa-28 forever.
S_MERGED="$(orphan_sha "$WTROOT/detached-squash-merged" 'squash-merged head')"
DETACHED+=("$WTROOT/detached-squash-merged")

# 2. detached with unpushed commits and NO PR: the irrecoverable class. Removing
#    it destroys commits that no ref points at, so it must be kept even under
#    --reclaim.
S_UNPUSHED="$(orphan_sha "$WTROOT/detached-unpushed" 'unpushed detached work')"
DETACHED+=("$WTROOT/detached-unpushed")

# 3. detached at a merged PR head, holding untracked review scaffolding only.
#    Scaffolding used to read as "dirty" and block reclaim (0 removable, 8 kept,
#    ~2.6 GB by hand on 2026-08-05).
S_SCAFFOLD="$(orphan_sha "$WTROOT/detached-scaffolding" 'scaffolding holder')"
printf 'probe\n' > "$WTROOT/detached-scaffolding/probe-viewof.ts"
printf '{}\n'    > "$WTROOT/detached-scaffolding/baseline-chart.json"
DETACHED+=("$WTROOT/detached-scaffolding")
SCAFFOLDING+=("$WTROOT/detached-scaffolding")

# 4. on a branch with a merged PR, but a TRACKED file modified: real uncommitted
#    work. Must be kept under every flag.
wt_branch "$WTROOT/branch-dirty-tracked" feat/dirty
commit_in "$WTROOT/branch-dirty-tracked" feature.txt 'dirty branch work'
printf 'local edit\n' >> "$WTROOT/branch-dirty-tracked/tracked.txt"

# 5. on a branch with an OPEN PR: in flight.
wt_branch "$WTROOT/branch-open-pr" feat/open-pr
commit_in "$WTROOT/branch-open-pr" feature.txt 'in-flight work'

# 6. on a branch that is an ancestor of the default branch, no PR — the case the
#    git-only fallback calls "merged into main". It is INDISTINGUISHABLE from
#    fixture 0: a branch is an ancestor of the default branch exactly when it has
#    no commits of its own, whether that is because its commits were
#    fast-forwarded in or because it never made any. Git offers no discriminator,
#    so the zero-commit guard wins the tie and this is KEPT. The cost is bounded
#    and one-directional (a fast-forward-merged worktree is reported, not
#    reclaimed); the alternative cost is deleting a running agent's directory.
#    A squash-merging repo is unaffected: its merged branches keep their own
#    commits and are removed on PR evidence (fixture 8).
git -C "$REPO" branch -q feat/ff "$C1"
git -C "$REPO" worktree add -q "$WTROOT/branch-ancestor-no-pr" feat/ff >/dev/null
ZERO_COMMIT+=("$WTROOT/branch-ancestor-no-pr")

# 7. fresh dispatch: on a branch, zero commits, HEAD still exactly at
#    origin/main. This is the case that removed oscos-af-001/002/003 while their
#    agents were running — a commit is its own ancestor, so a brand-new branch is
#    trivially "merged into main". Fixture 0 is the same worktree a few minutes
#    later; both must be kept, and only a COUNTING guard covers both.
wt_branch "$WTROOT/branch-fresh-dispatch" feat/fresh
ZERO_COMMIT+=("$WTROOT/branch-fresh-dispatch")

# 7b. THE GUARD'S POSITION. A fresh dispatch — zero commits, clean, on a real
#     branch — whose branch NAME already carries a MERGED PR from an earlier round
#     of work. `gh pr list --head <branch>` matches by branch name, not by SHA, so
#     a recycled name (a re-run task, a re-created branch after a revert, a name
#     from a naming scheme) really does return a merged PR for a worktree created
#     minutes ago. Every other fixture reaches KEEP through a LATER test than the
#     zero-commit guard, so demoting the guard into the `none|unknown` arm — which
#     is where it reads more naturally — changes NO other assertion here while
#     turning a live dispatch into `WOULD REMOVE (pr merged)`: the 2026-08-04 bug,
#     reintroduced silently. This fixture is the only one that sees the move, and
#     it is why the guard runs before the PR lookup rather than inside the
#     fallback arm. Verified by moving the guard and watching this go red.
wt_branch "$WTROOT/branch-recycled-name" feat/recycled
ZERO_COMMIT+=("$WTROOT/branch-recycled-name")

# 8. on a branch with a merged PR, fully clean: the provably-safe auto-remove.
wt_branch "$WTROOT/branch-merged-pr" feat/merged-pr
commit_in "$WTROOT/branch-merged-pr" feature.txt 'landed work'

# 9. on a branch with a merged PR, clean tracked files, but an untracked file
#    that is NOT scaffolding. The oscos-cba-006-rw counter-example: 88 lines of
#    uncommitted README work a naive "delete finished worktrees" rule destroys.
wt_branch "$WTROOT/branch-untracked-work" feat/untracked-work
commit_in "$WTROOT/branch-untracked-work" feature.txt 'landed work'
printf 'corrections a human has not committed yet\n' \
  > "$WTROOT/branch-untracked-work/README-corrections.md"

# 9b. on a branch, merged PR, clean tracked files, and untracked SCAFFOLDING
#     only. The one combination that reaches the scaffolding hold on its own: it
#     satisfies every auto-removal condition except a fully clean tree, so it is
#     the only fixture that can tell "scaffolding is held back" from "something
#     else held it back". Without it, deleting the scaffolding hold from the
#     pruner changes no assertion at all — the detached cases are already held by
#     being detached, and `branch-untracked-work` is held by being work. That
#     mutant survived the round-1 harness (M4, 35/35 still green).
wt_branch "$WTROOT/branch-scaffolding" feat/scaff
commit_in "$WTROOT/branch-scaffolding" feature.txt 'landed work, probes left behind'
printf 'probe\n' > "$WTROOT/branch-scaffolding/probe-run.log"
printf '{}\n'    > "$WTROOT/branch-scaffolding/baseline-out.json"
SCAFFOLDING+=("$WTROOT/branch-scaffolding")

# 10. explicitly locked: an agent's opt-out must be honoured.
wt_branch "$WTROOT/branch-locked" feat/locked
commit_in "$WTROOT/branch-locked" feature.txt 'landed but locked'
git -C "$REPO" worktree lock "$WTROOT/branch-locked"

# 11 + 12. the LEGACY root is still scanned, for both decision directions.
S_LEGACY="$(orphan_sha "$LEGACY/legacy-detached-merged" 'legacy squash head')"
DETACHED+=("$LEGACY/legacy-detached-merged")
wt_branch "$LEGACY/legacy-branch-merged-pr" feat/legacy
commit_in "$LEGACY/legacy-branch-merged-pr" feature.txt 'legacy landed work'

# 13. detached at a SHA that IS an ancestor of the default branch, clean, holding
#     untracked-but-IGNORED review scaffolding. This is the destructive path: the
#     pre-fix script saw no branch, found no PR for the literal ref "HEAD", fell
#     through to the ancestor test, and removed the worktree with --force, which
#     also cleared the ignored scaffolding. Kept in the LEGACY root so the
#     pre-fix script (which scanned only <reposRoot>/_wt) sees it too.
#     Since the fix it is ALSO a zero-commit worktree (an ancestor SHA carries no
#     commits of its own), so it is now kept outright rather than reported — the
#     strongest possible contrast with the pre-fix `WOULD REMOVE` above.
git -C "$REPO" worktree add -q --detach "$LEGACY/legacy-detached-ancestor" "$C1" >/dev/null
mkdir -p "$LEGACY/legacy-detached-ancestor/probe-ignored"
printf 'probe\n' > "$LEGACY/legacy-detached-ancestor/probe-ignored/run.log"
DETACHED+=("$LEGACY/legacy-detached-ancestor")
ZERO_COMMIT+=("$LEGACY/legacy-detached-ancestor")

# 13b. RECURSIVE LIVENESS. On a branch, merged PR, fully clean — so removable in
#      the decision matrix — but with an old worktree ROOT mtime and a tracked
#      file two directories down that was touched seconds ago. An agent edits
#      `src/**`, which never changes the root's mtime, so a root-only liveness
#      check calls this idle and removes a worktree that is being worked in right
#      now. Only a recursive check sees it. Aged in scenario E, so scenarios A-D
#      see an ordinary removable worktree.
NESTED="$WTROOT/branch-nested-activity"
wt_branch "$NESTED" feat/nested
mkdir -p "$NESTED/src/deep"
printf 'live\n' > "$NESTED/src/deep/live.ts"
git -C "$NESTED" add src/deep/live.ts
git -C "$NESTED" commit -qm 'landed work, with a file below the root'

# Make the root and every top-level entry look old, leaving anything deeper
# alone: the exact shape a root-only mtime check cannot see through.
age_root() { # <worktree>
  local wt=$1 e
  for e in "$wt"/* "$wt"/.[!.]*; do [[ -e "$e" ]] && touch -t 200001010000 "$e"; done
  touch -t 200001010000 "$wt"
}

# 14. a plain directory that is not a registered worktree — the stranded-dir
#     hygiene gap. Reportable, never actionable.
mkdir -p "$WTROOT/stranded-plain-dir"
printf 'left behind\n' > "$WTROOT/stranded-plain-dir/leftover.txt"

# --- gh stub ------------------------------------------------------------------
# Answers exactly the two invocations the pruner makes, emulating gh + --jq
# together (the pruner's jq reduces each to a plain space-separated state list):
#   gh pr list --head <branch> --state all --json state --jq ...
#   gh api repos/{owner}/{repo}/commits/<sha>/pulls --jq ...
# Unknown invocations exit 1 so a new gh call surfaces as a harness failure.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
mode=""; key=""
if [[ "${1:-}" == "api" ]]; then
  mode=sha
  key="$(printf '%s' "${2:-}" | sed -n 's#.*/commits/\([0-9a-fA-F]\{4,40\}\)/pulls.*#\1#p')"
else
  args=("$@")
  for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
      --head)   mode=branch; key="${args[i+1]:-}" ;;
      --search) mode=sha;    key="${args[i+1]:-}" ;;
    esac
  done
fi
if [[ -z "$mode" || -z "$key" ]]; then
  echo "gh-stub: unhandled invocation: $*" >&2
  exit 1
fi
awk -v m="$mode" -v k="$key" '$1 == m && $2 == k { out = ""; for (i = 3; i <= NF; i++) out = out (i > 3 ? " " : "") $i; print out }' \
  "${GH_FIXTURES:?}"
STUB
chmod +x "$TMP/bin/gh"

cat > "$FIXTURES" <<EOF
branch feat/dirty MERGED
branch feat/open-pr OPEN
branch feat/merged-pr MERGED
branch feat/recycled MERGED
branch feat/untracked-work MERGED
branch feat/scaff MERGED
branch feat/nested MERGED
branch feat/locked MERGED
branch feat/legacy MERGED
sha $S_MERGED MERGED
sha $S_SCAFFOLD MERGED
sha $S_LEGACY MERGED
EOF
# S_UNPUSHED is deliberately absent: no PR knows that sha.
: "$S_UNPUSHED" "$MAIN_SHA"

# --- runner -------------------------------------------------------------------
# PRUNE_ACTIVE_MINUTES=0 disables the liveness veto for the decision matrix:
# every fixture was created seconds ago, so the veto would otherwise keep them
# all. One separate scenario below asserts the veto itself, with the default.
run_pruner() {
  ( cd "$INSTANCE" \
    && PATH="$TMP/bin:$PATH" \
       GH_FIXTURES="$FIXTURES" \
       PRUNE_ACTIVE_MINUTES="${ACTIVE_MINUTES:-0}" \
       bash "$PRUNER" --dry-run "$@" 2>&1 )
}

pass=0; fail=0
OUT=""

expect() { # <path> <extended-regex the decision line must match>
  local path=$1 want=$2 line
  line="$(printf '%s\n' "$OUT" | grep -F -- "$path" | grep -v -F -- "$path/" | head -1)"
  if [[ -z "$line" ]]; then
    printf '  FAIL  %-34s no line mentioning it in the output\n' "$(basename "$path")"
    fail=$((fail + 1)); return
  fi
  if printf '%s\n' "$line" | grep -Eq -- "$want"; then
    printf '  PASS  %-34s %s\n' "$(basename "$path")" "$(printf '%s' "$line" | sed 's/  */ /g')"
    pass=$((pass + 1))
  else
    printf '  FAIL  %-34s want /%s/\n        got: %s\n' \
      "$(basename "$path")" "$want" "$(printf '%s' "$line" | sed 's/  */ /g')"
    fail=$((fail + 1))
  fi
}

assert() { # <label> <0|1 truthy result>
  if [[ "$2" == 0 ]]; then
    printf '  PASS  %s\n' "$1"; pass=$((pass + 1))
  else
    printf '  FAIL  %s\n' "$1"; fail=$((fail + 1))
  fi
}

# ---- SHOW_ONLY: no assertions, just what this pruner decides -----------------
if [[ "$SHOW_ONLY" == 1 ]]; then
  echo "=== fixtures under $TMP ==="
  echo "--- default run ---"; run_pruner
  echo "--- with --reclaim ---"; run_pruner --reclaim
  exit 0
fi

# ---- scenario A: default run (no --reclaim) ----------------------------------
echo "== scenario A: default run (classify; provably-safe cases report REMOVABLE) =="
OUT="$(run_pruner)"

expect "$WTROOT/detached-squash-merged"       '^RECLAIMABLE'
expect "$WTROOT/detached-unpushed"            '^KEEP'
expect "$WTROOT/detached-scaffolding"         '^RECLAIMABLE'
expect "$WTROOT/branch-dirty-tracked"         '^KEEP \(uncommitted work\)'
expect "$WTROOT/branch-open-pr"               '^KEEP \(pr open\)'
expect "$WTROOT/branch-ancestor-no-pr"        '^KEEP \(no commits yet\)'
expect "$WTROOT/branch-stale-base"            '^KEEP \(no commits yet\)'
expect "$WTROOT/branch-fresh-dispatch"        '^KEEP \(no commits yet\)'
# The guard's position: a merged PR on the branch NAME must not outrank "this
# worktree has committed nothing of its own". If this line ever reads
# `WOULD REMOVE (pr merged)`, the guard has been demoted below the PR lookup.
expect "$WTROOT/branch-recycled-name"         '^KEEP \(no commits yet\)'
expect "$WTROOT/branch-merged-pr"             '^REMOVABLE'
expect "$WTROOT/branch-untracked-work"        '^KEEP \(uncommitted work\)'
expect "$WTROOT/branch-scaffolding"           '^RECLAIMABLE'
expect "$WTROOT/branch-nested-activity"       '^REMOVABLE'
expect "$WTROOT/branch-locked"                '^KEEP \(locked\)'
expect "$LEGACY/legacy-detached-merged"       '^RECLAIMABLE'
expect "$LEGACY/legacy-branch-merged-pr"      '^REMOVABLE'
expect "$LEGACY/legacy-detached-ancestor"     '^KEEP \(no commits yet\)'
expect "$WTROOT/stranded-plain-dir"           '^UNREGISTERED'

# --- blanket properties, over the whole matrix rather than per case -----------
# A per-case expectation only proves the case it names; these say the pruner has
# no path at all to the outcome, which is what makes deleting a guard loud.
never_auto_removed() { # <label> <path>...
  local label=$1 bad="" d; shift
  for d in "$@"; do
    if printf '%s\n' "$OUT" | grep -F -- "$d" | grep -v -F -- "$d/" \
         | grep -Eq '^REMOVABLE'; then
      bad="$bad $d"
    fi
  done
  assert "$label" "$([[ -z "$bad" ]] && echo 0 || echo 1)"
  [[ -z "$bad" ]] || printf '        offending:%s\n' "$bad"
}

# (owner decision, 2026-08-14): detached HEAD is never auto-removed, however
# confidently the SHA->PR lookup classifies it.
never_auto_removed "no detached worktree is ever reported REMOVABLE" "${DETACHED[@]}"
# AC5's other half: a recognised scaffolding name can cost a report line, never a
# deletion. This is what bounds the allowlist's blast radius.
never_auto_removed "no worktree holding scaffolding is auto-removable" "${SCAFFOLDING[@]}"
# The 2026-08-04 class: nothing that has committed nothing of its own is removed.
never_auto_removed "no zero-commit worktree is auto-removable" "${ZERO_COMMIT[@]}"

# Isolation: every scan root the pruner reported is inside the fixture tree, and
# nothing outside it is mentioned.
roots="$(printf '%s\n' "$OUT" | grep '^prune-worktrees: scan root' || true)"
assert "reported at least one scan root" "$([[ -n "$roots" ]] && echo 0 || echo 1)"
outside="$(printf '%s\n' "$roots" | grep -v -F -- "$TMP" || true)"
assert "every scan root is inside the fixture tree" "$([[ -z "$outside" ]] && echo 0 || echo 1)"
[[ -z "$outside" ]] || printf '        outside:\n%s\n' "$outside"
assert "output never mentions a synced path" \
  "$(printf '%s\n' "$OUT" | grep -q -E 'Dropbox|iCloud|OneDrive' && echo 1 || echo 0)"
assert "both roots were scanned (configured + legacy)" \
  "$([[ "$(printf '%s\n' "$roots" | wc -l | tr -d ' ')" == 2 ]] && echo 0 || echo 1)"

# A report-only script must leave the disk exactly as it found it. Output
# assertions alone can't show that: they'd still pass if the run deleted a
# directory it also labelled REMOVABLE. Compare the registered worktrees and the
# on-disk directories before and after a full run.
echo "== scenario A2: a run mutates nothing =="
BEFORE_WT="$(git -C "$REPO" worktree list --porcelain | grep '^worktree ' | sort)"
BEFORE_DIRS="$( { ls -1 "$WTROOT" 2>/dev/null; ls -1 "$LEGACY" 2>/dev/null; } | sort )"
run_pruner >/dev/null
AFTER_WT="$(git -C "$REPO" worktree list --porcelain | grep '^worktree ' | sort)"
AFTER_DIRS="$( { ls -1 "$WTROOT" 2>/dev/null; ls -1 "$LEGACY" 2>/dev/null; } | sort )"
assert "no worktree was deregistered" "$([[ "$BEFORE_WT" == "$AFTER_WT" ]] && echo 0 || echo 1)"
assert "no worktree directory was deleted" "$([[ "$BEFORE_DIRS" == "$AFTER_DIRS" ]] && echo 0 || echo 1)"

# ---- scenario B: --reclaim is refused ---------------------------------------
# The removal path was deleted in ai-bridge v2 (it had destroyed three running
# agents' worktrees, and no harness mechanism covers <reposRoot>/_wt). The flag is
# kept only to fail loudly: a caller or a human with muscle memory must be told the
# capability is gone, not silently given a no-op that looks like a clean sweep.
echo "== scenario B: --reclaim is refused, and the reclaimable set is only reported =="
set +e
B_OUT="$( cd "$INSTANCE" && bash "$PRUNER" --reclaim 2>&1 )"; B_RC=$?
set -e
# assert() uses exit-code semantics: 0 is a pass.
assert "--reclaim exits 2 instead of sweeping" \
  "$([[ $B_RC -eq 2 ]] && echo 0 || echo 1)"
assert "--reclaim says plainly that the script never deletes" \
  "$(printf '%s\n' "$B_OUT" | grep -qi 'never deletes' && echo 0 || echo 1)"
assert "--reclaim removed nothing" \
  "$(printf '%s\n' "$B_OUT" | grep -Eqi '^REMOVED' && echo 1 || echo 0)"

# The detached set stays visible as RECLAIMABLE — a human decides each one — and
# is never promoted to REMOVABLE, whatever flags are passed.
OUT="$(run_pruner)"
for wt in "${DETACHED[@]}"; do
  expect "$wt" '^(RECLAIMABLE|KEEP)'
done

# ---- scenario C: the liveness veto, with the default window -----------------
# Every fixture is seconds old, so with the default PRUNE_ACTIVE_MINUTES nothing
# at all may be removed: a clean tree is not evidence that no agent is working
# there (2026-08-04: three agents' worktrees were clean only because they had
# not written a file yet).
echo "== scenario C: liveness veto (default PRUNE_ACTIVE_MINUTES) =="
ACTIVE_MINUTES="" OUT="$(ACTIVE_MINUTES=120 run_pruner)"
expect "$WTROOT/branch-merged-pr"       '^KEEP \(recently active\)'
expect "$WTROOT/detached-squash-merged" '^KEEP \(recently active\)'
assert "nothing is removable while worktrees are recently active" \
  "$(printf '%s\n' "$OUT" | grep -Eq '^REMOVABLE' && echo 1 || echo 0)"

# ---- scenario D: no worktreeRoot configured (older instances) ---------------
echo "== scenario D: instance.config.json without worktreeRoot =="
cat > "$INSTANCE/instance.config.json" <<JSON
{ "reposRoot": "$REPOS", "authorEmail": "fixture@example.com" }
JSON
OUT="$(run_pruner)"
expect "$LEGACY/legacy-branch-merged-pr" '^REMOVABLE'
assert "legacy-only config still scans <reposRoot>/_wt" \
  "$(printf '%s\n' "$OUT" | grep -q 'scan root' && echo 0 || echo 1)"
assert "worktrees under the unconfigured root are left alone" \
  "$(printf '%s\n' "$OUT" | grep -F -- "$WTROOT/" | grep -Eq '^REMOVABLE' && echo 1 || echo 0)"

# ---- scenario E: the liveness veto reaches below the worktree root -----------
# Restore the full config first (scenario D replaced it), then age the nested
# fixture's root so the ONLY recent mtime in it is two directories down. A
# root-only check reports it idle and removes it (it is branch-backed, clean and
# PR-merged); a recursive one keeps it. The 120-minute window is not the guard
# it looks like if an agent can age out of it by working in src/.
echo "== scenario E: liveness is recursive (activity below the worktree root) =="
write_config
age_root "$NESTED"
assert "the aged worktree's own root looks idle (fixture is still meaningful)" \
  "$([[ -z "$(find "$NESTED" -maxdepth 1 -mmin -120 2>/dev/null | head -1)" ]] && echo 0 || echo 1)"
OUT="$(ACTIVE_MINUTES=120 run_pruner)"
expect "$NESTED" '^KEEP \(recently active\)'

# ---- verdict ----------------------------------------------------------------
echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
