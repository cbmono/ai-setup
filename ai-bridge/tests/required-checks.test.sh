#!/usr/bin/env bash
# Exercises the delegated merge gate's precondition 1 — symlink/scripts/required-checks.sh.
#
# `gh` is replaced by a stub on PATH that answers from fixture files, so the whole
# matrix runs offline: platform-required sets, the declared-list fallback, and every
# way both are supposed to REFUSE. The refusals are the point — this gate is the only
# thing standing between an autonomous loop and a merge, so the tests that matter most
# are the ones proving it fails closed.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/symlink/scripts/required-checks.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

export FIX="$TMP/fix"
mkdir -p "$TMP/bin"

# --- gh stub -----------------------------------------------------------------
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal `gh` for required-checks.sh. Answers from $FIX; absent fixture = absent thing.
has() { local n="$1"; shift; for a in "$@"; do [ "$a" = "$n" ] && return 0; done; return 1; }

case "${1:-}" in
  pr)
    case "${2:-}" in
      view)
        [ -f "$FIX/pr_meta" ] || { echo "no PR" >&2; exit 1; }
        cat "$FIX/pr_meta" ;;
      checks)
        if has --required "$@"; then
          if [ -f "$FIX/platform_names" ]; then
            if has --jq "$@"; then cat "$FIX/platform_names"
            else echo '[{"name":"stub","bucket":"pass"}]'; fi
          else
            # Real gh: plain text on stdout, exit 1 — the case the script must not
            # confuse with "a required check failed".
            echo "no required checks reported on the 'topic' branch"; exit 1
          fi
        else
          cat "$FIX/checks" 2>/dev/null
          # Real gh exits 8 when anything is pending, 1 on failure.
          grep -qv '^pass	' "$FIX/checks" 2>/dev/null && exit 8
        fi ;;
      diff)
        [ -f "$FIX/diff_fails" ] && { echo "no diff" >&2; exit 1; }
        cat "$FIX/diff" 2>/dev/null; exit 0 ;;
      *) echo "stub: unhandled pr $2" >&2; exit 99 ;;
    esac ;;
  api)
    # Real gh prints the error BODY to stdout on a 404 and only the summary to
    # stderr — reproduce that, or the script's "did the fetch work" logic is untested.
    [ -f "$FIX/declared" ] || {
      echo '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}'
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    }
    cat "$FIX/declared" ;;
  *) echo "stub: unhandled $1" >&2; exit 99 ;;
esac
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

HEAD_SHA="0c2592f7bb98d3de9a7a181d1762dfcaf80785d9"

setup() { # start from: a readable PR, no protection, no declared list, no diff
  rm -rf "$FIX"; mkdir -p "$FIX"
  printf 'https://github.com/acme/widgets/pull/42\tmain\t%s\n' "$HEAD_SHA" > "$FIX/pr_meta"
  : > "$FIX/checks"
}

checks() { printf '%s\n' "$@" > "$FIX/checks"; }        # each arg: "bucket<TAB>name"
declared() { printf '%s\n' "$@" > "$FIX/declared"; }
platform() { printf '%s\n' "$@" > "$FIX/platform_names"; }
diff_files() { printf '%s\n' "$@" > "$FIX/diff"; }

expect() { # <name> <expected-rc> [extra args to the script...]
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$SCRIPT" 42 "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf '  PASS  %-56s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-56s expected rc=%s got rc=%s\n' "$name" "$want" "$rc"
    printf '        output: %s\n' "$(printf '%s' "$out" | head -3 | tr '\n' '|')"
    fail=$((fail+1))
  fi
  LAST_OUT="$out"
}

says() { # <name> <substring> — assert against the previous expect()'s output
  if printf '%s' "$LAST_OUT" | grep -Fq "$2"; then
    printf '  PASS  %-56s\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-56s missing %s in: %s\n' "$1" "$2" "$(printf '%s' "$LAST_OUT" | head -2 | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

echo "== required-checks gate =="

# --- nothing to enforce: the authority is not exercisable --------------------
setup; checks "pass	Build"
expect "no protection, no declared list -> not exercisable" 3
says   "  ...and says which file it looked for" "$(printf '.github/required-checks.txt')"

setup; checks "pass	Build"; declared "# only a comment" "" "   "
expect "declared list empty after parsing -> not exercisable" 3

# --- declared fallback: the happy path ---------------------------------------
setup
checks "pass	Build, Lint & Format" "pass	Unit Tests (vitest)" "pass	CodeRabbit"
declared "# what must be green before an autonomous merge" "Build, Lint & Format" "" "Unit Tests (vitest)"
expect "declared list, all green -> clear" 0
says   "  ...and reports the declared source" "source: declared"

# --- declared fallback: every way it must refuse -----------------------------
setup
checks "pass	Build, Lint & Format"
declared "Build, Lint & Format" "Unit Tests (vitest)"
expect "declared name never reported (renamed) -> refuse" 1
says   "  ...and names the drifted check" "Unit Tests (vitest): not reported"

setup; checks "fail	Build" "pass	Other"; declared "Build"
expect "declared check failing -> refuse" 1

setup; checks "pending	Build"; declared "Build"
expect "declared check pending -> refuse" 1

setup; checks "skipping	Build"; declared "Build"
expect "declared check skipped -> refuse (skipped is not passed)" 1

setup; checks "pass	Build" "fail	Build"; declared "Build"
expect "same name reported twice, one failing -> refuse" 1

# --- the gate cannot clear a PR that rewrites the gate -----------------------
setup
checks "pass	Build"; declared "Build"; diff_files "src/app.ts" ".github/required-checks.txt"
expect "PR edits the declared list -> human decision" 4

setup; checks "pass	Build"; declared "Build"; diff_files "src/app.ts" "README.md"
expect "PR touches unrelated files -> unaffected" 0

setup; checks "pass	Build"; declared "Build"; : > "$FIX/diff_fails"
expect "cannot list the PR's files -> refuse, not clear" 2

# --- platform protection wins, and is never confused with 'nothing required' --
setup
platform "Build" "E2E"
checks "pass	Build" "pass	E2E"
declared "A check nobody reports"          # would refuse if the fallback were used
expect "platform set present -> platform wins over declared" 0
says   "  ...and reports the platform source" "source: platform"

setup
platform "Build"
checks "fail	Build"
declared "Something that passes"           # must NOT rescue a failing platform check
expect "platform check failing -> refuse, no fallback to declared" 1

# --- head pinning -------------------------------------------------------------
setup; checks "pass	Build"; declared "Build"
expect "head matches the verified SHA -> clear" 0 --head "$HEAD_SHA"

setup; checks "pass	Build"; declared "Build"
expect "head moved since verification -> refuse" 1 --head "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

# --- environment failures fail closed, not open -------------------------------
setup; rm -f "$FIX/pr_meta"; declared "Build"
expect "PR unreadable -> error, never a clearance" 2

setup; checks "pass	Build"; declared "Build"
expect "unknown option -> usage error" 2 --nope

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
