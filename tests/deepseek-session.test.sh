#!/usr/bin/env bash
#
# deepseek-session.test.sh — the three secrecy properties of
# `.claude/scripts/deepseek-session.sh`.
#
# WHY. This script exports a third-party API key into a child process, prints a banner on
# EVERY run, and prints an environment summary on demand. That output lands in a terminal
# people paste into issues and show on shared screens, so:
#
#   · THE KEY NEVER APPEARS, not even a fragment. The version this replaces printed
#     "${KEY:0:5}…${KEY: -3}" as a "redacted preview" — eight characters of live key
#     material, every launch. A prefix is enough to correlate the credential with a leak
#     from somewhere else, and this repo's standing rule has no fragment exemption:
#     never echo, print, or log secrets or environment variables.
#   · `.env` IS PARSED, NEVER SOURCED. `set -a; . .env` would execute arbitrary shell out
#     of the one file in a repo that exists to hold secrets.
#   · `ANTHROPIC_API_KEY` IS UNSET BEFORE EXEC. It is a *different* auth header from
#     `ANTHROPIC_AUTH_TOKEN`, so an inherited one would travel to DeepSeek alongside the
#     DeepSeek token — an Anthropic credential handed to a third party.
#
# BOTH DIRECTIONS, EVERY TIME. "It doesn't print the key" passes trivially for a script
# that prints nothing, so every secrecy assertion is paired with one proving the useful
# output still happens and the key still reaches where it is supposed to: the model IDs on
# stdout, the token in the child's environment. The child is a `claude` STUB on PATH that
# dumps its own environment — the only way to assert what the exec'd process really
# receives, rather than inferring it from the banner.
#
# The launcher is opt-in and easy to leave out entirely, so an absent script is a SKIP,
# never a failure — routing a whole session to a third party is unacceptable under many
# organisations' data-governance rules, and this repo says so.
#
# ok() compares actual to expected, in that argument order — this directory's convention.
# Inverting it turns a script that fails for the wrong reason into a pass. Fixtures live
# under mktemp; no real `.env` and no real key is ever read.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/.claude/scripts/deepseek-session.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/deepseek.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
cnt() { printf '%s' "$1" | grep -c -- "$2" 2>/dev/null || true; }

if [ ! -f "$SRC" ]; then
  echo "SKIP: .claude/scripts/deepseek-session.sh absent (opt-in launcher)"
  exit 0
fi

# ---------------------------------------------------------------- the fixture
# A copy, never the real script, and a key whose first five and last three characters are
# both distinctive — so a leak of EITHER end of the old preview is caught, not just the
# whole value.
SCRIPT="$TMP/deepseek-session.sh"
cp "$SRC" "$SCRIPT"
KEY="sk-QQQQQ1111111111111111111ZZZ"
HEAD5="sk-QQ"          # what "${KEY:0:5}" used to print
TAIL3="ZZZ"            # what "${KEY: -3}" used to print
SHORT="sk-tiny"        # <= 8 chars: the length-sanity branch

# A stub `claude` that records the environment it was exec'd with. CHILD_ENV is inherited
# through the exec, so the stub can report the real child environment to this harness.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
env > "$CHILD_ENV"
STUB
chmod +x "$BIN/claude"
CHILD="$TMP/childenv"

# ------------------------------------------------- --print-env: no key, still useful
OUT="$( cd "$TMP" && DEEPSEEK_API_KEY="$KEY" bash "$SCRIPT" --print-env 2>&1 )"; RC=$?
ok "--print-env exits 0"                            "$RC" 0
ok "…prints no whole key"                           "$(cnt "$OUT" "$KEY")"   0
ok "…prints no leading key fragment"                "$(cnt "$OUT" "$HEAD5")" 0
ok "…prints no trailing key fragment"               "$(cnt "$OUT" "$TAIL3")" 0
# Non-vacuity: the flag exists to show which endpoint and which model IDs are in play —
# the header records that a wrong model ID silently costs money, so this must still print.
ok "…still reports the endpoint"                    "$(cnt "$OUT" '^ANTHROPIC_BASE_URL=https://')" 1
ok "…still reports the opus-tier model"             "$(cnt "$OUT" '^ANTHROPIC_DEFAULT_OPUS_MODEL=.')" 1
ok "…still reports the subagent model"              "$(cnt "$OUT" '^CLAUDE_CODE_SUBAGENT_MODEL=.')" 1
ok "…and names the token as set, not its value"     "$(cnt "$OUT" '^ANTHROPIC_AUTH_TOKEN=(set')" 1

