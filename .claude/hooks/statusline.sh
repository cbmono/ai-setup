#!/usr/bin/env bash
# Status line: robbyrussell-style prompt segment, followed by optional
# Claude Code metadata segments (model, context %, rate limits, PR),
# each shown only when its field is present in the input JSON.
#   ➜  <dir> git:(<branch>) ✗ │ <model> │ ctx 42% │ 5h 31% ↻14:22 · 7d 12% │ PR #123 (approved)
# Reads Claude Code's statusLine JSON from stdin. Always exits 0.

input=$(cat 2>/dev/null)

# ANSI colors (render dimmed in the Claude Code status bar)
GREEN=$'\033[1;32m'
CYAN=$'\033[36m'
BLUE=$'\033[1;34m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
MAGENTA=$'\033[35m'
RESET=$'\033[0m'

cwd=""
model_name=""
ctx_pct=""
five_pct=""
five_reset=""
seven_pct=""
pr_number=""
pr_state=""

if command -v jq >/dev/null 2>&1; then
  # Delimit fields with the ASCII Unit Separator (octal \037 / 0x1F) rather
  # than @tsv's tab: bash's `read` treats tab (like space/newline) as "IFS
  # whitespace", so it collapses consecutive tab delimiters and trims
  # leading/trailing ones -- silently shifting every later value one slot
  # to the left whenever an earlier field is empty. \037 is not IFS
  # whitespace, so each delimiter -- even next to another -- always marks
  # exactly one field. It's built in bash ($'\037', same style as the ANSI
  # color vars above) and passed to jq via --arg, so no escape sequence for
  # it ever has to live inside the jq program text itself. jq's `join`
  # turns missing/null elements into "" and numbers into their string form
  # on its own, so no `// ""` defaults are needed here.
  sep=$'\037'
  line=$(printf '%s' "$input" | jq -r --arg sep "$sep" '
    [
      (.workspace.current_dir // .cwd),
      .model.display_name,
      (.context_window.used_percentage | if . == null then null else round end),
      (.rate_limits.five_hour.used_percentage | if . == null then null else round end),
      .rate_limits.five_hour.resets_at,
      (.rate_limits.seven_day.used_percentage | if . == null then null else round end),
      .pr.number,
      .pr.review_state
    ] | join($sep)
  ' 2>/dev/null)
  IFS="$sep" read -r cwd model_name ctx_pct five_pct five_reset seven_pct pr_number pr_state <<< "$line"
fi

[ -z "$cwd" ] && cwd="$PWD"

# Basename of cwd (like %c in robbyrussell)
dir=$(basename "$cwd")

# --- robbyrussell git segment ---
git_segment=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --quiet --short HEAD 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    dirty=""
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      dirty=" ${YELLOW}✗${RESET}"
    fi
    git_segment=" ${BLUE}git:(${RED}${branch}${BLUE})${RESET}${dirty}"
  fi
fi

line=$(printf "${GREEN}➜${RESET}  ${CYAN}%s${RESET}%s" "$dir" "$git_segment")

# Green under 60, yellow 60-84, red 85+. Assumes $1 is an integer string.
pct_color() {
  case "$1" in
    ''|*[!0-9]*) printf '%s' "$RESET" ;;
    *)
      if [ "$1" -ge 85 ]; then printf '%s' "$RED"
      elif [ "$1" -ge 60 ]; then printf '%s' "$YELLOW"
      else printf '%s' "$GREEN"
      fi
      ;;
  esac
}

segments=()

# --- model ---
if [ -n "$model_name" ]; then
  segments+=("$(printf "${MAGENTA}%s${RESET}" "$model_name")")
fi

# --- context window usage ---
if [ -n "$ctx_pct" ]; then
  c=$(pct_color "$ctx_pct")
  segments+=("$(printf "${c}ctx %s%%${RESET}" "$ctx_pct")")
fi

# --- rate limits (5h / 7d) ---
if [ -n "$five_pct" ] || [ -n "$seven_pct" ]; then
  rl=""
  if [ -n "$five_pct" ]; then
    c=$(pct_color "$five_pct")
    rl="${c}5h ${five_pct}%${RESET}"
    if [ -n "$five_reset" ]; then
      reset_hm=$(date -r "$five_reset" +%H:%M 2>/dev/null)
      [ -n "$reset_hm" ] && rl="${rl} ↻${reset_hm}"
    fi
  fi
  if [ -n "$seven_pct" ]; then
    c=$(pct_color "$seven_pct")
    seven_str="${c}7d ${seven_pct}%${RESET}"
    if [ -n "$rl" ]; then
      rl="${rl} · ${seven_str}"
    else
      rl="$seven_str"
    fi
  fi
  [ -n "$rl" ] && segments+=("$rl")
fi

# --- open PR ---
if [ -n "$pr_number" ]; then
  if [ -n "$pr_state" ]; then
    segments+=("$(printf "PR #%s (%s)" "$pr_number" "$pr_state")")
  else
    segments+=("$(printf "PR #%s" "$pr_number")")
  fi
fi

for s in "${segments[@]}"; do
  line="${line} │ ${s}"
done

printf "%s\n" "$line"
exit 0
