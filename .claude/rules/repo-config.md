---
paths:
  - "/.coderabbit.yaml"
  - "/install.sh"
---

# Root config: CodeRabbit review config and the user-wide installer

Loaded on demand when you touch `.coderabbit.yaml` or `install.sh`. Relocated
verbatim from the root `CLAUDE.md`.

- `.coderabbit.yaml` (root) — CodeRabbit review config **for this repo only** (not shipped to consumers; `install.sh` is scoped to `.claude`). Enforces **one review per PR**: `auto_incremental_review: false` and `chat.auto_reply: false` (both default `true`). Findings get fixed and pushed; a re-review of addressed findings finds nothing and costs a full session. Validate keys against the schema URL in the file's header comment before editing — don't invent keys.
- `install.sh` (root) — user-wide installer. Per-entry symlinks the tracked `.claude/` defaults **into** the real config dir — `DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`, matching how `settings.json` references its hooks — (never a whole-dir symlink, so runtime state stays out of the repo and an existing `~/.claude` isn't clobbered). Auto-discovers what to link via `git ls-files .claude`, minus a small `EXCLUDE` denylist (repo docs, templates, `settings.json`). Idempotent; backs up anything it would overwrite. `--uninstall` removes only the symlinks it created (leaves runtime state, real files, and backups). When you add a tracked default that should NOT land in `~/.claude`, add it to `EXCLUDE`. **`ADOPTABLE_KEYS` / `adopt_keys()` is the one place the installer edits a user's real file, and it must stay display-only** (currently `statusLine`, `outputStyle`): those change how Claude *reports*, so merging one can never widen what Claude is allowed to *do*. Never add a permissions, env, MCP, or plugin key — silently granting a permission during an install is exactly the surprise the per-entry-symlink design exists to avoid. The merge only ever *adds an absent* key (a user's own value wins and re-running never reverts it), backs the file up first, and requires `jq` so the file is parsed as JSON rather than edited line-wise — invalid JSON or no `jq` must leave the file untouched with a printed instruction. Covered by `tests/install-adopt-keys.test.sh`.
