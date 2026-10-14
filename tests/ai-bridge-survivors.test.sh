#!/usr/bin/env bash
#
# ai-bridge-survivors.test.sh — every `ai-bridge` mention left in a tracked file is pinned.
#
# The control panel is `loopd` now; a mention may survive only as history. Each mention is
# keyed by its path plus three words either side (never a line number) and compared, both
# ways, with tests/ai-bridge-survivors.txt. A PR that rewords a pinned line updates its row.
# This harness and that list are excluded by path: both must contain the string.
# Exit 0 when the tree and the list agree, 1 otherwise.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIST=tests/ai-bridge-survivors.txt
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-56s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# stdin: `git grep` lines (`path:text`); stdout: `path<TAB>window`, one row per mention.
mentions() {
  awk '{
    i = index($0, ":"); p = substr($0, 1, i - 1); n = split(substr($0, i + 1), w, " ")
    for (k = 1; k <= n; k++) if (tolower(w[k]) ~ /ai-bridge/) {
      out = ""
      for (j = (k > 3 ? k - 3 : 1); j <= (k + 3 < n ? k + 3 : n); j++) out = out (out == "" ? "" : " ") w[j]
      print p "\t" out
    }
  }' | LC_ALL=C sort
}

cd "$REPO" || exit 1
got="$(printf 'a/b.md:  one two three four Ai-Bridge five six seven eight\n' | mentions)"
ok "a mention is keyed by path and 3 words each side" "$got" "$(printf 'a/b.md\ttwo three four Ai-Bridge five six seven')"

found="$(git grep -I -i --no-color -e ai-bridge -- . ":(exclude)tests/ai-bridge-survivors.test.sh" ":(exclude)$LIST" | mentions)"
pinned="$(grep -v -e '^#' -e '^$' "$LIST" | LC_ALL=C sort)"
ok "git grep finds mentions in the tree" "$([ -n "$found" ] && echo yes || echo no)" yes
ok "the survivor list pins mentions"     "$([ -n "$pinned" ] && echo yes || echo no)" yes

unlisted="$(LC_ALL=C comm -23 <(printf '%s\n' "$found") <(printf '%s\n' "$pinned"))"
gone="$(LC_ALL=C comm -13 <(printf '%s\n' "$found") <(printf '%s\n' "$pinned"))"
[ -z "$unlisted" ] || printf '%s\n' "$unlisted" | sed 's/^/        UNLISTED  /'
[ -z "$gone" ]     || printf '%s\n' "$gone" | sed 's/^/        GONE      /'
ok "every ai-bridge mention is on the list" "$(printf '%s' "$unlisted" | grep -c . || true)" 0
ok "every listed mention is still there"    "$(printf '%s' "$gone" | grep -c . || true)" 0

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
