#!/usr/bin/env bash
#
# statusline.sh — Claude Code status line (ai-setup baseline).
#
# Shows what a reply must never claim in prose: model, context used, session
# cost, lines changed, and 5-hour rate-limit burn. Spend belongs here, on a line
# fed real numbers by the harness, rather than in an answer where it would be
# guesswork.
#
# Reads the status-line JSON on stdin (contract:
# https://code.claude.com/docs/en/statusline) and prints one line. Every field is
# optional by design — absent or null parts are dropped rather than rendered as
# "null" or "0":
#   * context_window.used_percentage  — null before the first API call and after /compact
#   * cost.*                          — 0 until work happens
#   * rate_limits.*                   — Claude.ai Pro/Max only, after the first response
#
# Universally safe, per the settings.json hook rule: it only reads stdin, writes
# one line to stdout, and exits 0 on every input — including malformed JSON.
#
# To turn it off without editing this baseline, override the whole key in
# .claude/settings.local.json (project) or your own settings:
#   { "statusLine": { "type": "command", "command": "true" } }
set -uo pipefail

input="$(cat)"

# jq isn't guaranteed on a fresh machine. Say so once, actionably, instead of
# failing silently and leaving the user wondering where their status line went.
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "⚠ status line needs jq — install it (brew install jq) or unset statusLine"
  exit 0
fi

printf '%s' "$input" | jq -r '
  # 1.234 -> "1.23", 1.5 -> "1.50". jq has no float formatter, so round to
  # integer cents and reassemble, keeping the trailing zero.
  def money:
    (. * 100 | round) as $c
    | ($c % 100 | tostring) as $frac
    | "\($c / 100 | floor).\(if ($frac | length) == 1 then "0" + $frac else $frac end)";

  [
    (.model.display_name // empty),

    (if (.context_window.used_percentage // null) != null
       then "\(.context_window.used_percentage | floor)% ctx"
       else empty end),

    (if (.cost.total_cost_usd // 0) > 0
       then "$\(.cost.total_cost_usd | money)"
       else empty end),

    (if ((.cost.total_lines_added // 0) + (.cost.total_lines_removed // 0)) > 0
       then "+\(.cost.total_lines_added // 0)/-\(.cost.total_lines_removed // 0)"
       else empty end),

    (if (.rate_limits.five_hour.used_percentage // null) != null
       then "5h \(.rate_limits.five_hour.used_percentage | floor)%"
       else empty end)
  ]
  | join(" · ")
' 2>/dev/null || true

exit 0
