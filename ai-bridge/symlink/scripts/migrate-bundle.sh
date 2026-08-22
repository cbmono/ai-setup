#!/usr/bin/env bash
#
# migrate-bundle.sh — repair the mechanical schema violations `validate-bundle.sh`
# reports, in this instance's bundle.
#
#   Usage: scripts/migrate-bundle.sh            # report what it WOULD change (default)
#          scripts/migrate-bundle.sh --apply    # write the changes
#
# REPORT-ONLY BY DEFAULT, for the same reason `prune-worktrees.sh` is: a script that
# edits many files should not be one keystroke away from doing it. Read the report,
# then re-run with --apply.
#
# WHAT IT FIXES (mechanical — one right answer, no judgement):
#   · Finding `status` of exactly `open` or `active` — both mean "still applies" ⇒
#     `current`. A Finding with NO status ⇒ `current`.
#   · Service `status` of exactly `current` — the Finding enum applied to a Service
#     ⇒ `active`. A Service with NO status ⇒ `active`.
#   The mapping list is CLOSED. Any other unrecognised value — a typo, or a lifecycle
#   state this script has never seen — is reported for a human, never normalised: the
#   original carries a meaning the script cannot read, and overwriting it would
#   destroy that meaning while looking like a repair. Same rule as the timestamp.
#   · A missing `timestamp`. Filled from **git**: the author date of the commit that
#     added the file. That is real provenance, not a guess. A file git does not know
#     is reported and skipped — inventing a date would be worse than leaving the
#     error, because a wrong timestamp is indistinguishable from a right one.
#
# WHAT IT REFUSES TO FIX (needs a human):
#   · Dangling structural references. Whether to drop a `depends_on:` depends on
#     whether the task it pointed at finished, and once its project folder is gone
#     that state is unknowable from the bundle. `/close-project` step 6 is where this
#     is decided, with the source task still readable. Reported, never touched.
#   · A missing or unknown `type`, and absent frontmatter. These say the document is
#     not what its location claims, which is a content decision.
#
# Idempotent: a second run finds nothing. Safe to run before `validate-bundle.sh` and
# again after.
#
# Run from a control-panel instance root. Bash + awk + git only.
# Verified by ai-bridge/tests/migrate-bundle.test.sh.
set -euo pipefail

APPLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) echo "usage: $0 [--apply]" >&2; exit 2 ;;
  esac
  shift
done

[[ -f SCHEMA.md && -f instance.config.json ]] || {
  echo "migrate-bundle: run from a control-panel instance root (SCHEMA.md + instance.config.json)." >&2
  exit 2
}

fixed=0; skipped=0; human=0

act() { # <file> <what>
  if [[ $APPLY -eq 1 ]]; then printf '  FIXED    %s\n           %s\n' "$1" "$2"
  else printf '  WOULD FIX %s\n           %s\n' "$1" "$2"; fi
  fixed=$((fixed+1))
}
hold() { printf '  HUMAN    %s\n           %s\n' "$1" "$2"; human=$((human+1)); }
skip() { printf '  SKIPPED  %s\n           %s\n' "$1" "$2"; skipped=$((skipped+1)); }

# A temporary file BESIDE the target, carrying the target's mode.
#
# Two reasons it cannot live in $TMPDIR: `mktemp` creates mode 0600, and renaming
# that over a document would silently make every repaired file 0600; and if $TMPDIR
# is on another filesystem, `mv` degrades to copy-and-remove, so an interruption can
# leave a half-written document. Same-directory rename is atomic and keeps the mode.
temp_beside() { # <file>
  local f="$1" d t m
  d="$(dirname "$f")"
  t="$(mktemp "$d/.migrate-bundle.XXXXXX")"
  m="$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null || echo 644)"
  chmod "$m" "$t" 2>/dev/null || true
  printf '%s\n' "$t"
}

