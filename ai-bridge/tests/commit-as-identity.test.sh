#!/usr/bin/env bash
#
# commit-as-identity.test.sh — WHO a commit-as.sh commit is attributed to.
#
# WHY, and why it is separate from commit-as-guard.test.sh: that file is about what
# a role may commit; this one is about the author it lands as, which is the bundle's
# provenance record. The two came apart when an instance became shareable.
# `instance.config.json` is TRACKED, so on a bundle two humans clone, its
# `authorEmail` would author BOTH clones' commits as one person — silently
# destroying the per-agent, per-human audit trail the script exists to create.
# `instance.config.local.json` is gitignored and wins for identity keys.
#
# The property that matters most here is the NEGATIVE one: with no local file,
# resolution is byte-for-byte what it was before it existed. Every single-human
# instance depends on that.
#
# Resolution order asserted below:
#   1. $CONTROL_PLANE_AUTHOR_EMAIL
#   2. "authorEmail" in instance.config.local.json   (gitignored, per-machine)
#   3. "authorEmail" in instance.config.json         (tracked, shared)
#   4. `git config user.email`
#
# `assert()` uses exit-code semantics: 0 is a PASS, matching the other harnesses.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$TPL/symlink/scripts/commit-as.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/commit-as-identity.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
eq() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then printf '  PASS  %-50s (%s)\n' "$1" "$3"; pass=$((pass+1));
  else printf '  FAIL  %-50s expected [%s] got [%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

REPO="$TMP/repo"
setup() { # [<tracked authorEmail>]
  rm -rf "$REPO"; mkdir -p "$REPO"; cd "$REPO" || exit 1
  git init -q .
  git config user.email "gitconfig@example.com"
  git config user.name "Test Human"
  if [ "$#" -ge 1 ] && [ -n "$1" ]; then
    printf '{ "authorEmail": "%s" }\n' "$1" > instance.config.json
  else
    printf '{ "org": "o" }\n' > instance.config.json
  fi
  printf 'x\n' > seed.txt
  git add -A >/dev/null; git commit -qm init
}
commit_one() { # <role> -> attributes a fresh file
  printf '%s\n' "$RANDOM$RANDOM" > mine.txt
  git add mine.txt >/dev/null
  "$SCRIPT" "$1" "test: attribute" -- mine.txt >/dev/null 2>&1
}
ae() { git log -1 --format='%ae'; }
an() { git log -1 --format='%an'; }

echo "== the tracked file, unchanged behaviour (no local override present) =="

setup tracked@example.com
commit_one project-manager
eq "tracked authorEmail is used"        "tracked@example.com" "$(ae)"
eq "…and the author NAME is the role"   "project-manager"     "$(an)"
assert "no local file was created by the run" \
  "$( [ ! -e instance.config.local.json ] && echo 0 || echo 1 )"

setup
commit_one software-engineer
eq "no authorEmail anywhere -> git config" "gitconfig@example.com" "$(ae)"
eq "…still authored as the role"           "software-engineer"     "$(an)"

setup tracked@example.com
printf 'y\n' > mine.txt; git add mine.txt >/dev/null
CONTROL_PLANE_AUTHOR_EMAIL=env@example.com "$SCRIPT" project-manager "test: env" -- mine.txt >/dev/null 2>&1
eq "the env override still wins"        "env@example.com" "$(ae)"

setup tracked@example.com
commit_one human
eq "role 'human' uses the same email"   "tracked@example.com" "$(ae)"
eq "…but the person's git name"         "Test Human"          "$(an)"

echo
echo "== the per-machine override =="

setup tracked@example.com
printf '{ "authorEmail": "local@example.com" }\n' > instance.config.local.json
commit_one project-manager
eq "local override beats the tracked file" "local@example.com" "$(ae)"

