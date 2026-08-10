#!/usr/bin/env bash
#
# mirror-to.sh — copy this repo's tracked files into a parity repo, minus the
# capabilities that repo must not have.
#
#   Usage:
#     scripts/mirror-to.sh <dest-repo>            # dry run (default): report only
#     scripts/mirror-to.sh <dest-repo> --apply    # actually write
#
# WHY THIS EXISTS
# `ai-setup` (public/external) and `claude-code-setup` (Alteos-internal) are kept
# in parity, with two standing exceptions that must NOT reach the internal repo:
#
#   · The DeepSeek backend — substitution routes a whole session to a third party.
#   · Delegated autonomy (`AUTONOMY.md`) — no self-merging on client code.
#
# Both are deliberately structured so removal is a *deletion*, not an edit:
#   1. WHOLE FILES in EXCLUDE_PATHS are never copied. Because `AUTONOMY.md` is the
#      capability itself (absent file ⇒ every project is `gated`, see SCHEMA.md
#      "Delegated authority"), dropping it disables the feature with no edits to
#      the eight documents that reference it.
#   2. BLOCK MARKERS strip prose: everything between a line containing
#      `mirror:exclude start` and one containing `mirror:exclude end` is removed,
#      markers included. Works in any comment syntax (`<!-- -->`, `#`).
#   3. STRIP_LINE_PATTERNS drop single lines, for content inside fenced code
#      blocks where an HTML comment would render literally.
#   4. The OUTBOUND GUARD greps everything written for tokens that must not
#      survive, and FAILS if any does. A leak is loud, not silent.
#
# WHAT THIS IS NOT
# Not a full mirror. The destination is a SUPERSET, not a copy: it carries its own
# commands, skills and installer logic. So this is a *fast-forward for shared
# files* plus a *divergence report*:
#
#   5. The INBOUND GUARD protects the destination from us. Before overwriting any
#      file, it checks whether the destination version has lines matching
#      LOCAL_TOKENS that the incoming content does not — local content a write
#      would destroy. Such a file is never written; it is reported as MANUAL with
#      the count of lines at risk, and you merge it by hand.
#      (Learned the hard way: a run without this would have deleted ~80 lines
#      across six files — the installer's org-specific clone/symlink logic, three
#      org-only command triggers, and whole doc sections.)
#
# It never commits and never deletes in the destination — you review the diff
# there and commit yourself.
set -euo pipefail

EXCLUDE_PATHS=(
  "ai-bridge/symlink/AUTONOMY.md"      # the delegated-authority capability itself
  ".claude/scripts/deepseek-session.sh"
  ".env.example"                       # exists only for DEEPSEEK_API_KEY
  "scripts/mirror-to.sh"               # this tool is the source repo's own
  "LICENSE"                            # repo identity, not shared config
)

# Lines matching this in the DESTINATION are local content we must never clobber.
# Case-insensitive. Widen it if the destination grows other org-specific vocabulary.
LOCAL_TOKENS='alteos|axa|labs|langdock'


# Anchored regexes; a matching line is dropped. Deliberately literal: if someone
# rewords the prose these stop matching, and the GUARD below catches the leak — a
# loud failure, not a silent one. Used where a marker can't go (code fences, and
# GFM tables, where a comment line would terminate the table).
STRIP_LINE_PATTERNS=(
  'deepseek-session\.sh'                       # inventory lines inside code fences
  '^\| \*\*`yolo`\*\*'                          # the mode's row in README's autonomy table
  '^`yolo` is genuinely all-out\.'             # and the sentence under it
)

# Tokens that must never appear in a mirrored file. Case-insensitive.
FORBIDDEN='yolo|deepseek|ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN'

APPLY=0
DEST=""
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --help|-h) sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "error: unknown flag '$arg'" >&2; exit 2 ;;
    *) [ -z "$DEST" ] || { echo "error: multiple destinations given" >&2; exit 2; }
       DEST="$arg" ;;
  esac
done
[ -n "$DEST" ] || { echo "usage: $0 <dest-repo> [--apply]" >&2; exit 2; }

# Resolve SRC from THIS SCRIPT's location, never the caller's cwd. Invoked by
# absolute path from inside an unrelated git repo, `git rev-parse --show-toplevel`
# would resolve to *that* repo and mirror it into $DEST.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SRC="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
DEST="$(cd "$DEST" 2>/dev/null && pwd -P || true)"
[ -n "$DEST" ] || { echo "error: destination directory does not exist" >&2; exit 2; }
[ "$SRC" != "$DEST" ] || { echo "error: destination is this repo" >&2; exit 2; }
git -C "$DEST" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "error: $DEST is not a git repo — refusing (you'd have no way to review or undo)" >&2
  exit 2
}