# Replace a frontmatter scalar in place, only inside the frontmatter block.
set_field() { # <file> <key> <value>
  local f="$1" k="$2" v="$3" tmp
  tmp="$(temp_beside "$f")"
  awk -v key="$k" -v val="$v" '
    BEGIN { n=0; done=0 }
    /^---$/ { n++; print; next }
    n==1 && !done && $0 ~ "^" key ":" { print key ": " val; done=1; next }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# Insert a frontmatter scalar just before the closing delimiter.
add_field() { # <file> <key> <value>
  local f="$1" k="$2" v="$3" tmp
  tmp="$(temp_beside "$f")"
  awk -v key="$k" -v val="$v" '
    BEGIN { n=0 }
    /^---$/ { n++; if (n==2) print key ": " val; print; next }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

field() { # <file> <key>
  awk -v key="$2" '
    NR==1 && $0!="---" { exit }
    /^---$/ { n++; if (n==2) exit; next }
    n==1 && $0 ~ "^" key ":" { sub("^" key ":[[:space:]]*", ""); sub(/[[:space:]]*#.*/, ""); print; exit }
  ' "$1"
}

git_added_date() { # <file> -> ISO 8601, or empty
  git log --diff-filter=A --format=%aI -1 -- "$1" 2>/dev/null | head -1
}

collect_files() {
  find ./objectives -maxdepth 1 -name '*.md' 2>/dev/null || true
  find ./projects -maxdepth 2 -name 'project.md' 2>/dev/null || true
  find ./projects -path '*/phases/*.md' 2>/dev/null || true
  find ./projects -path '*/tasks/*.md' 2>/dev/null || true
  find ./knowledge -mindepth 2 -maxdepth 2 -type f -name '*.md' 2>/dev/null || true
}

FILE_LIST="$(collect_files | grep -vE '/(index|log)\.md$' | sort -u || true)"

while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  rel="${file#./}"
  head -1 "$file" | grep -q '^---$' || { skip "$rel" "no frontmatter — a content decision, not a migration"; continue; }

  type="$(field "$file" type)"
  [[ -n "$type" ]] || { skip "$rel" "no type — a content decision, not a migration"; continue; }
  status="$(field "$file" status)"

  case "$type" in
    Finding)
      case "$status" in
        current|superseded) : ;;
        "")            act "$rel" "Finding has no status -> current"; [[ $APPLY -eq 0 ]] || add_field "$file" status current ;;
        open|active)   act "$rel" "Finding status '$status' -> current"; [[ $APPLY -eq 0 ]] || set_field "$file" status current ;;
        *)             hold "$rel" "Finding status '$status' is not a mapping this script knows — decide it by hand" ;;
      esac ;;
    Service)
      case "$status" in
        active|deprecated) : ;;
        "")        act "$rel" "Service has no status -> active"; [[ $APPLY -eq 0 ]] || add_field "$file" status active ;;
        current)   act "$rel" "Service status 'current' -> active"; [[ $APPLY -eq 0 ]] || set_field "$file" status active ;;
        *)         hold "$rel" "Service status '$status' is not a mapping this script knows — decide it by hand" ;;
      esac ;;
  esac

  if [[ -z "$(field "$file" timestamp)" ]]; then
    added="$(git_added_date "$file")"
    if [[ -n "$added" ]]; then
      act "$rel" "timestamp missing -> $added (author date of the commit that added it)"
      [[ $APPLY -eq 0 ]] || add_field "$file" timestamp "$added"
    else
      skip "$rel" "timestamp missing and git does not know this file — refusing to invent a date"
    fi
  fi

  # Structural refs: reported for a human, never rewritten here.
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ -e ".$ref" ]] || hold "$rel" "dangling reference $ref — decide it in /close-project step 6, not here"
  done < <(awk '
      NR==1 && $0!="---" { exit }
      /^---$/ { n++; if (n==2) exit; next }
      n==1 && /^(objective|project|phase|depends_on):/ { inblock=1; print; next }
      n==1 && inblock && /^[[:space:]]+-[[:space:]]*/ { print; next }
      n==1 && /^[^[:space:]]/ { inblock=0 }
    ' "$file" | grep -oE '/(objectives|projects|knowledge|agents)/[A-Za-z0-9._/-]+[.]md' | sort -u || true)
done <<< "$FILE_LIST"

echo "---"
if [[ $APPLY -eq 1 ]]; then
  printf 'migrate-bundle: %d fixed, %d left for a human, %d skipped.\n' "$fixed" "$human" "$skipped"
  echo "Now run: scripts/validate-bundle.sh"
else
  printf 'migrate-bundle: %d would be fixed, %d need a human, %d skipped. (report only — nothing changed)\n' \
    "$fixed" "$human" "$skipped"
  echo "Re-run with --apply to write these changes."
fi
