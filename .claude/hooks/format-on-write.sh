#!/usr/bin/env bash
# Format files after Claude writes them, if the project declares a formatter.
#
# Wired up from .claude/settings.json as a PostToolUse hook on Write|Edit.
# Reads Claude Code's hook JSON on stdin and exits 0 unconditionally — a
# missing formatter, a non-Node project, or a tool failure must never block
# the parent tool.
#
# Detection (in order):
#   1. Bail unless the edited file has a formattable extension.
#   2. Walk up from the file looking for the nearest package.json.
#   3. If "@biomejs/biome" is declared (and the file type is supported by
#      biome), run `npx --no-install biome format --write`.
#   4. Else if "prettier" is declared, run `npx --no-install prettier --write
#      --ignore-unknown`.
#   5. Otherwise no-op.
#
# --no-install ensures we never auto-install a formatter the consumer didn't
# choose; if the dep is declared but node_modules is empty, we fail silently.

set -u

# Hook input on stdin: { tool_input: { file_path }, tool_response: { filePath } }
file="$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)"
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

# File extension gate. Biome handles JS/TS/JSON; Prettier additionally handles
# markdown, CSS, HTML, YAML.
biome_can_format=0
prettier_can_format=0
case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.jsonc)
    biome_can_format=1
    prettier_can_format=1
    ;;
  *.md|*.mdx|*.css|*.scss|*.less|*.html|*.vue|*.yml|*.yaml)
    prettier_can_format=1
    ;;
  *)
    exit 0
    ;;
esac

# Walk up to find the nearest package.json. Stop at the filesystem root or at
# any .git boundary so we don't escape the project.
dir="$(cd "$(dirname "$file")" && pwd)"
pkg=""
while [ "$dir" != "/" ]; do
  if [ -f "$dir/package.json" ]; then
    pkg="$dir/package.json"
    break
  fi
  if [ -d "$dir/.git" ]; then
    break
  fi
  dir="$(dirname "$dir")"
done
[ -z "$pkg" ] && exit 0

declares() {
  jq -e --arg name "$1" \
    '((.devDependencies // {}) + (.dependencies // {})) | has($name)' \
    "$pkg" >/dev/null 2>&1
}

project_dir="$(dirname "$pkg")"

if [ "$biome_can_format" = 1 ] && declares "@biomejs/biome"; then
  (cd "$project_dir" && npx --no-install biome format --write "$file") >/dev/null 2>&1
elif [ "$prettier_can_format" = 1 ] && declares "prettier"; then
  (cd "$project_dir" && npx --no-install prettier --write --ignore-unknown "$file") >/dev/null 2>&1
fi

exit 0
