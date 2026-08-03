Hand this session off to Codex — or pull Codex's work back into Claude. One command, both directions.

Use this when Claude tokens are running low (or you want a different model on the problem). It wraps
the `codex` plugin's `transfer`, fixing the two things that make the raw command awkward: the
transcript it can't auto-detect, and the fact that there is no built-in way *back*.

Requires the opt-in `codex` plugin (`openai/codex-plugin-cc`). If it isn't installed, say so and stop:
`/plugin marketplace add openai/codex-plugin-cc`, `/plugin install codex@openai-codex`,
`/reload-plugins`, then `/codex:setup`.

Argument: `$ARGUMENTS` — empty means **go to Codex**; `back` means **return to Claude**.

## Preflight (both directions)

1. **Resolve the companion script, preferring the version this setup pins.** Never hardcode a single
   version — the path contains one and it changes on plugin update — but don't blindly take the
   newest either, or a freshly-cached release silently supersedes the pinned one:
   ```bash
   CODEX_PIN="v1.0.6"   # keep in step with `ref` in settings.codex.example.json
   CODEX_ROOT="$HOME/.claude/plugins/cache/openai-codex/codex"
   CODEX_COMPANION="$CODEX_ROOT/${CODEX_PIN#v}/scripts/codex-companion.mjs"
   if [ ! -f "$CODEX_COMPANION" ]; then
     CODEX_COMPANION="$(ls -1d "$CODEX_ROOT"/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)"
   fi
   ```
   If the pinned version is absent and a different one is used, **say which** — the user is running
   code they didn't pin. If nothing resolves, the plugin isn't installed (see above) — stop.
2. Confirm Codex is ready: `node "$CODEX_COMPANION" setup --json`. If `ready` is not `true`, report
   which check failed (`node` / `npm` / `codex` / `auth`) and stop — `auth` false means `!codex login`.
3. **Resolve one state file path, used by both directions.** A relative path breaks when the return
   leg runs from a different directory, so anchor it to the repo root and create the parent:
   ```bash
   ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
   SESSION_LOG="$ROOT/.claude/codex-sessions.log"
   mkdir -p "$(dirname "$SESSION_LOG")"
   ```

## Direction A — Claude → Codex (no arguments)

4. **Resolve this session's transcript.** The plugin's auto-detection often fails with
   "Could not identify the current Claude transcript", so always pass `--source` explicitly:
   ```bash
   PROJ="$HOME/.claude/projects/$(pwd | sed 's|/|-|g')"
   TRANSCRIPT="$(ls -t "$PROJ"/*.jsonl 2>/dev/null | head -1)"
   ```
   **Print the resolved path and its mtime.** This picks the *most recently written* transcript for
   the current directory, which is this session — unless another session is live in the same
   directory. If several transcripts were touched in the last few minutes, say so and ask which
   before transferring; handing over the wrong conversation is confusing and wastes a large number
   of Codex tokens. (Transcripts are keyed by working directory, so a session started elsewhere
   lives under a different project folder.)
5. **Record the pre-handoff baseline** *before* Codex can touch anything — the return leg needs it
   to detect commits, not just working-tree edits:
   ```bash
   git rev-parse HEAD > "$ROOT/.claude/codex-baseline-head" 2>/dev/null || true
   ```
6. **Transfer, and capture the real session ID from the output** — do not write a placeholder, and
   do not record anything if the transfer failed:
   ```bash
   OUT="$(node "$CODEX_COMPANION" transfer --source "$TRANSCRIPT")" || { echo "$OUT"; exit 1; }
   echo "$OUT"
   SESSION_ID="$(printf '%s\n' "$OUT" | grep -oE '[0-9a-fA-F-]{36}' | head -1)"
   case "$SESSION_ID" in
     [0-9a-fA-F]*-*-*-*-*) printf '%s\t%s\n' "$(date -u +%FT%TZ)" "$SESSION_ID" >> "$SESSION_LOG" ;;
     *) echo "Could not parse a session ID from the transfer output — not recording."; exit 1 ;;
   esac
   ```
7. **Report** the `codex resume <session-id>` command verbatim, and tell the user to run it with the
   `!` prefix (`! codex resume <id>`) so its output lands in this conversation, or in a plain
   terminal if they're switching away from Claude entirely.
8. Note honestly what transferred: the **turn history**, not the tool-call internals. Codex starts
   with the conversation, not with Claude's live state — no worktrees, no in-flight edits.

## Direction B — Codex → Claude (`back`)

There is no "transfer back" primitive: Claude Code can't be resumed *into* from Codex. What works is
having Codex summarise itself and ingesting that — which this does in one step.

9. **Read the session ID** from `$SESSION_LOG` (last field of the last line) and **validate it before
   putting it in a command line** — an unvalidated value containing shell metacharacters would
   execute:
   ```bash
   SESSION_ID="$(awk 'END{print $NF}' "$SESSION_LOG" 2>/dev/null)"
   case "$SESSION_ID" in
     [0-9a-fA-F]*-*-*-*-*) : ;;
     *) echo "No valid recorded session ID — ask the user for one."; exit 1 ;;
   esac
   ```
10. **Ask Codex for a handoff brief, forced read-only.** `codex exec` defaults to read-only, but user
    or project config can set `sandbox_mode` to `workspace-write`/`danger-full-access`, and a
    summarise-only call must never write. Note `codex exec resume` rejects `--sandbox` (that flag is
    `codex exec` only) but **does** accept `-c`, and always quote the ID:
    ```bash
    codex exec resume "$SESSION_ID" -c sandbox_mode="read-only" "Summarise for a Claude Code session taking over from you: (1) what you changed, file by file; (2) what you verified and how; (3) what is still unfinished or uncertain; (4) any decision a reviewer would question. Be specific and terse. Do not re-explain the original task."
    ```
11. **Verify against reality rather than trusting the summary — and check all four kinds of change.**
    `git diff` alone sees only unstaged edits, so a clean worktree can hide work Codex **committed**:
    ```bash
    BASE="$(cat "$ROOT/.claude/codex-baseline-head" 2>/dev/null)"
    [ -n "$BASE" ] && git log --oneline "$BASE"..HEAD        # commits Codex made
    [ -n "$BASE" ] && git diff --stat "$BASE"..HEAD          # net committed change
    git diff --stat                                          # unstaged
    git diff --cached --stat                                 # staged
    git status --short                                       # includes untracked
    ```
    Reconcile: a file Codex claims to have changed that appears in none of these, or a changed file
    it didn't mention, is the finding. Report mismatches explicitly.
12. Summarise for the user: what Codex did, what you confirmed independently, and what still needs
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
  runs an automated loop — it makes every stop wait on a Codex review.
