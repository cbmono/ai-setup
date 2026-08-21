#!/usr/bin/env bash
#
# validate-bundle.sh — check that this bundle is machine-readable from frontmatter
# alone: every concept document has a known `type`, a `status` in that type's enum,
# a `timestamp`, and every structural cross-reference resolves.
#
#   Usage: scripts/validate-bundle.sh [--strict]
#          --strict   treat warnings as failures too
#
# WHY THIS EXISTS, AND WHAT IT DELIBERATELY DOES NOT CHECK.
# Measured across three live instances (2026-08-21, ~570 documents) BEFORE it was
# written, because a validator that reports problems nobody has is one people learn
# to ignore:
#   · status enums:      23 violations, all in `knowledge/`. The first measurement
#                        reported ZERO and was wrong: it sampled only Objective,
#                        Project, Phase and Task and never looked at Finding or
#                        Service. Findings carry `open` and `active` where the enum
#                        is `current|superseded`, and six Services carry `current`
#                        where theirs is `active|deprecated` — someone applied the
#                        Finding enum to a Service. Enum checking is NOT a
#                        future-typo guard; it is catching live drift, and the drift
#                        is concentrated exactly where nobody was looking.
#   · missing timestamp: 16 documents across two instances.
#   · frontmatter refs:  15 of 115 dangling (13%). This was the motivating rot. `/close-project` removes a project
#                        folder by design, so a surviving `depends_on:` or
#                        `objective:` pointing into it breaks silently.
#   · `id` / `updated`:  NOT required, and not added. No document in any instance
#                        carried either. The file path is already the identifier —
#                        a duplicate `id` can only drift from it — and OKF names the
#                        time field `timestamp`, so renaming it would diverge from
#                        the spec this bundle claims to follow. The v2 plan asked
#                        for both; the data said no.
#
# WHAT COUNTS AS A CONCEPT DOCUMENT. Only the schema-defined locations:
# `objectives/*.md`, `projects/*/project.md`, `projects/*/phases/*.md`,
# `projects/*/tasks/*.md`, and `knowledge/<kind>/*.md`. Everything else —
# `index.md`, `log.md`, `sources/`, `deliverables/`, a doc a human dropped into a
# project — is content or navigation. The first version of this script validated
# those too and buried 6 real errors under 77 warnings, which is exactly how a
# validator teaches people to ignore it.
#
# BODY PROSE IS NOT CHECKED. A body may cite a closed project's task as history —
# that is the record working as intended. Only FRONTMATTER references, which
# machinery actually follows, must resolve.
#
# `artifacts:` WARNS rather than fails: a research task legitimately declares a
# deliverable before it is written.
#
# Run from a control-panel instance root. Generic: no org/repo/path literals.
# Bash + awk only — no jq, no python — so it ships into every instance unchanged.
#
# Verified by ai-bridge/tests/validate-bundle.test.sh.
set -euo pipefail

STRICT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) echo "usage: $0 [--strict]" >&2; exit 2 ;;
  esac
  shift
done

[[ -f SCHEMA.md && -f instance.config.json ]] || {
  echo "validate-bundle: run from a control-panel instance root (SCHEMA.md + instance.config.json)." >&2
  exit 2
}

# Closed enums, per type. SCHEMA.md is the contract; this is its enforcement, so
# keep the two in step.
enum_for() {
  case "$1" in
    Objective) echo "active paused achieved dropped" ;;
    Project)   echo "active paused done" ;;
    Phase)     echo "not-started active done" ;;
    Task)      echo "draft ready in-progress in-review blocked cancelled done" ;;
    Finding)   echo "current superseded" ;;
    Service)   echo "active deprecated" ;;
    *)         echo "" ;;
  esac
}

KNOWN_TYPES="Objective Project Phase Task Agent Service Finding Team Runbook Reference"

errors=0; warns=0; checked=0

