#!/usr/bin/env bash
#
# required-checks.sh — resolve the REQUIRED-check set for a pull request and verify
# every member is green. This is precondition 1 of the delegated merge gate
# (`AUTONOMY.md` → "Merge under `yolo`"); nothing else in the bundle may merge a PR
# without it exiting 0.
#
#   Usage: scripts/required-checks.sh <pr> [--repo <owner>/<name>] [--head <sha>]
#
# Exit codes — 0 is the ONLY clearance; every other code is a refusal:
#
#   0  a non-empty required set resolved and every member passed
#   1  a required check is not green — failing, pending, or never reported
#   2  usage error, or the environment can't answer (no `gh`, unreadable PR)
#   3  no required set could be resolved — the merge authority is NOT exercisable
#      here (this is the signal AUTONOMY.md's preflight surfaces to the human)
#   4  this PR edits the declared list itself — changing the gate is a human call
#
# TWO SOURCES, IN ORDER
#
#   1. PLATFORM — branch protection / rulesets, read via `gh pr checks --required`.
#      Authoritative wherever it exists, because the host enforces it for humans and
#      for the loop alike; the loop is then a second lock, not the only one.
#   2. DECLARED — `.github/required-checks.txt` on the PR's BASE branch, one check
#      name per line. Used ONLY when the platform reports no required set at all.
#      It exists for hosts where protection is unavailable — notably private repos on
#      a free plan, where the branch-protection AND rulesets APIs both answer 403.
#
#      PLATFORM-ENFORCED IS STRICTLY BETTER. Upgrading the plan and configuring
#      protection needs no change here: source 1 starts resolving and automatically
#      wins, the declared file becomes dead weight, and the gate also starts applying
#      to human merges and to anything else pushing at the branch.
#
# GENERIC TEMPLATE FILE — symlinked from the `ai-bridge` template; do not edit per
# instance. It takes no org, repo, or check names: those live in the target repo.
#
# FAILS CLOSED. An empty set, an unparseable answer, a declared name that no check
# reports (a rename), a skipped check, a pending check — all refuse. A required check
# the loop cannot see green is a required check that did not pass.
set -euo pipefail

DECLARED_PATH=".github/required-checks.txt"

usage() {
  echo "Usage: $(basename "$0") <pr> [--repo <owner>/<name>] [--head <sha>]" >&2
  exit 2
}

pr=""; repo=""; want_head=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; [ -n "$repo" ] || usage; shift 2 ;;
    --head) want_head="${2:-}"; [ -n "$want_head" ] || usage; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) [ -z "$pr" ] || { echo "error: unexpected argument '$1'" >&2; usage; }
       pr="$1"; shift ;;
  esac
done
[ -n "$pr" ] || usage

command -v gh >/dev/null 2>&1 || {
  echo "error: gh not found — cannot verify required checks" >&2
  exit 2
}

# bash 3.2 (the macOS default) errors on "${arr[@]}" when arr is empty under `set -u`,
# hence the ${arr[@]+...} guard at every expansion.
R=()
[ -n "$repo" ] && R=(--repo "$repo")

# --- PR facts ---------------------------------------------------------------
meta="$(gh pr view "$pr" ${R[@]+"${R[@]}"} \
        --json url,baseRefName,headRefOid \
        --jq '[.url, .baseRefName, .headRefOid] | @tsv' 2>/dev/null)" || {
  echo "error: could not read PR $pr${repo:+ in $repo}" >&2
  exit 2
}
url="$(printf '%s' "$meta" | cut -f1)"
base="$(printf '%s' "$meta" | cut -f2)"
head_sha="$(printf '%s' "$meta" | cut -f3)"
nwo="$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*#\1#')"

[ -n "$base" ] && [ -n "$head_sha" ] && [ "$nwo" != "$url" ] || {
  echo "error: could not resolve base branch / head SHA / repo for PR $pr" >&2
  exit 2
}

# Pin to the SHA the reviewer actually cleared, when the caller knows it. Checks are
# reported against the head, so a moved head invalidates this whole answer.
if [ -n "$want_head" ] && [ "$want_head" != "$head_sha" ]; then
  echo "refuse: head moved — verified $want_head, PR is now at $head_sha" >&2
  exit 1
fi

