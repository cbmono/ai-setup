#!/usr/bin/env bash
#
# installer-worktree-guard.test.sh — neither installer may run from a git worktree.
#
# WHY. Both derive their source from `dirname $0` and then create symlinks pointing AT
# that path: `~/.claude/*` for the root installer, an instance's whole machinery set for
# ai-bridge/install.sh. A linked worktree is temporary by design — ExitWorktree or
# `git worktree remove` deletes it — so every symlink made from one dangles the moment it
# goes. Nothing fails at install time; the commands and hooks simply disappear later,
# which is the worst shape a failure can take.
#
# It is not hypothetical: this project's convention is to work on a branch in a worktree,
# so a checkout of the installer is routinely one `cd` away from the wrong answer. It was
# recorded as a structural hazard during a plan review and went unfixed until now.
#
# The load-bearing assertions are the two directions together. "It refuses in a worktree"
# alone would pass a script that refuses everywhere.
#
# ok() compares actual to expected, per this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wtguard.XXXXXX")"
trap 'git -C "$TMP/main" worktree remove --force "$TMP/linked" 2>/dev/null; rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-54s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-54s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# A fixture repo carrying copies of both installers, so the test never runs the real ones
# against the user's own ~/.claude.
M="$TMP/main"; mkdir -p "$M/.claude/commands" "$M/ai-bridge/seed" "$M/ai-bridge/symlink/scripts"
cp "$REPO/install.sh" "$M/install.sh"
cp "$REPO/ai-bridge/install.sh" "$M/ai-bridge/install.sh"
printf '# c\n' > "$M/.claude/commands/x.md"
printf '{}\n' > "$M/ai-bridge/seed/instance.config.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$M/ai-bridge/symlink/scripts/s.sh"
printf 'x\n' > "$M/ai-bridge/symlink/SCHEMA.md"
( cd "$M" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
git -C "$M" worktree add -q "$TMP/linked" -b wt >/dev/null 2>&1
L="$TMP/linked"

run_root()   { local src="$1" dest="$2"; CLAUDE_CONFIG_DIR="$dest" bash "$src/install.sh" >"$TMP/out" 2>&1; printf '%s' "$?"; }
run_bridge() { local src="$1" target="$2"; bash "$src/ai-bridge/install.sh" "$target" >"$TMP/out" 2>&1; printf '%s' "$?"; }

# --- the main working tree must still work (the non-vacuity half) -----------
d="$TMP/dest1"; mkdir -p "$d"
ok "root installer runs from the main tree"      "$(run_root "$M" "$d")" 0
i="$TMP/inst1"; mkdir -p "$i"
ok "ai-bridge installer runs from the main tree" "$(run_bridge "$M" "$i")" 0
ok "…and it actually stamped the instance"       "$([ -e "$i/instance.config.json" ] && echo yes || echo no)" yes

# --- a linked worktree must be refused, exit 2, before any write -----------
d2="$TMP/dest2"; mkdir -p "$d2"
rc="$(run_root "$L" "$d2")"
ok "root installer refuses from a worktree"      "$rc" 2
ok "…says why"                                   "$(grep -qi 'refusing to install from a git worktree' "$TMP/out" && echo yes || echo no)" yes
# Compare the RESOLVED path: mktemp hands back /var/... while git reports
# /private/var/... on macOS, so an unresolved grep fails on a correct message. Third time
# this exact trap has shown up in this repo (task-owner.sh, codegraph-sync.sh, here).
M_REAL="$(cd "$M" && pwd -P)"
ok "…names the main checkout to use instead"     "$(grep -q "$M_REAL" "$TMP/out" && echo yes || echo no)" yes
ok "…and wrote NOTHING into the destination"     "$(find "$d2" -mindepth 1 | wc -l | tr -d ' ')" 0

i2="$TMP/inst2"; mkdir -p "$i2"
rc="$(run_bridge "$L" "$i2")"
ok "ai-bridge installer refuses from a worktree" "$rc" 2
ok "…and stamped nothing"                        "$(find "$i2" -mindepth 1 | wc -l | tr -d ' ')" 0

# --- a plain `git init` repo is a MAIN tree, so the guard must not fire there.
# Every fixture in this suite is built that way; if the guard misread them, the whole
# harness would break rather than this one assertion, so assert it explicitly.
P="$TMP/plain"; mkdir -p "$P"; cp "$REPO/install.sh" "$P/install.sh"
mkdir -p "$P/.claude/commands"; printf '# c\n' > "$P/.claude/commands/x.md"
( cd "$P" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
d3="$TMP/dest3"; mkdir -p "$d3"
ok "a plain git repo is not treated as a worktree" "$(run_root "$P" "$d3")" 0

# --- and outside git entirely: no repo, no guard, still installs -----------
N="$TMP/nogit"; mkdir -p "$N/.claude/commands"; cp "$REPO/install.sh" "$N/install.sh"
printf '# c\n' > "$N/.claude/commands/x.md"
d4="$TMP/dest4"; mkdir -p "$d4"
rc="$(run_root "$N" "$d4")"
ok "outside a git repo it does not refuse"       "$([ "$rc" -ne 2 ] && echo yes || echo no)" yes

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
