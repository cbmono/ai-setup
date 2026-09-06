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

- `.claude/hooks/` — executable scripts referenced from `settings.json`. Mostly hooks; `statusline.sh` also lives here, because the defining property of this dir is "referenced from `settings.json`" and it shares the absolute-path convention. **The status line is where spend gets reported** — a reply can only guess at cost, so `claude-defaults.md` forbids stating it in prose and the script reads the real numbers off the harness's stdin JSON ([contract](https://code.claude.com/docs/en/statusline)). Treat every field as optional: `cost` is `0` early, `rate_limits` is Pro/Max-only, `context_window.used_percentage` is `null` before the first call and after `/compact` — drop absent parts instead of rendering `null`, and exit 0 on malformed or empty stdin. Must be self-detecting (no project-specific paths, no toolchain assumptions) and exit 0 on every non-applicable input so they can ship to every consumer. **Always reference a hook by an absolute, shell-expanded path** — `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/<name>.sh` for anything in this baseline (the configured Claude config dir, default `~/.claude` — the same expression `install.sh` resolves `DEST` from, so the installer and the hook command can't disagree about where config lives), or `"$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>.sh` for a hook a project commits itself (the idiom the ai-bridge repo's `symlink/.claude/settings.json` uses). A bare relative `.claude/hooks/…` resolves against the **session cwd**, so it exits 127 on every matching tool call in any project that doesn't itself ship the script — noisy, and the hook silently never runs.
- `.claude/scripts/` — executable scripts the **user** runs directly, as opposed to `hooks/` (invoked by Claude Code) and `commands/` (invoked as `/name` inside a session). Adding anything here needs a matching `!.claude/scripts/` line in the root `.gitignore` — `.claude/*` is denied with tracked defaults re-included one by one, so a new dir is silently untracked otherwise. `install.sh` links the dir automatically once git tracks it.
- **Alternative LLM backends are not shipped here.** Substituting a non-Anthropic model behind Claude Code lives in the `ai-bridge-llm@ai-bridge` companion plugin.
