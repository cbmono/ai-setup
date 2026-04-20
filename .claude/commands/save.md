Save durable context from the current conversation, then compact.

## Steps

1. Review the conversation so far and identify anything worth persisting:
   - Decisions made (and the reasons behind them)
   - User preferences / feedback corrections
   - Project context not derivable from code or `git log`
   - External references (Linear projects, dashboards, Slack channels)
2. Save to the built-in memory system. Skip anything that's already in `CLAUDE.md`, obvious from code, or ephemeral (current task state).
3. If **mempalace** is installed (`which mempalace`), also run `mempalace mine` on the current session's transcript so verbatim content is indexed locally. See the top-level README for mempalace setup.
4. Run `/compact` to compress the conversation.

Keep memory entries specific. "User prefers pnpm" beats "user has preferences about tooling".
