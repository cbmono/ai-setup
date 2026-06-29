#!/usr/bin/env bash
#
# install.sh — link this repo's Claude Code defaults into ~/.claude.
#
# Per-entry symlinks, NOT a whole-directory symlink: your real ~/.claude keeps
# owning its runtime state (plugins/, sessions/, projects/, history.jsonl,
# settings.local.json), and only the tracked defaults point back at this repo.
# That avoids the two traps of `ln -s .../.claude ~/.claude`: it never nests
# inside an existing ~/.claude, and Claude Code's runtime state never leaks into
# the repo.
#
# Because the links are live, `git pull` propagates content changes and new
# files *inside* linked dirs automatically — no re-sync. Re-run only to pick up
# a brand-new *top-level* entry; it auto-discovers what to link from what git
# tracks. Idempotent and non-destructive (anything it would overwrite is backed
# up — see link() for the shadowing caveat).

set -euo pipefail

usage() {
  cat <<'USAGE'
install.sh — link this repo's Claude Code defaults into ~/.claude.

  ./install.sh              link the tracked defaults into ~/.claude (default)
  ./install.sh --uninstall  remove only the symlinks this script created
  ./install.sh --help       show this help
USAGE
}

# ---- Config (safe to edit by hand) ----------------------------------------
# Tracked entries that must NOT be linked into ~/.claude: repo docs, copy-from
# templates, and the per-machine-sensitive settings.json (handled separately
# below). Everything else git tracks under .claude/ is linked automatically, so
# a new default needs no change here — only add the rare exception.
EXCLUDE="README.md settings.json settings.local.json settings.mempalace.example.json settings.plugins.example.json"

# Used only outside a git checkout (e.g. a tarball download), where tracked
# entries can't be auto-discovered. Keep roughly in sync with the linkable set.
FALLBACK_DEFAULTS="agents commands skills hooks MEMORY.md claude-defaults.md"
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_CLAUDE="$REPO_ROOT/.claude"
DEST="$HOME/.claude"

MODE="install"
case "${1:-}" in
  ""|install) MODE="install" ;;
  -u|--uninstall) MODE="uninstall" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "error: unknown argument '$1' (try --help)." >&2; exit 1 ;;
esac

if [ ! -d "$REPO_CLAUDE" ]; then
  echo "error: $REPO_CLAUDE not found — run install.sh from the repo root." >&2
  exit 1
fi

if [ -L "$DEST" ]; then
  echo "error: ~/.claude is itself a symlink ($(readlink "$DEST"))." >&2
  echo "       This script expects ~/.claude to be a real directory that owns your" >&2
  echo "       runtime state. Replace the symlink with a real dir first, then re-run." >&2
  exit 1
fi

# Top-level entries to link = everything git tracks under .claude/, collapsed to
# its first path component. Falls back to FALLBACK_DEFAULTS outside a git checkout.
list_entries() {
  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$REPO_ROOT" ls-files .claude | sed 's#^\.claude/##; s#/.*##' | sort -u
  else
    echo "warning: not a git checkout — auto-discovery needs git; using FALLBACK_DEFAULTS." >&2
    printf '%s\n' $FALLBACK_DEFAULTS
  fi
}

excluded() {
  case " $EXCLUDE " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# True only when ~/.claude/<name> is a symlink we created (points into this repo).
ours() {
  local dst="$DEST/$1"
  [ -L "$dst" ] && [ "$(readlink "$dst")" = "$REPO_CLAUDE/$1" ]
}

# Links each entry as a whole. NOTE: entries like commands/ and agents/ are
# symlinked as a *unit*, not file-by-file. So if ~/.claude already has a real
# commands/ holding your own global commands, the whole dir is moved aside to
# commands.bak.<epoch> and replaced by the symlink — your commands stay intact
# in the backup but go inactive. You can copy them back, BUT ~/.claude/commands
# is now a symlink into THIS repo, so copying into it writes into the repo
# clone. Personal global commands have no user-level slot under whole-dir
# linking; keep them per-project (<project>/.claude/commands/) instead.
link() {
  local name="$1" src="$REPO_CLAUDE/$1" dst="$DEST/$1"
  if ours "$name"; then
    echo "  ok    $name (already linked)"
    return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    local bak="$dst.bak.$(date +%s)"
    mv "$dst" "$bak"
    echo "  moved $name -> $(basename "$bak")"
  fi
  ln -s "$src" "$dst"
  echo "  link  $name"
}

unlink_entry() {
  local name="$1" dst="$DEST/$1"
  if ours "$name"; then
    rm "$dst"
    echo "  rm    $name"
  elif [ -L "$dst" ]; then
    echo "  skip  $name (symlink points elsewhere — not ours)"
  elif [ -e "$dst" ]; then
    echo "  skip  $name (real file/dir, not a link)"
  fi
}

if [ "$MODE" = "uninstall" ]; then
  echo "Removing Claude Code default symlinks from $DEST"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    excluded "$name" && continue
    unlink_entry "$name"
  done <<EOF
$(list_entries)
EOF
  unlink_entry settings.json
  echo
  echo "Done. Your runtime state, real files, and *.bak.* backups were left untouched."
  exit 0
fi

mkdir -p "$DEST"

echo "Linking Claude Code defaults into $DEST"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  excluded "$name" && continue
  link "$name"
done <<EOF
$(list_entries)
EOF

# settings.json is per-machine sensitive — it can carry plugins/permissions you
# enabled locally. Adopt the repo baseline only if you don't already have one.
if ours settings.json; then
  echo "  ok    settings.json (already linked)"
elif [ -L "$DEST/settings.json" ] && [ ! -e "$DEST/settings.json" ]; then
  # Dangling symlink (e.g. this repo was moved) — nothing real to preserve, relink.
  rm "$DEST/settings.json"
  ln -s "$REPO_CLAUDE/settings.json" "$DEST/settings.json"
  echo "  relink settings.json (was dangling)"
elif [ -e "$DEST/settings.json" ]; then
  echo
  echo "note: ~/.claude/settings.json already exists and was left untouched. To adopt"
  echo "      this repo's permission + plugin baseline, back it up and link it, moving"
  echo "      any machine-specific plugins into settings.local.json (gitignored):"
  echo "        mv ~/.claude/settings.json ~/.claude/settings.json.bak.\$(date +%s)"
  echo "        ln -s \"$REPO_CLAUDE/settings.json\" ~/.claude/settings.json"
else
  ln -s "$REPO_CLAUDE/settings.json" "$DEST/settings.json"
  echo "  link  settings.json"
fi

echo
echo "Done. Restart Claude Code (/exit, then \`claude\`) so it re-scans agents and commands."
