#!/usr/bin/env bash
#
# claude-config-ownership.test.sh — this repo owns `~/.claude`, and every path it owns is
# actually installed by its own installer.
#
# WHY. Until now TWO installers targeted `${CLAUDE_CONFIG_DIR:-~/.claude}`: this repo's,
# and the `config/` layer of `cbmono/ai-bridge`, which was a fork of this `.claude/` tree.
# 23 of the 25 entries below were shipped by both, 14 had diverged, and which copy a
# machine ended up with was decided by whichever installer ran last — not by design. The
# fork is being retired in ai-bridge's favour of *this* repo: **ai-setup owns `~/.claude`**,
# and ai-bridge keeps only the three agents its own role agents probe for.
#
# That decision has a failure mode in each direction, and this file guards the one that
# lives here:
#
#   · ai-bridge stops installing the non-required set → if a path is missing HERE, it is
#     now installed by NOBODY. Silently: an absent agent is a failed `test -f`, an absent
#     command is a slash command that just does not exist. So the paths ai-bridge handed
#     over are enumerated below and asserted to be **installable from this repo**, not
#     merely present in it. `EXCLUDE` and the top-level linking are the parts that can
#     drop one without any file disappearing, which is why the assertion runs the real
#     installer instead of checking `git ls-files`.
#   · the two layers start shipping the same path again → the count is PINNED. A new
#     tracked, installable entry under `.claude/` fails here until it is added to the
#     manifest, which is the moment to check that ai-bridge is not shipping it too.
#
# THE ONE SANCTIONED OVERLAP is `agents/{code-architect,deep-bug-scan,plan-architect}.md`.
# ai-bridge probes for those three by absolute path and must work on a machine that never
# cloned this repo, so it keeps its own copies in `config/required/`. They are asserted to
# be in the manifest here as well: this repo is a superset, so whichever installer runs
# last, the agent exists.
#
# The fixture is a throwaway git copy of the tracked tree, so the installer's
# worktree guard does not fire and the real `~/.claude` is never touched.
#
# ok() compares actual to expected, in that argument order.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cfgown.XXXXXX")"
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
  echo "error: mktemp produced no directory (is TMPDIR set to a path that does not exist?)" >&2
  exit 1
fi
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# ---------------------------------------------------------------------- the manifest
# Every `~/.claude` path this repo owns. Grouped only for reading; order is irrelevant.
# The three marked (ai-bridge) are the sanctioned overlap described in the header.
OWNED="
agents/build-validator.md
agents/code-architect.md
agents/deep-bug-scan.md
agents/oncall-guide.md
agents/plan-architect.md
agents/stack-navigator.md
claude-defaults.md
commands/acp.md
commands/codex-handoff.md
commands/dave.md
commands/grill.md
commands/plan.md
commands/rabbit.md
commands/scan.md
commands/stack.md
commands/techdebt.md
commands/verify.md
hooks/format-on-write.sh
hooks/statusline.sh
MEMORY.md
output-styles/brief.md
scripts/codegraph-sync.sh
scripts/deepseek-session.sh
skills/README.md
skills/test-locators/SKILL.md
"
AI_BRIDGE_REQUIRED="agents/code-architect.md agents/deep-bug-scan.md agents/plan-architect.md"
# Tracked under .claude/ but deliberately NOT installed. These are the non-vacuity
# probes: the resolution check below must return "no" for each, or it is proving nothing.
NOT_INSTALLED="rules/repo-config.md settings.plugins.example.json settings.codex.example.json README.md"

