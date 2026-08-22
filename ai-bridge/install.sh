#!/usr/bin/env bash
#
# install.sh — provision (or refresh) an ai-bridge INSTANCE.
#
#   Usage:
#     install.sh [TARGET]              # install/refresh an instance at TARGET (default: cwd)
#     install.sh --uninstall [TARGET]  # remove only the symlinks this script created
#     install.sh --help
#
# It does three things, mirroring how the parent ai-setup repo provisions ~/.claude:
#   1. SYMLINKS the generic machinery in `symlink/` into TARGET (file granularity,
#      absolute targets). Updates to the template propagate to every instance.
#      These paths are gitignored in the instance (managed block in .gitignore).
#   2. COPIES the `seed/` content into TARGET *only if absent* — never clobbering
#      instance data (objectives/projects/knowledge/log/config/CLAUDE.md).
#   3. LINKS the group's product repos into TARGET/repos/ — one symlink each, via
#      scripts/link-repos.sh — so the peer repos are reachable from inside the
#      instance without ever being nested in it. Gitignored, and skipped while
#      reposRoot is still the seeded placeholder. Re-run that script on its own
#      after cloning a repo; you don't need a full refresh for it.
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
      # Range must cover the whole header block above (through the "Backs up…"
      # line) — extend it when you add lines there, or --help truncates silently.
      sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'
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
  # The repos/ view first, and via the TEMPLATE's copy of the script rather than
  # the installed symlink — the loop below is about to delete that symlink, and
  # running the template copy also works if it was already removed by hand.
  ( cd "$TARGET" && bash "$SYMLINK_SRC/scripts/link-repos.sh" --remove ) || true
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

# Is this the first stamp, or a refresh of an existing instance? Decided BEFORE
# seeding, since seeding is what creates instance.config.json. Only the awaiting
# queue below needs to know, and it needs to badly: see there for why.
FIRST_STAMP=no
[ -e "$TARGET/instance.config.json" ] || FIRST_STAMP=yes

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
        # The seed ships terminal.integrated.cwd commented out with a __BRIDGE_DIR__
        # placeholder; uncomment it with this instance's absolute path so every new
        # terminal in the workspace starts in the instance rather than the group
        # root — see the comment in seed/bridge.code-workspace for why the wrong
        # cwd silently hides /pm-loop and /new-project. Whole-line
        # replacement, so a marker that ever stops matching degrades to "no pin"
        # rather than to a broken workspace file. Escaped for sed's replacement
        # side ('&' means "the match", '\' escapes, '|' is our delimiter) so a path
        # containing any of them can't corrupt the file. JSON-escaped first (a
        # literal '\' or '"' in a path would otherwise emit an invalid string).
        ws_dir="$(printf '%s' "$TARGET" | sed 's/["\\]/\\&/g; s/[\\&|]/\\&/g')"
        sed "s|^ *// \"terminal.integrated.cwd\": \"__BRIDGE_DIR__\",|    \"terminal.integrated.cwd\": \"$ws_dir\",|" \
          "$SEED_SRC/$rel" > "$TARGET/$WS_NAME"
        echo "  seed  $WS_NAME"
        # No live setting line means the marker stopped matching the seed; say so
        # rather than leaving a silently unpinned workspace. (Checking for a
        # leftover placeholder wouldn't work — a drifted line is still a comment.)
        if ! grep -q '^ *"terminal\.integrated\.cwd":' "$TARGET/$WS_NAME"; then
          echo "  warn  $WS_NAME: terminal cwd not stamped; set terminal.integrated.cwd to $TARGET by hand" >&2
        fi
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