# A static guard, in the spirit of snapshot.test.sh's no-GNU-escape check: the slicing
# expression must not come back, in any of its three spellings.
ok "no key-slicing expression left in the script"   "$(grep -c 'KEY_HINT\|KEY:0\|KEY: -' "$SCRIPT")" 0

# --------------------------------------------- the launch banner: printed, key-free
rm -f "$CHILD"
ERR="$( cd "$TMP" && PATH="$BIN:$PATH" CHILD_ENV="$CHILD" DEEPSEEK_API_KEY="$KEY" \
        ANTHROPIC_API_KEY="anthropic-must-not-travel" bash "$SCRIPT" 2>&1 >/dev/null )"; RC=$?
ok "a session launch exits 0"                       "$RC" 0
ok "banner prints no whole key"                     "$(cnt "$ERR" "$KEY")"   0
ok "banner prints no leading key fragment"          "$(cnt "$ERR" "$HEAD5")" 0
ok "banner prints no trailing key fragment"         "$(cnt "$ERR" "$TAIL3")" 0
ok "banner never prints the Anthropic credential"   "$(cnt "$ERR" 'anthropic-must-not-travel')" 0
# Non-vacuity: the banner is unsuppressible by design — forgetting which backend you are
# on is the failure it guards. A key-free banner must not become a missing banner.
ok "…the banner still fires"                        "$(cnt "$ERR" 'DeepSeek session')" 1
ok "…and still says this is NOT Anthropic"          "$(cnt "$ERR" 'NOT Anthropic')" 1
ok "…and still names the key's source"              "$(cnt "$ERR" 'key     :')" 1

# ------------------------------- the child environment: the two load-bearing properties
# Asserted at the real boundary. The first case is the second's non-vacuity partner: the
# DeepSeek token DOES travel, and the Anthropic one does NOT.
ok "child received the DeepSeek token"              "$(grep -c "^ANTHROPIC_AUTH_TOKEN=$KEY\$" "$CHILD")" 1
ok "child has NO ANTHROPIC_API_KEY at all"          "$(grep -c '^ANTHROPIC_API_KEY=' "$CHILD")" 0
ok "child points at the DeepSeek endpoint"          "$(grep -c '^ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic$' "$CHILD")" 1

# ------------------------------------------------- .env is parsed, never sourced
PROJ="$TMP/proj"; mkdir -p "$PROJ"
cat > "$PROJ/.env" <<EOF
EVIL=\$(touch "$PROJ/pwned")
DEEPSEEK_API_KEY=$KEY
EOF
rm -f "$PROJ/pwned"
OUT="$( cd "$PROJ" && bash "$SCRIPT" --print-env 2>&1 )"; RC=$?
ok ".env supplies the key (exit 0)"                 "$RC" 0
ok "…the file was PARSED, not sourced"              "$(yn test ! -e "$PROJ/pwned")" yes
ok "…and no fragment of that key is printed"        "$(cnt "$OUT" "$HEAD5")" 0
ok "…only the .env PATH is named, not the value"    "$(cnt "$OUT" '\.env')" 1

# ------------------------------------------------- the length check replaces the preview
# The one thing the old fragment was useful for — spotting a truncated paste — survives
# without printing any characters of the key.
OUT="$( cd "$TMP" && DEEPSEEK_API_KEY="$SHORT" bash "$SCRIPT" --print-env 2>&1 )"
ok "a too-short key is still called out"            "$(cnt "$OUT" 'check it')" 1
ok "…and even then the key is not echoed"           "$(cnt "$OUT" "$SHORT")" 0
OUT="$( cd "$TMP" && DEEPSEEK_API_KEY="$KEY" bash "$SCRIPT" --print-env 2>&1 )"
ok "a normal-length key raises no warning"          "$(cnt "$OUT" 'check it')" 0

# ------------------------------------------------- the https guard still fails closed
# Not part of the secrecy change, but it is the reason the key never rides plaintext, and
# a refactor of the surrounding block is exactly what would drop it.
OUT="$( cd "$TMP" && DEEPSEEK_BASE_URL="http://api.deepseek.com/anthropic" \
        DEEPSEEK_API_KEY="$KEY" bash "$SCRIPT" --print-env 2>&1 )"; RC=$?
ok "an http:// endpoint is refused"                 "$([ "$RC" -ne 0 ] && echo yes || echo no)" yes
ok "…and the refusal prints no key fragment"        "$(cnt "$OUT" "$HEAD5")" 0

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
