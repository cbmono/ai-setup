---
paths:
  - "/.claude/hooks/**"
  - "/.claude/scripts/**"
---

# Hooks, the status line, and user-run scripts

Loaded on demand when you touch `.claude/hooks/` or `.claude/scripts/`.
Relocated verbatim from the root `CLAUDE.md`.

- **`.claude/scripts/codegraph-sync.sh`** — CodeGraph rebuilds are **manual**, and the
  `codegraph prompt-hook` on `UserPromptSubmit` only *injects context*; it never
  reindexes, and it is structurally blind besides — it receives `{prompt, cwd}`, and the
  human's sessions run in control-panel repos with no `.codegraph` at all. Measured
  2026-08-22: 21 of 35 indexes were 41 days stale while `codegraph status` reported
  `pendingChanges: {0,0,0}` six days and 35 commits behind. **An index that misreports its
  own freshness is worse than none**, so this sweeps them with `codegraph sync` (`--full`
  forces the full `codegraph index`). Two refusals are the design: it never runs
  `codegraph init` (indexing is the user's decision, as the CodeGraph guidance itself
  says) and it never removes an index — it *names* a zero-node one and prints the `uninit`
  command, the same report-don't-delete stance as `prune-worktrees.sh`. And don't judge
  freshness by the `.codegraph/` **directory mtime**: opening the SQLite DB writes WAL
  files, so it tracks the last *read*, not the last build. Use `lastIndexed` from
  `codegraph status --json`.

- `.claude/hooks/` — executable scripts referenced from `settings.json`. Mostly hooks; `statusline.sh` also lives here, because the defining property of this dir is "referenced from `settings.json`" and it shares the absolute-path convention. **The status line is where spend gets reported** — a reply can only guess at cost, so `claude-defaults.md` forbids stating it in prose and the script reads the real numbers off the harness's stdin JSON ([contract](https://code.claude.com/docs/en/statusline)). Treat every field as optional: `cost` is `0` early, `rate_limits` is Pro/Max-only, `context_window.used_percentage` is `null` before the first call and after `/compact` — drop absent parts instead of rendering `null`, and exit 0 on malformed or empty stdin. Must be self-detecting (no project-specific paths, no toolchain assumptions) and exit 0 on every non-applicable input so they can ship to every consumer. **Always reference a hook by an absolute, shell-expanded path** — `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/<name>.sh` for anything in this baseline (the configured Claude config dir, default `~/.claude` — the same expression `install.sh` resolves `DEST` from, so the installer and the hook command can't disagree about where config lives), or `"$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>.sh` for a hook a project commits itself (the idiom `ai-bridge/symlink/.claude/settings.json` uses). A bare relative `.claude/hooks/…` resolves against the **session cwd**, so it exits 127 on every matching tool call in any project that doesn't itself ship the script — noisy, and the hook silently never runs.
- `.claude/scripts/` — executable scripts the **user** runs directly, as opposed to `hooks/` (invoked by Claude Code) and `commands/` (invoked as `/name` inside a session). Adding anything here needs a matching `!.claude/scripts/` line in the root `.gitignore` — `.claude/*` is denied with tracked defaults re-included one by one, so a new dir is silently untracked otherwise. `install.sh` links the dir automatically once git tracks it.
- **The DeepSeek backend is a launcher, not a settings file — don't "harmonise" it.** `.claude/scripts/deepseek-session.sh` works by exporting `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` / model-tier vars **before** `claude` starts. No settings key can do that, so folding it into a `settings.*.example.json` would be inventing config that silently does nothing. Keep two safety properties if you edit it: it **parses** `.env` instead of sourcing it (sourcing executes arbitrary shell from a secrets file), and it `unset`s `ANTHROPIC_API_KEY` (otherwise an Anthropic credential is forwarded to a third-party endpoint alongside the DeepSeek token). Keep it modular like Codex — one script plus bounded doc sections. Unlike Codex it is **substitution, not delegation**: the whole session goes to DeepSeek, so the data-governance caveat and the unsuppressible backend banner are load-bearing, not decoration. **Keep it opt-in and easy to leave out entirely** — routing a whole session to a third party is unacceptable under many organisations' data-governance rules, so any setup with such constraints should be able to simply not have these files. That's why it stays one script plus bounded doc sections rather than being threaded through shared machinery.
