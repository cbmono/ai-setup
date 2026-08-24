#!/usr/bin/env bash
#
# claude-config-ownership.test.sh — this repo owns `~/.claude`, and every path it owns is
# actually installed by its own installer.
#
# WHY. Until now TWO installers targeted `${CLAUDE_CONFIG_DIR:-~/.claude}`: this repo's,
# and the `config/` layer of `cbmono/ai-bridge`, which was a fork of this `.claude/` tree.
# 24 of the 26 entries below were shipped by both, 14 had diverged, and which copy a
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
# Read BEFORE anything here could set it: the property asserted at the end is that THIS
# file exports no CLAUDE_CONFIG_DIR, not that nobody's environment has one.
CCD_IN_ENV_AT_START="$(env | grep -c '^CLAUDE_CONFIG_DIR=' || true)"
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
settings.json
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
ok "the manifest still has 26 entries"    "$total" 26

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
# settings.json is in EXCLUDE — the generic link loop must skip it, because it is the one
# file here that can already hold permissions and plugins a human tuned by hand. But it IS
# installed, by its own branch at the end of install.sh, so it belongs in the manifest and
# therefore in this comparison too. Left out, both assertions below passed while the whole
# permissions baseline could stop being linked without a single failure.
printf '%s\n' settings.json >> "$TMP/tracked"
sort -o "$TMP/tracked" "$TMP/tracked"
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
# THE SAFETY PROPERTY THIS PAIR IS FOR: nothing here can reach the real config dir. Both
# assertions have now been wrong in opposite ways, which is worth recording because the
# second failure was caused by fixing the first.
#
#   · it began as `[ "$DEST" != "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ]`, which cannot fail —
#     CLAUDE_CONFIG_DIR is only ever a per-command prefix here, so the right-hand side is
#     always $HOME/.claude while $DEST is always under $TMP;
#   · it then became `"${CLAUDE_CONFIG_DIR+exported}"`, which is wrongly ARMED: `+` tests
#     whether the variable is SET, not whether it is exported, so this suite went red for any
#     contributor who has CLAUDE_CONFIG_DIR in their own environment — a false failure about
#     their setup, in a harness that never reads the variable.
#
# What is true and falsifiable is the DELTA: this harness must not add an exported
# CLAUDE_CONFIG_DIR to the environment a child process sees. Baselined before anything runs,
# so an inherited one is fine and an `export` added anywhere above goes red. The second
# assertion compares two variables of this file's own making ($DEST is built from $TMP), so
# it too cannot fail; replaced by the property that would actually break — every installer
# invocation carries a throwaway config dir. Add an unprefixed one and the counts diverge.
# (A stronger check — fingerprinting the real ~/.claude around the run — stays out: its
# top-level entries change on their own while Claude Code is running, so it would flake.)
ok "…and this harness exported no CLAUDE_CONFIG_DIR" \
   "$(env | grep -c '^CLAUDE_CONFIG_DIR=' || true)" "$CCD_IN_ENV_AT_START"
# The `[$]` keeps each pattern from matching its own line.
ok "…and every installer invocation names a throwaway one" \
   "$(grep -c 'bash "[$]FIX' "$0" | tr -d ' ')" \
   "$(grep -c 'CLAUDE_CONFIG_DIR="[$][A-Za-z0-9]*" bash "[$]FIX' "$0" | tr -d ' ')"

# ------------------------------------------------ 6. settings.json in the handover
# THE ORDER-INDEPENDENCE DEFECT THIS GROUP EXISTS FOR. `cbmono/ai-bridge` used to link
# ~/.claude/settings.json into its own checkout and has stopped. On a machine in that
# state, running ai-setup FIRST and then ai-bridge's refresh left the file installed by
# NOBODY: this installer saw a settings.json, said "already exists, left alone", and
# ai-bridge's next `--config` retired its own now-dangling link. Gone with it: the whole
# permissions.deny block (.env*, ssh keys, .aws/credentials, sudo, rm -rf ~), statusLine,
# outputStyle and the PostToolUse hook — recoverable only by re-running this installer, and
# nothing prompts that. The rule that fixes it: A SYMLINK IS NOT YOUR settings.json.
#
# AND WHY THE ASSERTIONS BELOW ARE PRESENCE CHECKS, NOT DANGLING-LINK COUNTS. The evidence
# offered twice for "the two installers compose in either order" was `0 dangling` — and
# that number cannot see this defect at all: a path that was never linked is ABSENT, not
# dangling. The failing run scored 0 dangling and exit 0 with the file gone. So each
# assertion here reads the path itself (`sj_dest`, `-e`), and (c) mutation-tests the branch
# they depend on so none of them can pass for an incidental reason. Same reason the ai-bridge
# side asserts by SET MEMBERSHIP over CONFIG_MANAGED_TOPS rather than by sweeping for
# dangling links: see its docs/claude-config-ownership.md, point 6.
sj_dest() { readlink "$1/settings.json" 2>/dev/null; }
# The installer derives its own root with `cd && pwd`, which normalises away the trailing
# slash $TMPDIR happily carries — so a link it creates is spelled with the NORMALISED path
# and comparing against "$FIX/..." fails on a machine whose TMPDIR ends in `/`.
FIXR="$(cd "$FIX" && pwd)"