# The point of the whole exercise: two clones of ONE tracked config authoring as
# two different people.
printf '{ "authorEmail": "other@example.com" }\n' > instance.config.local.json
commit_one project-manager
eq "a second clone's override differs"     "other@example.com" "$(ae)"

setup tracked@example.com
printf '{ "authorEmail": "local@example.com" }\n' > instance.config.local.json
printf 'z\n' > mine.txt; git add mine.txt >/dev/null
CONTROL_PLANE_AUTHOR_EMAIL=env@example.com "$SCRIPT" project-manager "test: env" -- mine.txt >/dev/null 2>&1
eq "env beats the local override too"      "env@example.com" "$(ae)"

echo
echo "== absence, and a local file that answers nothing, change nothing =="

setup tracked@example.com
printf '{ "authorEmail": "local@example.com" }\n' > instance.config.local.json
commit_one project-manager
eq "with the override"                     "local@example.com"   "$(ae)"
rm -f instance.config.local.json
commit_one project-manager
eq "removing it restores the tracked value" "tracked@example.com" "$(ae)"

setup tracked@example.com
printf '{ "ownerGithubUser": "someone" }\n' > instance.config.local.json
commit_one project-manager
eq "a local file with no authorEmail defers" "tracked@example.com" "$(ae)"

setup
printf '{ "ownerGithubUser": "someone" }\n' > instance.config.local.json
commit_one project-manager
eq "…and defers all the way to git config"   "gitconfig@example.com" "$(ae)"

# An empty string is not an address: it must fall through, not be committed as "".
setup
printf '{ "authorEmail": "" }\n' > instance.config.local.json
commit_one project-manager
eq "an empty local authorEmail falls through" "gitconfig@example.com" "$(ae)"

# And with nothing at all to resolve, it refuses rather than inventing one. The
# global and system git configs are neutralised, or the developer's own
# user.email would answer step 4 and this case could never be reached.
setup
printf '{ "authorEmail": "" }\n' > instance.config.local.json
git config --unset user.email
printf 'q\n' > mine.txt; git add mine.txt >/dev/null
RC=0
OUT="$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
       "$SCRIPT" project-manager "test: none" -- mine.txt 2>&1)" || RC=$?
assert "no email anywhere -> refuses"   "$([[ $RC -ne 0 ]] && echo 0 || echo 1)"
assert "…and names the local file too"  "$(printf '%s\n' "$OUT" | grep -q 'instance.config.local.json' && echo 0 || echo 1)"

echo
echo "== the override is gitignored by the template's seed =="

assert "seed/.gitignore ignores it" \
  "$(grep -qxF 'instance.config.local.json' "$TPL/seed/.gitignore" && echo 0 || echo 1)"
# install.sh must also add it to an instance whose .gitignore predates the line —
# the seed is copied only when absent, so an older instance would never get it.
INST="$TMP/g/_ai-bridge-g"; mkdir -p "$INST"
bash "$TPL/install.sh" "$INST" >/dev/null 2>&1
grep -v 'instance.config.local.json' "$INST/.gitignore" > "$INST/.gi" && mv "$INST/.gi" "$INST/.gitignore"
bash "$TPL/install.sh" "$INST" >/dev/null 2>&1
assert "install.sh re-adds it to an older instance" \
  "$(grep -qxF 'instance.config.local.json' "$INST/.gitignore" && echo 0 || echo 1)"
assert "…and does not duplicate it on a re-run" \
  "$( [ "$( { bash "$TPL/install.sh" "$INST" >/dev/null 2>&1; grep -cxF 'instance.config.local.json' "$INST/.gitignore"; } )" = 1 ] && echo 0 || echo 1 )"
# It really is ignored in a live instance, not just listed.
( cd "$INST" && git init -q . && printf '{ "authorEmail": "x@y.z" }\n' > instance.config.local.json )
assert "git ignores the override in an instance" \
  "$( ( cd "$INST" && git check-ignore -q instance.config.local.json ) && echo 0 || echo 1 )"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