# 1b. The awaiting-you queue, created ONLY on the first stamp.
#
# AWAITING.md is opt-in by presence: the project-manager refreshes it only when
# it exists and never creates it, so deleting it turns the startup nudge off for
# good. That switch is the whole design — but it also means a brand-new instance
# would start with the queue OFF, and the SessionStart nudge would never fire
# until someone happened to read the docs and touch the file. So the installer
# provides the initial file, exactly once.
#
# It must NOT run on a refresh: re-creating the file would silently undo a
# deliberate `rm`, which is the one thing the off switch has to survive. That's
# what FIRST_STAMP guards. It's also gitignored, so this never becomes tracked
# state. Content is a valid empty queue, so show-awaiting.sh stays silent until
# the first tick fills it in.
if [ "$FIRST_STAMP" = yes ] && [ ! -e "$TARGET/AWAITING.md" ]; then
  cat > "$TARGET/AWAITING.md" <<'AWAITING'
# Awaiting you

Derived and gitignored — **do not hand-edit**. Rewritten each `/pm-loop` tick
from `projects/*/tasks/*.md`. Delete this file to turn the queue off for good;
the loop never recreates it. Last refreshed: never (no tick has run yet).

## 🔴 Awaiting you (0)
_None._
AWAITING
  echo "  seed  AWAITING.md (queue on; delete it to turn the startup nudge off)"
elif [ "$FIRST_STAMP" = no ] && [ ! -e "$TARGET/AWAITING.md" ]; then
  echo "  skip  AWAITING.md (absent by choice — run 'touch AWAITING.md' to re-enable)"
fi

# 1c. The board snapshot, created ONLY on the first stamp — same contract, same
# reason, same guard as AWAITING.md above.
#
# SNAPSHOT.json is opt-in by presence: scripts/write-snapshot.sh rewrites it only when
# it exists and never creates it, and scripts/build-board.sh leaves an instance without
# one off the board entirely. So `rm SNAPSHOT.json` takes this instance off the board
# for good — and FIRST_STAMP is what makes "for good" true, because a refresh that
# re-created the file would silently undo that decision.
#
# It is deliberately generated ROOT content and not a file under symlink/: machinery is
# re-linked unconditionally on every run (see AUTONOMY.md's hazard in
# .claude/rules/ai-bridge.md), so a deletable capability built out of a machinery file
# comes back by itself. A gitignored root file has no such hole.
#
# Seeded content is a VALID EMPTY snapshot rather than an empty file: build-board.sh
# parses this as JSON, and a zero-byte file would render an "unreadable snapshot" note
# on a brand-new instance that has done nothing wrong.
if [ "$FIRST_STAMP" = yes ] && [ ! -e "$TARGET/SNAPSHOT.json" ]; then
  cat > "$TARGET/SNAPSHOT.json" <<'SNAPSHOT'
{
  "_schema": "ai-bridge board snapshot v1",
  "_sensitivity": "Derived and gitignored. Rewritten by scripts/write-snapshot.sh each /pm-loop tick. Delete this file to take this instance off the board for good.",
  "group": "",
  "generated_at": "",
  "counts": {"projects": 0, "tasks": 0, "awaiting": 0},
  "projects": []
}
SNAPSHOT
  echo "  seed  SNAPSHOT.json (on the board; delete it to take this instance off)"
elif [ "$FIRST_STAMP" = no ] && [ ! -e "$TARGET/SNAPSHOT.json" ]; then
  echo "  skip  SNAPSHOT.json (absent by choice — run 'touch SNAPSHOT.json' to re-enable)"
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