# A clean destination is what makes this safe: `git -C <dest> checkout .` undoes
# everything this script did. Checked in BOTH modes so a dry run tells you now
# rather than letting --apply fail later — but fatal only when actually writing,
# since previewing a diff against a dirty tree is harmless and sometimes useful.
# We copy the WORKING TREE (not HEAD), so uncommitted source edits would ship.
if [ -n "$(git -C "$SRC" status --porcelain)" ]; then
  if [ "$APPLY" -eq 1 ]; then
    echo "error: the SOURCE repo has uncommitted changes. This script copies the working" >&2
    echo "       tree, not HEAD, so those would be mirrored. Commit or stash them first." >&2
    exit 2
  fi
  echo "WARNING: source repo is dirty; the working tree is what gets copied." >&2
fi

if [ -n "$(git -C "$DEST" status --porcelain)" ]; then
  if [ "$APPLY" -eq 1 ]; then
    echo "error: $DEST has uncommitted changes — commit or stash them first, so the" >&2
    echo "       mirror is reviewable as a clean diff (and revertable with 'git checkout .')." >&2
    exit 2
  fi
  echo "WARNING: $DEST has uncommitted changes. --apply will refuse until it's clean." >&2
fi

excluded_path() {
  local f=$1 e
  for e in "${EXCLUDE_PATHS[@]}"; do [ "$f" = "$e" ] && return 0; done
  return 1
}

