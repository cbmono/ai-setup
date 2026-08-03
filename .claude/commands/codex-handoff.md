Hand this session off to Codex — or pull Codex's work back into Claude. One command, both directions.

Use this when Claude tokens are running low (or you want a different model on the problem). It wraps
the `codex` plugin's `transfer`, fixing the two things that make the raw command awkward: the
transcript it can't auto-detect, and the fact that there is no built-in way *back*.

Argument: `$ARGUMENTS` — empty means **go to Codex**; `back` means **return to Claude**.

## Preflight (both directions)

1. Resolve the plugin's companion script **version-agnostically** — never hardcode a version, it
   changes on every plugin update:
   ```bash
   CODEX_COMPANION="$(ls -1d "$HOME"/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)"
   ```
   If that resolves to nothing, the plugin isn't installed — tell the user to follow
   "Codex as a failover" in `README.md` (`/plugin marketplace add openai/codex-plugin-cc`,
   `/plugin install codex@openai-codex`, `/reload-plugins`) and stop.
2. Confirm Codex is ready: `node "$CODEX_COMPANION" setup --json`. If `ready` is not `true`, report
   which check failed (`node` / `npm` / `codex` / `auth`) and stop — `auth` false means `!codex login`.

## Direction A — Claude → Codex (no arguments)

3. **Resolve this session's transcript.** The plugin's auto-detection often fails with
   "Could not identify the current Claude transcript", so always pass `--source` explicitly:
   ```bash
   PROJ="$HOME/.claude/projects/$(pwd | sed 's|/|-|g')"
   TRANSCRIPT="$(ls -t "$PROJ"/*.jsonl 2>/dev/null | head -1)"
   ```
   **Print the resolved path and its mtime.** This picks the *most recently written* transcript for
   the current directory, which is this session — unless another session is live in the same
   directory. If several transcripts were touched in the last few minutes, say so and ask which
   before transferring; handing over the wrong conversation is confusing and wastes a large number
   of Codex tokens.
4. **Transfer:**
   ```bash
   node "$CODEX_COMPANION" transfer --source "$TRANSCRIPT"
   ```
5. **Persist the returned session ID** so the return leg needs no copy-paste, and keep the file
   greppable (it's gitignored):
   ```bash
   printf '%s\t%s\n' "$(date -u +%FT%TZ)" "<session-id>" >> .claude/codex-sessions.log
   ```
6. **Report** the `codex resume <session-id>` command verbatim, and tell the user to run it with the
   `!` prefix (`! codex resume <id>`) so its output lands in this conversation, or in a plain
   terminal if they're switching away from Claude entirely.
7. Note honestly what transferred: the **turn history**, not the tool-call internals. Codex starts
   with the conversation, not with Claude's live state — no worktrees, no in-flight edits.

## Direction B — Codex → Claude (`back`)

There is no "transfer back" primitive: Claude Code can't be resumed *into* from Codex. What works is
having Codex summarise itself and ingesting that — which this does in one step.

8. Read the most recent ID from `.claude/codex-sessions.log` (last field of the last line). If the
   file is missing or empty, ask the user for the session ID.
9. Ask Codex for a handoff brief, non-interactively:
   ```bash
   codex exec resume <session-id> "Summarise for a Claude Code session taking over from you: (1) what you changed, file by file; (2) what you verified and how; (3) what is still unfinished or uncertain; (4) any decision a reviewer would question. Be specific and terse. Do not re-explain the original task."
   ```
   `codex exec resume` takes **no** `--sandbox` flag (that's `codex exec` only) — passing one errors.
10. **Verify against reality rather than trusting the summary.** Run `git status --short` and
    `git diff --stat` and reconcile: a file Codex claims to have changed that isn't in the diff, or a
    changed file it didn't mention, is the finding. Report mismatches explicitly.
11. Summarise for the user: what Codex did, what you confirmed independently, and what still needs
    doing. Then carry on in Claude.

## Rules

- **Never invent flags.** Confirm with `node "$CODEX_COMPANION" <cmd> --help` or `codex exec --help`
  before improvising; the surfaces differ between `codex exec` and `codex exec resume`.
- **Transferring is not free** — the transcript is re-read into Codex's context (tens of thousands of
  tokens for a long session). Worth it to escape a token wall; wasteful for a one-line question, where
  `/codex:rescue` is the cheaper tool — but note `/codex:rescue` is **write-capable by default**, and
  with `--background` it edits the same checkout you're still working in. Before suggesting it, say so:
  the user should pause edits in that scope or give Codex its own worktree, then `git diff` the result.
- **Don't enable the Stop-time review gate** (`/codex:setup --enable-review-gate`) on a machine that
  runs `/pm-loop` — it makes every stop wait on a Codex review.