# (a) a RESOLVING link into some other checkout — the real handover state.
D6="$TMP/cfg-foreign"; mkdir -p "$D6" "$TMP/other"; OTHERR="$(cd "$TMP/other" && pwd)"
printf '{"permissions":{"deny":["Read(./.env)"]},"outputStyle":"Other"}\n' > "$TMP/other/settings.json"
ln -s "$OTHERR/settings.json" "$D6/settings.json"
CLAUDE_CONFIG_DIR="$D6" bash "$FIX/install.sh" >"$TMP/out6" 2>&1
ok "a foreign settings.json link: exits 0"  "$?" 0
ok "…is replaced by THIS repo's"            "$(sj_dest "$D6")" "$FIXR/.claude/settings.json"
ok "…the old link is kept as a .bak"        "$(find "$D6" -maxdepth 1 -name 'settings.json.bak.*' | wc -l | tr -d ' ')" 1
ok "…and the other checkout is untouched"   "$(cat "$OTHERR/settings.json")" \
   '{"permissions":{"deny":["Read(./.env)"]},"outputStyle":"Other"}'
ok "…so no path is installed by nobody"     "$([ -e "$D6/settings.json" ] && echo yes || echo no)" yes

# (a2) a DANGLING link — no .bak, because a backup of a link that resolves to nothing is
# pure debris. Relinked in place, and the path it named is still printed.
D6b="$TMP/cfg-dangling"; mkdir -p "$D6b"
ln -s "$TMP/gone/settings.json" "$D6b/settings.json"
CLAUDE_CONFIG_DIR="$D6b" bash "$FIX/install.sh" >"$TMP/out6b" 2>&1
ok "a dangling link is relinked"            "$(sj_dest "$D6b")" "$FIXR/.claude/settings.json"
ok "…with no .bak left behind"              "$(find "$D6b" -maxdepth 1 -name 'settings.json.bak.*' | wc -l | tr -d ' ')" 0

# (b) a REAL file — the property that must NOT regress. Yours stays yours.
D7="$TMP/cfg-real"; mkdir -p "$D7"
printf '{"permissions":{"allow":["Bash(mine:*)"]}}\n' > "$D7/settings.json"
CLAUDE_CONFIG_DIR="$D7" bash "$FIX/install.sh" >"$TMP/out7" 2>&1
ok "a REAL settings.json is not replaced"   "$(sj_dest "$D7")" ""
ok "…and still holds your own rule"         "$(grep -c 'Bash(mine:\*)' "$D7/settings.json" | tr -d ' ')" 1

# (c) non-vacuity for (a): the same fixture with the ADOPT branch removed must fail it.
# Proves the assertions above are held by that branch and not by something incidental.
FIX2="$TMP/repo-nofix"; cp -R "$FIX" "$FIX2"
# The pre-fix condition, restored by narrowing the branch back to DANGLING links only.
sed -e 's#^elif \[ -L "\$DEST/settings\.json" \]; then$#elif [ -L "$DEST/settings.json" ] \&\& [ ! -e "$DEST/settings.json" ]; then#' \
    "$FIX/install.sh" > "$FIX2/install.sh"
ok "the mutation applied"                   "$(grep -c '! -e "\$DEST/settings.json" \]; then' "$FIX2/install.sh" | tr -d ' ')" 1
D8="$TMP/cfg-nofix"; mkdir -p "$D8"
ln -s "$OTHERR/settings.json" "$D8/settings.json"
CLAUDE_CONFIG_DIR="$D8" bash "$FIX2/install.sh" >"$TMP/out8" 2>&1
ok "without the adopt branch it declines"   "$(sj_dest "$D8")" "$OTHERR/settings.json"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