# Strip marker blocks and pattern lines from stdin.
transform() {
  local awk_prog='
    index($0, "mirror:exclude start") { skip=1; next }
    index($0, "mirror:exclude end")   { skip=0; next }
    !skip { print }
  '
  awk "$awk_prog" | {
    if [ ${#STRIP_LINE_PATTERNS[@]} -eq 0 ]; then cat
    else
      local sed_args=() p
      for p in "${STRIP_LINE_PATTERNS[@]}"; do sed_args+=(-e "/$p/d"); done
      sed "${sed_args[@]}"
    fi
  }
}

# A symlink anywhere along a destination path would make `>` write THROUGH it,
# outside $DEST — a clean repo can still hold a committed symlink. Validate every
# path component before writing anything, so a violation aborts with nothing
# half-written rather than mid-mirror.
symlink_on_path() {  # <rel> → prints the offending component, if any
  local rel=$1 cur="$DEST" part
  local IFS='/'
  for part in $rel; do
    cur="$cur/$part"
    [ -L "$cur" ] && { printf '%s' "$cur"; return 0; }
  done
  return 1
}

skipped=0; manual=0
rels=()
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if excluded_path "$rel"; then
    printf '  EXCLUDE  %s\n' "$rel"; skipped=$((skipped+1)); continue
  fi
  [ -f "$SRC/$rel" ] || continue
  rels+=("$rel")
done < <(git -C "$SRC" ls-files)

violations=0
for rel in "${rels[@]}"; do
  if offender="$(symlink_on_path "$rel")"; then
    printf '  SYMLINK  %s → %s\n' "$rel" "$offender" >&2
    violations=$((violations+1))
  fi
done
if [ "$violations" -gt 0 ]; then
  echo "error: $violations destination path(s) traverse a symlink — refusing to write." >&2
  echo "       A write would land outside $DEST. Replace the symlink(s) with real paths." >&2
  exit 2
fi

copied=0; changed=0; stripped_files=0
written_files=()

for rel in "${rels[@]}"; do
  src_file="$SRC/$rel"

  tmp="$(mktemp)"
  transform < "$src_file" > "$tmp"
  if ! cmp -s "$src_file" "$tmp"; then
    stripped_files=$((stripped_files+1))
    printf '  STRIP    %s (%d line(s) removed)\n' "$rel" \
      "$(( $(wc -l < "$src_file") - $(wc -l < "$tmp") ))"
  fi

  dst_file="$DEST/$rel"
  if [ -f "$dst_file" ] && cmp -s "$dst_file" "$tmp"; then
    rm -f "$tmp"; copied=$((copied+1)); written_files+=("$rel"); continue
  fi

  # INBOUND GUARD: would this write delete destination-local content? Compare the
  # destination's LOCAL_TOKENS lines against the incoming content line-for-line;
  # any that the incoming file doesn't carry would be lost. Report, never write.
  if [ -f "$dst_file" ]; then
    # Multiset, not set membership: `grep -vxF -f` would treat two identical
    # destination-local lines as covered by ONE matching incoming line, so a
    # duplicate would be silently dropped. comm -23 over sorted occurrences
    # counts what's genuinely surplus in the destination. (Comparing against the
    # incoming file's *local* lines is equivalent to comparing against all of
    # them: an identical line necessarily matches LOCAL_TOKENS too.)
    # Each grep guarded: a legitimate no-match exits 1, which under
    # `set -o pipefail` would abort the whole run.
    at_risk="$( comm -23 \
                  <( { grep -iE "$LOCAL_TOKENS" "$dst_file" || true; } | sort ) \
                  <( { grep -iE "$LOCAL_TOKENS" "$tmp"      || true; } | sort ) \
                | wc -l | tr -d ' ')"
    if [ "${at_risk:-0}" -gt 0 ]; then
      printf '  MANUAL   %s (%s local line(s) would be lost — merge by hand)\n' "$rel" "$at_risk"
      manual=$((manual+1)); rm -f "$tmp"; continue
    fi
  fi

  changed=$((changed+1))
  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$(dirname "$dst_file")"
    # Write to a destination-local temp, then rename into place: atomic, and it
    # can't follow a symlink that appeared at $dst_file after validation.
    dst_tmp="$(mktemp "$(dirname "$dst_file")/.mirror.XXXXXX")"
    cat "$tmp" > "$dst_tmp"
    # Mirror the source mode in BOTH directions — only setting +x would leave a
    # destination file executable after the source stopped being so.
    if [ -x "$src_file" ]; then chmod +x "$dst_tmp"; else chmod a-x "$dst_tmp"; fi
    mv -f "$dst_tmp" "$dst_file"
  fi
  printf '  %s  %s\n' "$([ "$APPLY" -eq 1 ] && echo 'WRITE   ' || echo 'WOULD   ')" "$rel"
  rm -f "$tmp"
  copied=$((copied+1)); written_files+=("$rel")
done

# Files the destination has that the source doesn't: reported, never deleted —
# the internal repo legitimately carries its own content.
echo "---"
extra=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ -f "$SRC/$rel" ] || { printf '  DEST-ONLY %s (left alone)\n' "$rel"; extra=$((extra+1)); }
done < <(git -C "$DEST" ls-files)

# --- Guard: nothing forbidden may survive in what we mirrored ----------------
echo "---"
printf 'guard: scanning %d mirrored file(s) for /%s/i\n' "${#written_files[@]}" "$FORBIDDEN"
leaks=0
scan_root="$DEST"; [ "$APPLY" -eq 1 ] || scan_root="$SRC"   # dry run scans the transform's input
for rel in "${written_files[@]}"; do
  f="$scan_root/$rel"
  [ -f "$f" ] || continue
  if [ "$APPLY" -eq 1 ]; then hits="$(grep -inE "$FORBIDDEN" "$f" || true)"
  else hits="$(transform < "$f" | grep -inE "$FORBIDDEN" || true)"; fi
  if [ -n "$hits" ]; then
    leaks=$((leaks+1))
    printf '  LEAK  %s\n' "$rel"
    printf '%s\n' "$hits" | sed 's/^/          /'
  fi
done

echo "---"
printf 'mirror-to: %d mirrored (%d differ), %d excluded, %d stripped, %d dest-only, %d MANUAL.\n' \
  "$copied" "$changed" "$skipped" "$stripped_files" "$extra" "$manual"
[ "$manual" -eq 0 ] || echo "NOTE: $manual file(s) diverge and were NOT written — merge those by hand."

if [ "$leaks" -gt 0 ]; then
  echo "FAILED: $leaks file(s) still contain forbidden tokens (listed above)." >&2
  echo "        Wrap the prose in 'mirror:exclude start/end' markers, add the path to" >&2
  echo "        EXCLUDE_PATHS, or add a STRIP_LINE_PATTERNS regex — then re-run." >&2
  exit 1
fi
echo "guard: clean."
if [ "$APPLY" -eq 1 ]; then
  echo "Review and commit in the destination: git -C $DEST diff"
else
  echo "(dry run — nothing written. Re-run with --apply.)"
fi
