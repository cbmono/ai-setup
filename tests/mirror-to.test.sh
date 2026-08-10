#!/usr/bin/env bash
# Exercises scripts/mirror-to.sh — the guards, not the copying.
#
# Builds a throwaway SOURCE repo (with the script inside it, since it resolves
# SRC from its own location) and a throwaway DEST repo per case.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/mirror-to.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

git_q() { git -c user.email=t@example.com -c user.name=Test "$@"; }

# new_src <name> — a minimal source repo carrying the script under test.
new_src() {
  local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d/scripts" "$d/.claude/hooks"
  cp "$SCRIPT" "$d/scripts/mirror-to.sh"; chmod +x "$d/scripts/mirror-to.sh"
  printf 'shared config\n' > "$d/shared.md"
  printf '# Layout\nplain docs\n' > "$d/CLAUDE.md"
  printf '#!/bin/sh\ntrue\n' > "$d/.claude/hooks/h.sh"; chmod +x "$d/.claude/hooks/h.sh"
  ( cd "$d" && git init -q . && git_q add -A && git_q commit -qm init ) >/dev/null
  printf '%s' "$d"
}

new_dest() {
  local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"
  ( cd "$d" && git init -q . && git_q commit -qm init --allow-empty ) >/dev/null
  printf '%s' "$d"
}

check() { # <name> <expected-rc> <must-contain> <src> <dest> [flags...]
  local name="$1" want_rc="$2" needle="$3" src="$4" dest="$5"; shift 5
  local out rc
  out="$("$src/scripts/mirror-to.sh" "$dest" "$@" 2>&1)"; rc=$?
  if [ "$rc" = "$want_rc" ] && printf '%s' "$out" | grep -qF "$needle"; then
    printf '  PASS  %-56s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-56s expected rc=%s + %s, got rc=%s\n' "$name" "$want_rc" "$needle" "$rc"
    printf '%s\n' "$out" | tail -6 | sed 's/^/          /'
    fail=$((fail+1))
  fi
}

echo "== mirror-to.sh guards =="

# 1. INBOUND: a dest file carrying local-only lines is never overwritten.
src="$(new_src src1)"; dest="$(new_dest dest1)"
printf 'shared config\nalteos-only line\n' > "$dest/shared.md"
( cd "$dest" && git_q add -A && git_q commit -qm local ) >/dev/null
check "inbound guard reports divergent file as MANUAL" 0 "MANUAL   shared.md" "$src" "$dest" --apply
if grep -qF 'alteos-only line' "$dest/shared.md"; then
  printf '  PASS  %-56s\n' "local content survived --apply"; pass=$((pass+1))
else
  printf '  FAIL  %-56s\n' "local content was clobbered"; fail=$((fail+1))
fi

# 1b. DUPLICATES: two identical dest-local lines vs one incoming — set membership
#     would call this covered and silently drop one. Must be counted as surplus.
src="$(new_src src1b)"; dest="$(new_dest dest1b)"
printf 'shared config\nalteos dup\n' > "$src/shared.md"
( cd "$src" && git_q add -A && git_q commit -qm srclocal ) >/dev/null
printf 'shared config\nalteos dup\nalteos dup\n' > "$dest/shared.md"
( cd "$dest" && git_q add -A && git_q commit -qm destdup ) >/dev/null
check "duplicate dest-local line counted as at-risk" 0 "MANUAL   shared.md (1 local line" "$src" "$dest" --apply
if [ "$(grep -c 'alteos dup' "$dest/shared.md")" = "2" ]; then
  printf '  PASS  %-56s\n' "both duplicate local lines survived"; pass=$((pass+1))
else
  printf '  FAIL  %-56s\n' "a duplicate local line was dropped"; fail=$((fail+1))
fi

# 2. A dest file with no local tokens IS fast-forwarded.
src="$(new_src src2)"; dest="$(new_dest dest2)"
printf 'stale\n' > "$dest/CLAUDE.md"
( cd "$dest" && git_q add -A && git_q commit -qm stale ) >/dev/null
check "non-divergent file is written" 0 "guard: clean" "$src" "$dest" --apply
if grep -qF 'plain docs' "$dest/CLAUDE.md"; then
  printf '  PASS  %-56s\n' "non-divergent file fast-forwarded"; pass=$((pass+1))
else
  printf '  FAIL  %-56s\n' "non-divergent file not updated"; fail=$((fail+1))
