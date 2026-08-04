#!/usr/bin/env bash
#
# deepseek-session.sh — run a Claude Code session against DeepSeek instead of Anthropic.
#
# This is a BACKEND SUBSTITUTION, not a delegation helper. Unlike the opt-in Codex
# integration (where Claude stays the driver and hands specific tasks to a separate
# `codex` process), this replaces the model behind Claude Code itself: the whole agent
# loop — your prompts, file contents, tool results, diffs — is served by DeepSeek.
#
# Nothing here is a default. Normal `claude` is untouched; this only affects the
# session it launches, via environment variables in that process. Your Anthropic
# credentials on disk are never read, written, or invalidated.
#
# Deliberately minimal and self-contained: no proxy, no third-party code in the path
# that holds your API key. Compare github.com/aattaran/deepclaude, which adds a local
# proxy for live backend switching and cost tracking — more features, but ~2k lines of
# unpinned third-party code (that repo publishes no tags or releases) wrapping your
# credentials. If you want those features, install it separately and deliberately.
#
# Usage:  deepseek-session.sh [--help] [--print-env] [claude args...]

set -euo pipefail

# ---- Config (override via environment) ------------------------------------
# Verified against DeepSeek's Anthropic-compatibility docs:
#   https://api-docs.deepseek.com/guides/anthropic_api
#   https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code
# Overridable because model IDs outlive scripts, and a stale one fails silently
# rather than loudly: DeepSeek maps an unrecognised model name to a working model
# instead of erroring. Verified 2026-08-04 — an unknown name resolved to
# deepseek-v4-pro, i.e. the EXPENSIVE tier (DeepSeek's docs claim it falls back to
# flash; it did not). So a wrong ID here quietly inflates cost and never errors.
# Bump these deliberately; don't expect a failure to tell you they went stale.
BASE_URL="${DEEPSEEK_BASE_URL:-https://api.deepseek.com/anthropic}"
MODEL_PRO="${DEEPSEEK_MODEL_PRO:-deepseek-v4-pro}"
MODEL_FLASH="${DEEPSEEK_MODEL_FLASH:-deepseek-v4-flash}"
# Subagents get the cheap tier by default (DeepSeek's own recommendation). That's
# right for an ordinary session, but wrong wherever subagents do the real work —
# an ai-bridge instance dispatches its role agents as subagents, so leaving them
# on flash would quietly downgrade every PR-writing agent. Separate knob so such a
# setup can raise just the subagent tier without also moving the haiku tier.
SUBAGENT_MODEL="${DEEPSEEK_SUBAGENT_MODEL:-$MODEL_FLASH}"
# ---------------------------------------------------------------------------

usage() {
  cat <<'USAGE'
deepseek-session.sh — run one Claude Code session against DeepSeek.

  deepseek-session.sh                 start a session on DeepSeek
  deepseek-session.sh --print-env     show the env it would set (key redacted), then exit
  deepseek-session.sh --help          show this help

Any other arguments are passed through to `claude` verbatim.

API key, first match wins:
  1. $DEEPSEEK_API_KEY already exported
  2. DEEPSEEK_API_KEY= in ./.env
  3. DEEPSEEK_API_KEY= in <git repo root>/.env

The .env file is PARSED, never sourced — nothing in it is executed as shell.

Overrides: DEEPSEEK_BASE_URL (must be https://), DEEPSEEK_MODEL_PRO,
           DEEPSEEK_MODEL_FLASH, DEEPSEEK_SUBAGENT_MODEL (defaults to the flash
           tier; raise it where subagents do the real work, e.g. an ai-bridge
           instance whose role agents open PRs).

Everything in the session goes to DeepSeek. Check what the code you are pointing
it at is allowed to leave your infrastructure before you use it.
USAGE
}

PRINT_ENV=0
CLAUDE_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --print-env) PRINT_ENV=1; shift ;;
    --) shift; CLAUDE_ARGS+=("$@"); break ;;
    *) CLAUDE_ARGS+=("$1"); shift ;;
  esac
done

# The endpoint is exported alongside the API key, so an http:// value (a typo, or a
# stale DEEPSEEK_BASE_URL in a shell profile) would put that key on the wire in
# plaintext. Require https and fail closed. `https://?*` also rejects a bare scheme
# and a hostname with no scheme, which Claude Code would otherwise turn into a
# confusing error far from the cause. Validated here rather than at assignment so
# `--help` still works with a bad value, and before any export so --print-env sees it.
# NB this deliberately forbids http://127.0.0.1 local proxies — this script has no
# proxy support (see the header); add a loopback case here if that ever changes.
case "$BASE_URL" in
  https://?*) : ;;
  *)
    echo "error: DEEPSEEK_BASE_URL must be an https:// URL (got: '$BASE_URL')." >&2
    echo "       Anything else would send your API key unencrypted." >&2
    exit 1
    ;;
esac