# Print the frontmatter block. Exit 3 when the file does not open with `---`, and
# exit 4 when it opens but never closes — an unterminated block used to return the
# whole file, so a malformed document with valid-looking fields passed validation.
frontmatter() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

# Collect path references from the given frontmatter keys, in BOTH YAML forms:
#   depends_on: [ /a.md, /b.md ]     (inline)
#   depends_on:                       (block)
#     - /a.md
# The line-based first version saw only the inline form, so a valid block sequence
# was silently skipped and the validator could report success while a structural
# reference dangled. No instance uses block style today; nothing forbids it.
refs_for() { # <frontmatter> <key-alternation> <path-regex>
  printf '%s\n' "$1" | awk -v keys="$2" '
    $0 ~ "^(" keys "):" { inblock=1; rest=$0; sub(/^[^:]*:/, "", rest); print rest; next }
    inblock && /^[[:space:]]+-[[:space:]]*/ { print; next }
    inblock && /^[[:space:]]*$/ { next }
    /^[^[:space:]]/ { inblock=0 }
  ' | grep -oE "$3" | sort -u || true
}
fail() { printf '  ERROR  %s\n         %s\n' "$1" "$2"; errors=$((errors+1)); }
warn() { printf '  WARN   %s\n         %s\n' "$1" "$2"; warns=$((warns+1)); }

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
  fm_rc=0
  fm="$(frontmatter "$file")" || fm_rc=$?
  if [[ $fm_rc -eq 3 ]] || { [[ $fm_rc -eq 0 ]] && [[ -z "$fm" ]]; }; then
    fail "$rel" "no YAML frontmatter, but it sits in a schema-defined location"
    continue
  fi
  if [[ $fm_rc -eq 4 ]]; then
    fail "$rel" "frontmatter opens with --- but is never closed by a second ---"
    continue
  fi
  checked=$((checked+1))

  type="$(printf '%s\n' "$fm" | sed -n 's/^type:[[:space:]]*//p' | head -1)"
  if [[ -z "$type" ]]; then
    fail "$rel" "missing required field: type"
    continue
  fi
  case " $KNOWN_TYPES " in
    *" $type "*) : ;;
    *) fail "$rel" "unknown type '$type' (known: $KNOWN_TYPES)" ;;
  esac

  allowed="$(enum_for "$type")"
  if [[ -n "$allowed" ]]; then
    status="$(printf '%s\n' "$fm" | sed -n 's/^status:[[:space:]]*//p' | head -1 | sed 's/[[:space:]]*#.*//;s/[[:space:]]*$//')"
    if [[ -z "$status" ]]; then
      fail "$rel" "type $type requires a status (one of: $allowed)"
    else
      case " $allowed " in
        *" $status "*) : ;;
        *) fail "$rel" "status '$status' is not valid for type $type (one of: $allowed)" ;;
      esac
    fi
  fi

  if ! printf '%s\n' "$fm" | grep -q '^timestamp:[[:space:]]*[^[:space:]]'; then
    fail "$rel" "missing required field: timestamp"
  fi

  structural="$(refs_for "$fm" 'objective|project|phase|depends_on' '/(objectives|projects|knowledge|agents)/[A-Za-z0-9._/-]+[.]md')"
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ -e ".$ref" ]] || fail "$rel" "dangling reference: $ref"
  done <<< "$structural"

  declared="$(refs_for "$fm" 'artifacts' '/projects/[A-Za-z0-9._/-]+[.]md')"
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ -e ".$ref" ]] || warn "$rel" "declared artifact does not exist yet: $ref"
  done <<< "$declared"
done <<< "$FILE_LIST"

echo "---"
printf 'validate-bundle: %d documents checked, %d errors, %d warnings.\n' "$checked" "$errors" "$warns"
[[ $errors -eq 0 ]] || exit 1
if [[ $STRICT -eq 1 && $warns -gt 0 ]]; then
  echo "(--strict: warnings are failures)"
  exit 1
fi
exit 0