fi

# 3. Execute bits sync in BOTH directions.
if [ -x "$dest/.claude/hooks/h.sh" ] && [ ! -x "$dest/shared.md" ]; then
  printf '  PASS  %-56s\n' "execute bits mirrored both ways"; pass=$((pass+1))
else
  printf '  FAIL  %-56s\n' "execute bits wrong"; fail=$((fail+1))
fi

# 4. A symlink anywhere on a destination path aborts before any write.
src="$(new_src src4)"; dest="$(new_dest dest4)"
mkdir -p "$dest/elsewhere" && ln -s "$dest/elsewhere" "$dest/.claude"
# Commit it: the realistic case is a *committed* symlink in an otherwise clean
# repo, and it keeps the dirty-dest check from firing first.
( cd "$dest" && git_q add -A && git_q commit -qm symlink ) >/dev/null
check "symlinked dest path refused" 2 "traverse a symlink" "$src" "$dest" --apply

# 5. OUTBOUND: a forbidden token in the source fails the run.
src="$(new_src src5)"; dest="$(new_dest dest5)"
printf 'this mentions yolo outside any marker\n' > "$src/leak.md"
( cd "$src" && git_q add -A && git_q commit -qm leak ) >/dev/null
check "outbound guard fails on forbidden token" 1 "LEAK  leak.md" "$src" "$dest"

# 5b. …and marker-wrapped prose is stripped instead of leaking.
src="$(new_src src5b)"; dest="$(new_dest dest5b)"
printf 'keep me\n<!-- mirror:exclude start -->\nyolo prose\n<!-- mirror:exclude end -->\ntail\n' > "$src/marked.md"
( cd "$src" && git_q add -A && git_q commit -qm marked ) >/dev/null
check "marker-wrapped forbidden prose is stripped" 0 "guard: clean" "$src" "$dest" --apply
if [ -f "$dest/marked.md" ] && ! grep -qi yolo "$dest/marked.md" && grep -qF 'keep me' "$dest/marked.md"; then
  printf '  PASS  %-56s\n' "stripped file kept its surrounding content"; pass=$((pass+1))
else
  printf '  FAIL  %-56s\n' "strip removed too much or too little"; fail=$((fail+1))
fi

# 6. A dirty SOURCE would ship uncommitted work — refuse on --apply.
src="$(new_src src6)"; dest="$(new_dest dest6)"
printf 'uncommitted\n' >> "$src/shared.md"
check "dirty source refused on --apply" 2 "SOURCE repo has uncommitted changes" "$src" "$dest" --apply
check "dirty source only warns on dry run" 0 "source repo is dirty" "$src" "$dest"

# 7. A dirty DEST is fatal only when writing.
src="$(new_src src7)"; dest="$(new_dest dest7)"
printf 'dirty\n' > "$dest/untracked.md"
( cd "$dest" && git_q add -A ) >/dev/null
check "dirty dest refused on --apply" 2 "has uncommitted changes" "$src" "$dest" --apply
check "dirty dest only warns on dry run" 0 "will refuse until it's clean" "$src" "$dest"

# 8. Excluded paths never reach the destination.
src="$(new_src src8)"; dest="$(new_dest dest8)"
mkdir -p "$src/.claude/scripts" && printf 'secret launcher\n' > "$src/.claude/scripts/deepseek-session.sh"
printf 'MIT\n' > "$src/LICENSE"
( cd "$src" && git_q add -A && git_q commit -qm excl ) >/dev/null
check "excluded paths reported" 0 "EXCLUDE  LICENSE" "$src" "$dest" --apply
if [ ! -e "$dest/.claude/scripts/deepseek-session.sh" ] && [ ! -e "$dest/LICENSE" ]; then
  printf '  PASS  %-56s\n' "excluded paths absent from dest"; pass=$((pass+1))
else
  printf '  FAIL  %-56s\n' "an excluded path was copied"; fail=$((fail+1))
fi

# 9. Dry run writes nothing at all.
src="$(new_src src9)"; dest="$(new_dest dest9)"
check "dry run reports it wrote nothing" 0 "nothing written" "$src" "$dest"
if [ ! -e "$dest/shared.md" ]; then
  printf '  PASS  %-56s\n' "dry run left dest untouched"; pass=$((pass+1))
else
  printf '  FAIL  %-56s\n' "dry run wrote files"; fail=$((fail+1))
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