# --------------------------------------------------------------------- the fixture
# A git copy of exactly what install.sh reads: itself plus the tracked .claude/ tree it
# discovers with `git ls-files`. A copy rather than the checkout, because the installer
# refuses to run from a worktree — and because nothing here may write into the real tree
# every other agent and harness is reading.
FIX="$TMP/repo"
mkdir -p "$FIX"
( cd "$REPO" && git ls-files .claude install.sh ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$FIX/$(dirname "$f")"
  cp "$REPO/$f" "$FIX/$f"
done
( cd "$FIX" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm fixture ) >/dev/null 2>&1
ok "the fixture is a git checkout"        "$([ -d "$FIX/.git" ] && echo yes || echo no)" yes

DEST="$TMP/config"; mkdir -p "$DEST"
CLAUDE_CONFIG_DIR="$DEST" bash "$FIX/install.sh" >"$TMP/out" 2>&1; rc=$?
ok "the installer exits 0"                "$rc" 0
ok "…and did not fall back to the hardcoded list" \
   "$(grep -qF 'FALLBACK_DEFAULTS' "$TMP/out" && echo yes || echo no)" no

# `-e` follows symlinks, so this answers the question that matters — "does the path
# resolve to a real file in the config dir?" — rather than "is there a link named that?".
# A whole-directory link with a missing file inside would pass the second and fail this.
installed() { [ -e "$DEST/$1" ] && [ ! -d "$DEST/$1" ] && echo yes || echo no; }

# ------------------------------------------------ 1. every owned path is installable
missing=0; total=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  total=$((total+1))
  if [ ! -f "$REPO/.claude/$rel" ]; then
    missing=$((missing+1)); printf '        NOT IN THE REPO      %s\n' "$rel"; continue
  fi
  if [ "$(installed "$rel")" != yes ]; then
    missing=$((missing+1)); printf '        NOT INSTALLED        %s\n' "$rel"
  fi
done <<EOF
$OWNED
EOF
ok "every owned path is installed into the config dir" "$missing" 0
# Pinned, so a NEW entry under .claude/ cannot slip in unlisted. When this fails after an
# addition: add the path above AND check that ai-bridge is not shipping it too.
ok "the manifest still has 25 entries"    "$total" 25

# ------------------------------------------------ 2. the check can say "no" (non-vacuity)
# Without this, "every owned path is installed" would also pass if `installed()` returned
# yes unconditionally — the failure mode that makes a whole harness decorative.
notinst=0; probed=0
for rel in $NOT_INSTALLED; do
  [ -f "$REPO/.claude/$rel" ] || continue
  probed=$((probed+1))
  [ "$(installed "$rel")" = no ] || { notinst=$((notinst+1)); printf '        UNEXPECTEDLY INSTALLED  %s\n' "$rel"; }
done
ok "…and there were excluded paths to probe"          "$([ "$probed" -ge 3 ] && echo yes || echo no)" yes
ok "a deliberately excluded path is NOT installed"    "$notinst" 0
# And one that does not exist at all, so the predicate is exercised on plain absence too.
ok "an absent path reads as not installed"            "$(installed 'commands/no-such-command.md')" no

# ------------------------------------------------ 3. the manifest matches what git tracks
# The other direction of assertion 1: a tracked, installable entry that is NOT in the
# manifest. Computed from the installer's own EXCLUDE list rather than a second copy of
# it, so the two cannot disagree.
EXCL="$(sed -n 's/^EXCLUDE="\(.*\)"$/\1/p' "$REPO/install.sh")"
ok "the installer's EXCLUDE list was found"           "$([ -n "$EXCL" ] && echo yes || echo no)" yes
printf '%s\n' $OWNED | sed '/^$/d' | sort > "$TMP/manifest"
( cd "$REPO" && git ls-files .claude ) | sed 's#^\.claude/##' | while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  top="${rel%%/*}"
  case " $EXCL " in *" $top "*) continue ;; esac
  case " $EXCL " in *" $rel "*) continue ;; esac
  printf '%s\n' "$rel"
done | sort > "$TMP/tracked"
ok "no tracked installable path is missing from the manifest" \
   "$(comm -13 "$TMP/manifest" "$TMP/tracked" | tr '\n' ' ' | sed 's/ *$//')" ""
ok "…and no manifest entry has stopped being tracked" \
   "$(comm -23 "$TMP/manifest" "$TMP/tracked" | tr '\n' ' ' | sed 's/ *$//')" ""

# ------------------------------------------------ 4. the sanctioned overlap is covered
# ai-bridge keeps its own copies of these three and probes for them by absolute path. This
# repo must ship them too, or a machine that installs only these defaults loses them.
for rel in $AI_BRIDGE_REQUIRED; do
  ok "ai-bridge's required agent is shipped here: ${rel#agents/}" "$(installed "$rel")" yes
done

# ------------------------------------------------ 5. uninstall gives every owned path back
CLAUDE_CONFIG_DIR="$DEST" bash "$FIX/install.sh" --uninstall >"$TMP/out" 2>&1
left=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ "$(installed "$rel")" = no ] || { left=$((left+1)); printf '        STILL INSTALLED  %s\n' "$rel"; }
done <<EOF
$OWNED
EOF
ok "--uninstall removes every owned path"  "$left" 0
ok "…and the real config dir was never touched" \
   "$([ "$DEST" != "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ] && echo yes || echo no)" yes

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