# Extract one KEY=value from a .env file WITHOUT executing it. `set -a; . .env`
# would run arbitrary shell from a file that exists to hold secrets; a stray
# command substitution in there would execute silently. Parse, don't source.
read_key_from_file() {
  local file="$1" line
  [ -f "$file" ] || return 1
  line="$(grep -E '^[[:space:]]*(export[[:space:]]+)?DEEPSEEK_API_KEY[[:space:]]*=' "$file" 2>/dev/null | tail -1)" || return 1
  [ -n "$line" ] || return 1
  line="${line#*=}"
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  # A quoted value ends at its closing quote — anything after it (typically a
  # trailing comment) is not part of the key. An unquoted value ends at the first
  # '#'. Order matters: stripping quotes before the comment leaves the quotes
  # embedded in the token, which surfaces as a baffling 401 rather than an error.
  case "$line" in
    '"'*) line="${line#\"}"; line="${line%%\"*}" ;;
    "'"*) line="${line#\'}"; line="${line%%\'*}" ;;
    *)    line="${line%%#*}"
          line="$(printf '%s' "$line" | sed -e 's/[[:space:]]*$//')" ;;
  esac
  [ -n "$line" ] || return 1
  printf '%s' "$line"
}

KEY="${DEEPSEEK_API_KEY:-}"
KEY_SOURCE="\$DEEPSEEK_API_KEY (exported)"

if [ -z "$KEY" ]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  for candidate in "$PWD/.env" ${REPO_ROOT:+"$REPO_ROOT/.env"}; do
    if KEY="$(read_key_from_file "$candidate")"; then
      KEY_SOURCE="$candidate"
      break
    fi
    KEY=""
  done
fi

if [ -z "$KEY" ]; then
  echo "error: no DeepSeek API key found." >&2
  echo "       Export DEEPSEEK_API_KEY, or add 'DEEPSEEK_API_KEY=sk-...' to ./.env" >&2
  echo "       (.env is gitignored in this repo — keep it that way)." >&2
  exit 1
fi

# Redacted preview — never print the key itself, this banner is shown every run
# and often ends up pasted into issues or shared terminals.
if [ "${#KEY}" -gt 8 ]; then
  KEY_HINT="${KEY:0:5}…${KEY: -3}"
else
  KEY_HINT="(short — check it)"
fi

export ANTHROPIC_BASE_URL="$BASE_URL"
export ANTHROPIC_AUTH_TOKEN="$KEY"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL_PRO"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL_PRO"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL_FLASH"
# The installed CLI reads a FABLE tier too (confirmed present in 2.1.221), which
# DeepSeek's setup docs omit. Left unset, a `fable`-tier request would fall through
# to DeepSeek's silent unknown-model mapping — which resolves to the expensive tier
# anyway, so mapping it explicitly costs nothing and removes the accident.
export ANTHROPIC_DEFAULT_FABLE_MODEL="$MODEL_PRO"
export CLAUDE_CODE_SUBAGENT_MODEL="$SUBAGENT_MODEL"

# ANTHROPIC_API_KEY (x-api-key) and ANTHROPIC_AUTH_TOKEN (Authorization) are two
# different auth headers. An inherited ANTHROPIC_API_KEY would travel to DeepSeek
# alongside our token — leaking an Anthropic credential to a third party. Drop it.
unset ANTHROPIC_API_KEY

if [ "$PRINT_ENV" -eq 1 ]; then
  cat <<ENVDUMP
ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL
ANTHROPIC_AUTH_TOKEN=$KEY_HINT   # redacted, from $KEY_SOURCE
ANTHROPIC_DEFAULT_OPUS_MODEL=$ANTHROPIC_DEFAULT_OPUS_MODEL
ANTHROPIC_DEFAULT_SONNET_MODEL=$ANTHROPIC_DEFAULT_SONNET_MODEL
ANTHROPIC_DEFAULT_HAIKU_MODEL=$ANTHROPIC_DEFAULT_HAIKU_MODEL
ANTHROPIC_DEFAULT_FABLE_MODEL=$ANTHROPIC_DEFAULT_FABLE_MODEL
CLAUDE_CODE_SUBAGENT_MODEL=$CLAUDE_CODE_SUBAGENT_MODEL
ANTHROPIC_API_KEY=(unset)
ENVDUMP
  exit 0
fi

command -v claude >/dev/null 2>&1 || {
  echo "error: 'claude' not found on PATH." >&2
  exit 1
}

# Banner to stderr, every run, no way to suppress it. The failure mode this guards
# against is forgetting which backend you are on and pasting in code that must not
# leave your infrastructure. Cheap to print, expensive to omit.
{
  echo "┌─ DeepSeek session ─────────────────────────────────────────"
  echo "│ backend : $BASE_URL"
  echo "│ models  : $MODEL_PRO (opus/sonnet/fable) · $MODEL_FLASH (haiku)"
  echo "│ subagent: $SUBAGENT_MODEL"
  echo "│ key     : $KEY_HINT  ← $KEY_SOURCE"
  echo "│ cwd     : $PWD"
  echo "│"
  echo "│ NOT Anthropic. Every prompt, file read, and tool result in"
  echo "│ this session is sent to DeepSeek. Confirm this repo's code"
  echo "│ is cleared to go there."
  echo "└────────────────────────────────────────────────────────────"
} >&2

exec claude "${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"}"
