---
description: Find a set of related open, green PRs and draft a grouped review-request message; optionally post it to Slack if a Slack MCP is configured
argument-hint: <pr-filter>  e.g. "unit-test-split"  |  "title:apollo"  |  "1722 1723 1724"  [repo=<name|owner/name>]
allowed-tools: Bash(gh pr list:*), Bash(gh pr view:*)
---

Build a grouped review-request message for a set of related open, green PRs.
**Posting to Slack is optional** — the command's core job is finding/filtering the
PRs and drafting the message; if no Slack MCP is configured it just hands you the
final text to paste.

> **Generic template file** (symlinked from the `ai-bridge` template). It
> reads the target org, default repo, and (optional) Slack channel from this
> instance's `instance.config.json` — never hard-code those here.

## Config (read from `<repo-root>/instance.config.json`)
- `org` — GitHub org; a bare `repo=<name>` is qualified to `<org>/<name>`.
- `defaultRepo` — optional. The repo to use when `$ARGUMENTS` carries no `repo=`
  token. May be a bare name (qualified with `org`) or full `owner/name`. If
  unset and no `repo=` is given, **ask** which repo before doing anything.
- `prReviewSlackChannel` — **optional.** The target channel for auto-posting (a
  channel **name** or **id**). Auto-posting also requires a **Slack MCP** to be
  available in this session (e.g. `mcp__*slack*__*send*` tools). If either is
  missing, the command still drafts the message and you post it yourself.

## Input

`$ARGUMENTS` selects the PRs. Interpret it as one of:
- **Branch/title substring** (default), e.g. `unit-test-split` → match open PRs
  whose **head branch** contains it; if zero match, retry against the **title**.
- **`title:<text>`** → match on PR title only.
- **Explicit PR numbers**, e.g. `1722 1723 1724` → use exactly those.
- An optional `repo=<name|owner/name>` token overrides the repo for this run.

If `$ARGUMENTS` is empty, ask the user which PRs (pattern or numbers) before doing anything.

## Steps

1. **Resolve the repo** from `instance.config.json` + `$ARGUMENTS` (qualify a bare
   name with `org`). The Slack channel is only needed if you'll auto-post (step 6).

2. **Find candidates** with `gh pr list --repo <repo> --state open --limit 100
   --json number,title,headRefName,url,state` and apply the filter above.

3. **Filter out anything not postable** — fetch fresh per-PR state with
   `gh pr view <n> --repo <repo> --json number,state,headRefName,url,statusCheckRollup`:
   - **Drop `state != OPEN`** (merged/closed) — merges happen live, so always
     re-check; never trust a list snapshot.
   - **Drop "not green"** = any check in `statusCheckRollup` with `conclusion` in
     `FAILURE`, `CANCELLED`, `TIMED_OUT`, or `ACTION_REQUIRED`, **or** any
     `status` still `IN_PROGRESS`/`QUEUED` for a real CI job.
   - **Do NOT** count as failures: `SUCCESS`, `SKIPPED`, `NEUTRAL`, and ambient
     non-gating statuses that report `status=null` (these vary by org — e.g.
     external CI bridges or review bots that appear even on merged PRs). Treat a
     PR with zero real failures/in-progress jobs as green.

4. **Build the message.** Derive a short per-PR label from the head branch
   (strip a common `<prefix>/<service>-<suffix>` pattern to the service name,
   e.g. `perf/claim-unit-test-split` → `claim`); fall back to the PR title if no
   clean label. One bullet per PR: `• <label> — <url>`. Lead with a one-line
   purpose inferred from the shared title prefix. Keep it tight; **no PII**.

5. **Show the draft to the user and STOP for confirmation.** List exactly which
   PRs are included and which were dropped (with reason: merged / failing /
   pending). Do not post yet.

6. **Deliver the message.**
   - **If a Slack MCP is available *and* a channel is resolved** (`prReviewSlackChannel`
     or one the user names): on the user's go-ahead, post via the MCP's
     send-message tool (resolve the channel id from a name first if the MCP offers
     a search tool). Return the permalink. If the user says "draft" instead, use
     the MCP's draft tool if it has one.
   - **Otherwise** (no Slack MCP, or no channel): print the final message in a
     copy-paste block and stop — that's the deliverable. Mention once that
     auto-posting can be enabled by adding a Slack MCP server to
     `.claude/settings.local.json` and setting `prReviewSlackChannel` in
     `instance.config.json` (don't nag on later runs).

## Notes
- `mergeable=MERGEABLE` only means no merge conflict — it is **not** CI status.
  Always read `statusCheckRollup`.
- Posting is outward-facing: never skip the confirmation gate in step 5.
- Slack is **optional**. Never fail the command for a missing Slack MCP — fall
  back to handing the user the drafted message.