# 2b. Retire machinery the template no longer ships.
#
# When a capability is removed from symlink/, an instance stamped earlier keeps a symlink
# pointing at a path that no longer exists. A dangling command or hook is worse than an
# absent one: Claude Code registers the file that isn't there, and a SessionStart hook
# whose script has vanished exits 127 on every launch.
#
# The test is deliberately narrow, and both halves are load-bearing: the link must point
# INTO this template's symlink/ (so it is unambiguously one we created — `ours` decides
# that, not a name match), AND its target must be gone.
#
# The SCAN is deliberately wide, though — the whole instance, not just .claude/ and
# scripts/. `machinery_paths()` also places files at the instance ROOT (SCHEMA.md,
# AUTONOMY.md, CONVENTIONS.md) and under agents/, so a narrower scan would miss exactly
# the most load-bearing files. `ours` is what makes a wide scan safe: `repos/<name>`
# links point at reposRoot, not into symlink/, so they are never candidates. `find` does
# not follow symlinks, so it cannot descend into a linked repo; .git is pruned for speed. A link we made whose target we
# deleted has exactly one possible meaning. Anything else — a real file, a link to
# somewhere else, a link that still resolves — is left alone.
#
# Only removes the link. Never touches seed content or instance data: a `todos.md` left
# behind by a retired feature is the human's own writing, so it is reported, not deleted.
while IFS= read -r dst; do
  [ -n "$dst" ] || continue
  # "$TARGET" must be QUOTED inside the prefix operator: unquoted it is matched as a
  # GLOB, so an instance path containing [ ] * or ? strips nothing, `rel` stays absolute,
  # `ours` then tests "$TARGET/$TARGET/..." and returns false — silently skipping a
  # genuinely dead link instead of retiring it. (SC2295.)
  rel="${dst#"$TARGET"/}"
  if ours "$rel" && [ ! -e "$dst" ]; then
    rm -f "$dst"
    echo "  retire $rel (no longer shipped by the template)"
  fi
done <<EOF
$(find "$TARGET" -name .git -prune -o -type l -print 2>/dev/null | sort)
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

# The repos/ view is derived, so it must be ignored too — but OUTSIDE the managed
# block, which is regenerated from the machinery file list and would drop any line
# that isn't a machinery path. Appended once; a hand-written `repos/` also counts.
if ! grep -qE '^/?repos/?$' "$gi"; then
  cat >> "$gi" <<'GI'

# Derived view of the group's product repos (scripts/link-repos.sh) — symlinks
# into reposRoot, never content, and machine-local like the rest. Delete it
# freely; the next install or `scripts/link-repos.sh` run recreates it.
/repos/
GI
fi

# 4. Product-repo view — one symlink per repo under TARGET/repos/, so the peer
# repos are reachable from inside the instance without being nested in it.
# Best-effort by design: a fresh instance still has the placeholder reposRoot, and
# the script exits 0 with an explanation in that case rather than failing the
# install. Template copy, for the same reason as in --uninstall.
( cd "$TARGET" && bash "$SYMLINK_SRC/scripts/link-repos.sh" ) \
  || echo "  warn  repos/ view not refreshed; run scripts/link-repos.sh by hand" >&2

echo "Done. Machinery symlinked & gitignored; seed content in place."
echo "Next: edit instance.config.json, then run /pm-loop from this directory."
echo "      (Set reposRoot first, then 'scripts/link-repos.sh' fills in repos/.)"

# 5. One nudge, and only a nudge. A pull can bring a stricter SCHEMA.md, whose validator
# reaches the instance instantly through its symlink and starts reporting errors against
# documents written under the old rules — and nothing repairs them until someone runs
# the migration. So say so, once, and point at upgrade.sh.
#
# Deliberately NOT the migration itself: this script is safe to run blindly precisely
# because it only links and seeds-if-absent, and spending that property to save the user
# one command would be a bad trade. Non-fatal, and silent unless the validator says
# exactly "there are errors" (exit 1): absent (an instance older than the validator) or
# clean says nothing, and any other exit code — 2 is "not an instance root" — is not
# something a user can act on from here.
if [ -e "$TARGET/scripts/validate-bundle.sh" ]; then
  vrc=0
  ( cd "$TARGET" && bash scripts/validate-bundle.sh ) >/dev/null 2>&1 || vrc=$?
  if [ "$vrc" -eq 1 ]; then
    echo "Note: this bundle has schema errors. To see and repair them, run:"
    echo "      $TEMPLATE_DIR/upgrade.sh $TARGET"
  fi
fi
