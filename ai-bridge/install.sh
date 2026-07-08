#!/usr/bin/env bash
#
# install.sh — provision (or refresh) an ai-bridge INSTANCE.
#
#   Usage:
#     install.sh [TARGET]              # install/refresh an instance at TARGET (default: cwd)
#     install.sh --uninstall [TARGET]  # remove only the symlinks this script created
#     install.sh --help
#
# It does two things, mirroring how the parent ai-setup repo provisions ~/.claude:
#   1. SYMLINKS the generic machinery in `symlink/` into TARGET (file granularity,
#      absolute targets). Updates to the template propagate to every instance.
#      These paths are gitignored in the instance (managed block in .gitignore).
#   2. COPIES the `seed/` content into TARGET *only if absent* — never clobbering
#      instance data (objectives/projects/knowledge/log/config/CLAUDE.md).
#
# Idempotent: re-running relinks cleanly and reports already-linked entries.
# Backs up any conflicting real file as <name>.bak.<epoch> before linking.
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"
SYMLINK_SRC="$TEMPLATE_DIR/symlink"
SEED_SRC="$TEMPLATE_DIR/seed"
BEGIN_MARK="# >>> ai-bridge machinery (symlinked) >>>"
END_MARK="# <<< ai-bridge machinery <<<"

MODE="install"
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE="uninstall" ;;
    --help|-h)
      sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) echo "error: unknown flag '$arg'" >&2; exit 2 ;;
    *)
      [ -z "$TARGET" ] || { echo "error: multiple target directories given" >&2; exit 2; }
      TARGET="$arg" ;;
  esac
done
TARGET="$(cd "${TARGET:-$PWD}" 2>/dev/null && pwd || true)"
[ -n "$TARGET" ] || { echo "error: target directory does not exist" >&2; exit 2; }
[ -d "$SYMLINK_SRC" ] || { echo "error: template missing $SYMLINK_SRC" >&2; exit 2; }

# Name the seeded workspace file after the group so an open editor window is
# identifiable (VS Code shows the .code-workspace *filename* — there's no top-level
# name field). Group = instance dir name minus the _ai-bridge- prefix.
WS_GROUP="$(basename "$TARGET")"; WS_GROUP="${WS_GROUP#_ai-bridge-}"
WS_NAME="${WS_GROUP}.code-workspace"

# Relative paths of every machinery file to symlink.
machinery_paths() {
  ( cd "$SYMLINK_SRC" && find . -type f | sed 's#^\./##' | sort )
}

ours() {  # is TARGET/$1 a symlink we created (points into this template)?
  local dst="$TARGET/$1"
  [ -L "$dst" ] && case "$(readlink "$dst")" in "$SYMLINK_SRC"/*) return 0 ;; esac
  return 1
}

if [ "$MODE" = "uninstall" ]; then
  echo "Removing ai-bridge machinery symlinks from $TARGET"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if ours "$rel"; then rm "$TARGET/$rel"; echo "  unlinked $rel"; fi
  done <<EOF
$(machinery_paths)
EOF
  echo "Done. Seed content, instance data, and backups were left untouched."
  exit 0
fi

echo "Installing ai-bridge instance at $TARGET"

# 1. Seed content — copy only what's absent (never clobber instance data).
if [ -d "$SEED_SRC" ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    # The workspace file is seeded under a group-specific name (see WS_NAME above).
    if [ "$rel" = "bridge.code-workspace" ]; then
      existing="$(find "$TARGET" -maxdepth 1 -name '*.code-workspace' 2>/dev/null | head -1)"
      if [ -n "$existing" ]; then
        echo "  keep  $(basename "$existing") (workspace exists)"
      else
        cp "$SEED_SRC/$rel" "$TARGET/$WS_NAME"; echo "  seed  $WS_NAME"
      fi
      continue
    fi
    src="$SEED_SRC/$rel"; dst="$TARGET/$rel"
    dstdir="$(dirname "$dst")"
    if [ -e "$dst" ]; then
      echo "  keep  $rel (exists)"
    elif [ "$(basename "$rel")" = ".gitkeep" ] && [ -d "$dstdir" ] && [ -n "$(ls -A "$dstdir" 2>/dev/null)" ]; then
      # The dir already has real content — a placeholder .gitkeep would just be clutter.
      echo "  skip  $rel (dir already populated)"
    else
      mkdir -p "$dstdir"
      cp "$src" "$dst"
      echo "  seed  $rel"
    fi
  done <<EOF
$(cd "$SEED_SRC" && find . -type f | sed 's#^\./##' | sort)
EOF
fi

# 2. Machinery — symlink each file (absolute target), backing up real conflicts.
chmod +x "$SYMLINK_SRC"/scripts/*.sh 2>/dev/null || true
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  src="$SYMLINK_SRC/$rel"; dst="$TARGET/$rel"
  if ours "$rel"; then echo "  ok    $rel (already linked)"; continue; fi
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    bak="$dst.bak.$(date +%s)"; mv "$dst" "$bak"
    echo "  moved $rel -> $(basename "$bak")"
  fi
  ln -s "$src" "$dst"
  echo "  link  $rel"
done <<EOF
$(machinery_paths)
EOF

# 3. Rewrite the managed machinery block in the instance .gitignore.
gi="$TARGET/.gitignore"
[ -f "$gi" ] || printf '%s\n%s\n' "$BEGIN_MARK" "$END_MARK" > "$gi"
grep -qF "$BEGIN_MARK" "$gi" || printf '\n%s\n%s\n' "$BEGIN_MARK" "$END_MARK" >> "$gi"
mlist="$(mktemp)"; machinery_paths > "$mlist"
tmp="$gi.tmp.$$"
awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v mlist="$mlist" '
  $0==b { print; while ((getline line < mlist) > 0) print "/" line; close(mlist); inblock=1; next }
  $0==e { print; inblock=0; next }
  !inblock { print }
' "$gi" > "$tmp" && mv "$tmp" "$gi"
rm -f "$mlist"

echo "Done. Machinery symlinked & gitignored; seed content in place."
echo "Next: edit instance.config.json, then run /pm-loop from this directory."
