#!/usr/bin/env bash
#
# skills-allowlisted.test.sh — only deliberately-shipped skills may be tracked, and a
# tracked symlink must resolve inside the repo.
#
# WHY. `.claude/skills/` is a DROP-IN directory: installing any third-party skill creates
# a subdirectory here. With a bare `!.claude/skills/` re-include in .gitignore, a single
# `git add -A -- .claude` swept four of them into this PUBLIC repo — `graphify`, plus
# `computer-use`, `orca-cli` and `orchestration` as symlinks to `../../.agents/skills/…`,
# a path that exists under ~/.claude but NOT here, so the repo shipped three dead links.
#
# The blast radius is what makes it a test rather than a note: `install.sh` discovers what
# to link with `git ls-files .claude`, so anything tracked here is symlinked into EVERY
# consumer's ~/.claude/skills/ — a third-party skill they never chose, and three links
# that resolve to nothing.
#
# Shipping a skill is now an explicit act: add a `!` line to .gitignore. This test is the
# thing that notices when it happens by accident instead.
#
# ok() compares actual to expected, per this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-56s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# The skills this repo has decided to ship. Adding one here is a deliberate choice and
# should be a reviewed diff — which is the whole point.
ALLOWED="README.md test-locators"

cd "$REPO"
tracked="$(git ls-files .claude/skills/ | sed 's#^\.claude/skills/##' | cut -d/ -f1 | sort -u)"
ok "something under .claude/skills is tracked" "$([ -n "$tracked" ] && echo yes || echo no)" yes

unexpected=0
while IFS= read -r e; do
  [ -n "$e" ] || continue
  case " $ALLOWED " in *" $e "*) ;; *) unexpected=$((unexpected+1)); printf '        UNEXPECTED  %s\n' "$e" ;; esac
done <<EOF
$tracked
EOF
ok "no unexpected skill is tracked" "$unexpected" 0

# A tracked symlink whose target sits outside the repo can never resolve for a consumer.
broken=0; escaping=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -L "$f" ] || continue
  [ -e "$f" ] || { broken=$((broken+1)); printf '        BROKEN LINK  %s -> %s\n' "$f" "$(readlink "$f")"; }
  case "$(readlink "$f")" in /*|*../../*) escaping=$((escaping+1)); printf '        ESCAPES REPO  %s -> %s\n' "$f" "$(readlink "$f")" ;; esac
done <<EOF
$(git ls-files .claude/skills/)
EOF
ok "no tracked skill symlink is broken"  "$broken"   0
ok "no tracked skill symlink escapes"    "$escaping" 0

# And the gitignore must actually ignore a fresh drop-in, not merely happen to have none.
probe=".claude/skills/zz-probe-$$"
mkdir -p "$probe" && printf 'x\n' > "$probe/SKILL.md"
ignored=$(git check-ignore -q "$probe/SKILL.md" && echo yes || echo no)
rm -rf "$probe"
ok "a fresh drop-in skill is gitignored" "$ignored" yes

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