# --- source 1: platform-required set ----------------------------------------
# Classify on the PAYLOAD, not the exit code: `gh pr checks --required` exits
# non-zero both when a required check FAILS and when no protection exists, and those
# two must never be confused. Three answers are recognised, and ONLY three:
#
#   JSON array         -> protection answered. An empty array means it requires
#                         nothing, which legitimately falls through to source 2.
#   the "no required
#   checks" message    -> no protection on this branch; source 2 may answer.
#   anything else      -> we do NOT know what the platform requires. Refuse (exit 2).
#
# That last arm is the point. A transient 5xx, an expired token or a rate limit all
# produce some other text, and silently reading them as "nothing is required" would
# hand the decision to a declared list that may be weaker than the protection we
# just failed to read — failing open at exactly the moment we are least informed.
#
# The message lands on STDERR, while the JSON lands on stdout — so both streams are
# captured, separately. Merging them would let a stray gh warning prefix the payload
# and turn a good JSON answer into an unrecognised one.
required=""
source="platform"
probe_err="$(mktemp)"
trap 'rm -f "$probe_err"' EXIT
platform_raw="$(gh pr checks "$pr" ${R[@]+"${R[@]}"} --required --json name,bucket 2>"$probe_err" || true)"
platform_msg="$(cat "$probe_err")"
case "$platform_raw$platform_msg" in
  '['*)
    # Enumerate separately so a failure here is also an error, not an empty set.
    if ! required="$(gh pr checks "$pr" ${R[@]+"${R[@]}"} --required --json name \
                     --jq '.[].name' 2>/dev/null)"; then
      echo "error: protection reported a required set but it could not be read —" >&2
      echo "       refusing rather than falling back to the declared list." >&2
      exit 2
    fi
    ;;
  *"no required checks"*) required="" ;;
  *)
    echo "error: unrecognised answer from 'gh pr checks --required' for PR $pr." >&2
    echo "       Cannot tell 'nothing is required' from 'the query failed', so the" >&2
    echo "       required set is unknown and this refuses (fail closed)." >&2
    echo "       Got: ${platform_raw:-}${platform_msg:+ }${platform_msg:-}" >&2
    [ -n "$platform_raw$platform_msg" ] || echo "       (no output on either stream)" >&2
    exit 2 ;;
esac

# --- source 2: declared list on the base branch ------------------------------
if [ -z "$required" ]; then
  source="declared"
  # `gh api` prints the error BODY to stdout on a 404, so take the output only on a
  # clean exit — otherwise `{"message":"Not Found"...}` becomes a "required check".
  if ! declared_raw="$(gh api -H "Accept: application/vnd.github.raw" \
                       "/repos/$nwo/contents/$DECLARED_PATH?ref=$base" 2>/dev/null)"; then
    declared_raw=""
  fi
  # Comments are whole-line only (`#` in column 1 after optional spaces) — a check
  # name may legitimately contain '#', so nothing is stripped mid-line.
  required="$(printf '%s\n' "$declared_raw" \
              | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
              | grep -v '^#' | grep -v '^$' || true)"

  if [ -n "$required" ]; then
    # A PR that rewrites the gate must not be cleared by the gate it rewrites. The
    # list is read from BASE, so an open PR cannot weaken its own merge — but merging
    # it would weaken every later one, and that is the human's decision to take.
    changed="$(gh pr diff "$pr" ${R[@]+"${R[@]}"} --name-only 2>/dev/null)" || {
      echo "error: could not list the files PR $pr changes — refusing (fail closed)" >&2
      exit 2
    }
    if printf '%s\n' "$changed" | grep -Fxq "$DECLARED_PATH"; then
      echo "refuse: PR $pr edits $DECLARED_PATH — a change to the merge gate itself is" >&2
      echo "        a human decision. Surface it; do not auto-merge." >&2
      exit 4
    fi
  fi
fi

if [ -z "$required" ]; then
  echo "not-exercisable: no required checks for $nwo ($base)." >&2
  echo "        No branch protection reports a required set, and $DECLARED_PATH is" >&2
  echo "        absent or empty on the base branch. Surface the PR for the human." >&2
  exit 3
fi

# --- verify every required name is green at the current head -----------------
checks="$(gh pr checks "$pr" ${R[@]+"${R[@]}"} --json name,bucket \
          --jq '.[] | "\(.bucket)\t\(.name)"' 2>/dev/null || true)"

problems=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  buckets="$(printf '%s\n' "$checks" | awk -F'\t' -v n="$name" '$2 == n { print $1 }')"
  if [ -z "$buckets" ]; then
    problems="${problems}  - ${name}: not reported on this PR (renamed, or never ran)
"
  elif printf '%s\n' "$buckets" | grep -qv '^pass$'; then
    problems="${problems}  - ${name}: $(printf '%s' "$buckets" | tr '\n' ',' | sed 's/,$//')
"
  fi
done <<EOF
$required
EOF

if [ -n "$problems" ]; then
  echo "refuse: required checks not green on PR $pr (source: $source, head $head_sha):" >&2
  printf '%s' "$problems" >&2
  echo "        Only 'pass' clears — pending, skipped and missing all count as not passed." >&2
  exit 1
fi

count="$(printf '%s\n' "$required" | grep -c '^' || true)"
echo "ok: $count required check(s) pass on PR $pr (source: $source, head $head_sha)"
