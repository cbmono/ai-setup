#!/usr/bin/env bash
#
# rule-globs-anchored.test.sh — every `paths:` pattern in a rules file must be
# root-anchored with a leading `/`.
#
# WHY THIS IS A TEST AND NOT A CONVENTION. Measured against Claude Code v2.1.239
# with an `InstructionsLoaded` hook, reading root and nested copies of one
# filename and inspecting the hook's `load_reason` / `globs` / `trigger_file_path`:
#
#   pattern            root file   nested file
#   x.txt  *.txt  {x}  fires       FIRES        <- matches that basename anywhere
#   /x.txt             fires       no
#   ./x.txt            NO          no           <- silently dead rule
#   a/x.txt            fires       no
#   a/**               fires       FIRES        <- matched nest/a/...
#   /a/**              fires       no
#
# So `install.sh` loaded the root-config rule while editing `ai-bridge/install.sh`,
# and `.claude/hooks/**` loaded the parent-layer hook conventions while editing
# `ai-bridge/symlink/.claude/hooks/*`. Both were real, both were invisible from
# reading the frontmatter, and the OFFICIAL DOCS SAY THE OPPOSITE — their table
# claims `*.md` matches "Markdown files in the project root" and their guidance
# advises against a leading slash. A convention that contradicts the documentation
# will be "corrected" back by the next reader, so it is asserted here instead.
#
# `./` is checked separately because it is worse than unanchored: it matches
# nothing, so the rule never loads and nothing looks wrong.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# Every rules file anywhere in the repo — the parent layer's and the ones that
# ship into instances under ai-bridge/symlink/.
FILES="$(find "$REPO" -type d -name .git -prune -o -type f -path '*/.claude/rules/*.md' -print | sort)"
ok "rules files found" "$([ -n "$FILES" ] && echo yes || echo no)" yes

bad=0; dead=0; total=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # The paths: block only — stop at the closing frontmatter delimiter.
  pats="$(awk '/^paths:/{p=1;next} /^---/{p=0} p && /^[[:space:]]*-[[:space:]]/{print}' "$f")"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    pat="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*-[[:space:]]*//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//")"
    [ -n "$pat" ] || continue
    total=$((total+1))
    case "$pat" in
      ./*) dead=$((dead+1)); printf '        DEAD     %s -> %s\n' "${f#$REPO/}" "$pat" ;;
      /*)  ;;
      *)   bad=$((bad+1));  printf '        UNANCHORED %s -> %s\n' "${f#$REPO/}" "$pat" ;;
    esac
  done <<EOF
$pats
EOF
done <<EOF
$FILES
EOF

ok "at least one pattern was parsed"   "$([ "$total" -gt 0 ] && echo yes || echo no)" yes
ok "no unanchored pattern"             "$bad"  0
ok "no ./ pattern (matches nothing)"   "$dead" 0

printf '\n%s passed, %s failed  (%s pattern(s) checked)\n' "$pass" "$fail" "$total"
[ "$fail" -eq 0 ]
