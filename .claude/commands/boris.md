Boris Cherny's Claude Code workflow tips — parallel sessions, plan mode, subagents, hooks, permissions, MCP, auto-memory. Reference doc; use for learning and optimizing your Claude Code workflow.

# Boris Cherny's Claude Code Workflow Tips

_Source: howborisusesclaudecode.com · Compiled by @cbmono · Version 3.1.0 (2026-04-20)_

## 1. Parallel Execution

### Run Multiple Claude Sessions in Parallel

The single biggest productivity unlock. Spin up 3-5 git worktrees at once, each running its own Claude session.

```bash
# Create a worktree
git worktree add .claude/worktrees/my-worktree origin/main

# Start Claude in it
cd .claude/worktrees/my-worktree && claude
```

**Why worktrees over checkouts:** The Claude Code team prefers worktrees - it's why native support was built into the Claude Desktop app.

**Pro tips:**

- Name your worktrees and set up shell aliases (za, zb, zc) to hop between them in one keystroke
- Have a dedicated "analysis" worktree just for reading logs and running BigQuery
- Use iTerm2/terminal notifications to know when any Claude needs attention
- Color-code and name your terminal tabs, one per task/worktree

### Web and Mobile Sessions

Beyond the terminal, run additional sessions on claude.ai/code. Use:

- `&` command to background a session
- `--teleport` flag to switch contexts between local and web
- Claude iOS app to start sessions on the go, pick them up on desktop later

---

## 2. Model Selection

### Pick the Right Model for the Job

Use **Opus 4.7 (1M context)** in Plan mode for deeper reasoning and the largest context window. Use **Sonnet 4.6** for fast, cost-effective implementation of scoped work.

Opus 4.7 introduces adaptive thinking (see section 17a) — extended-thinking fixed budgets are no longer supported, and effort level is set via `/model` rather than per-turn.

---

## 3. Plan Mode

### Start Every Complex Task in Plan Mode

Press `shift+tab` to cycle to plan mode. Pour your energy into the plan so Claude can 1-shot the implementation.

**Workflow:** Plan mode -> Refine plan -> Auto-accept edits -> Claude 1-shots it

**Team patterns:**

- One person has one Claude write the plan, then spins up a second Claude to review it as a staff engineer
- The moment something goes sideways, switch back to plan mode and re-plan
- Explicitly tell Claude to enter plan mode for verification steps, not just for the build

"A good plan is really important to avoid issues down the line."

---

## 4. CLAUDE.md Best Practices

### Invest in Your CLAUDE.md

Share a single CLAUDE.md file for your repo, checked into git. The whole team should contribute.

**Key practice:** "Anytime we see Claude do something incorrectly we add it to the CLAUDE.md, so Claude knows not to do it next time."

**After every correction:** End with "Update your CLAUDE.md so you don't make that mistake again." Claude is eerily good at writing rules for itself.

**Advanced:** One engineer tells Claude to maintain a notes directory for every task/project, updated after every PR. They then point CLAUDE.md at it.

### @.claude in Code Reviews

Tag @.claude on PRs to add learnings to the CLAUDE.md as part of the PR itself. Use the Claude Code GitHub Action (`/install-github-action`) for this.

Example PR comment:

```
nit: use a string literal, not ts enum

@claude add to CLAUDE.md to never use enums,
always prefer literal unions
```

This is "Compounding Engineering" - Claude automatically updates the CLAUDE.md with the learning.

---

## 5. Skills & Slash Commands

### Create Your Own Skills

Create skills and commit them to git. Reuse across every project.

**Team tips:**

- If you do something more than once a day, turn it into a skill or command
- Build a `/techdebt` slash command and run it at the end of every session to find and kill duplicated code
- Set up a slash command that syncs 7 days of Slack, GDrive, Asana, and GitHub into one context dump
- Build analytics-engineer-style agents that write dbt models, review code, and test changes in dev

### Slash Commands for Inner Loops

Use slash commands for workflows you do many times a day. Commands are checked into git under `.claude/commands/` and shared with the team.

```
> /commit-push-pr
```

**Power feature:** Slash commands can include inline Bash to pre-compute info (like git status) for quick execution without extra model calls.

---

## 6. Subagents

### Use Subagents for Common Workflows

Think of subagents as automations for the most common PR workflows:

```
.claude/
  agents/
    build-validator.md
    code-architect.md
    code-simplifier.md
    oncall-guide.md
    verify-app.md
    deep-bug-scan.md
```

**Examples:**

- `code-simplifier` - Cleans up code after Claude finishes
- `verify-app` - Detailed instructions for end-to-end testing

### Leveraging Subagents

- Append "use subagents" to any request where you want Claude to throw more compute at the problem
- Offload individual tasks to subagents to keep your main agent's context window clean and focused
- Route permission requests to Opus 4.5 via a hook - let it scan for attacks and auto-approve the safe ones

---

## 7. Hooks

### PostToolUse Hooks for Formatting

Use a PostToolUse hook to auto-format Claude's code. While Claude generates well-formatted code 90% of the time, the hook catches edge cases to prevent CI failures.

```json
"PostToolUse": [
  {
    "matcher": "Write|Edit",
    "hooks": [
      {
        "type": "command",
        "command": "bun run format || true"
      }
    ]
  }
]
```

### Stop Hooks for Long-Running Tasks

For very long-running tasks, use an agent Stop hook for deterministic checks, ensuring Claude can work uninterrupted.

---

## 8. Permissions

### Pre-Allow Safe Permissions

Instead of `--dangerously-skip-permissions`, use `/permissions` to pre-allow common safe commands. Most are shared in `.claude/settings.json`.

For sandboxed environments, use `--permission-mode=dontAsk` or `--dangerously-skip-permissions` to avoid blocks.

---

## 9. MCP Integrations

### Tool Integrations

Claude Code uses your tools autonomously:

- Searches and posts to **Slack** (via MCP server)
- Runs **BigQuery** queries with bq CLI
- Grabs error logs from **Sentry**

```json
{
  "mcpServers": {
    "slack": {
      "type": "http",
      "url": "https://slack.mcp.anthropic.com/mcp"
    }
  }
}
```

### Data & Analytics

Ask Claude Code to use the "bq" CLI to pull and analyze metrics on the fly. Have a BigQuery skill checked into the codebase.

Boris's take: "Personally, I haven't written a line of SQL in 6+ months."

This works for any database that has a CLI, MCP, or API.

---

## 10. Prompting Tips

### Challenge Claude

- Say "Grill me on these changes and don't make a PR until I pass your test."
- Say "Prove to me this works" and have Claude diff behavior between main and your feature branch

### After a Mediocre Fix

Say: "Knowing everything you know now, scrap this and implement the elegant solution."

### Write Detailed Specs

Reduce ambiguity before handing work off. The more specific you are, the better the output.

**Key insight:** Don't accept the first solution. Push Claude to do better - it usually can.

---

## 11. Terminal Setup

### Recommended Tools

- **Ghostty** terminal - synchronized rendering, 24-bit color, proper unicode support
- Use `/statusline` to customize your status bar to always show context usage and current git branch

---

## 12. Bug Fixing

### Let Claude Fix Bugs

Enable the Slack MCP, then paste a Slack bug thread into Claude and just say "fix." Zero context switching required.

Or just say "Go fix the failing CI tests." Don't micromanage how.

**Pro tip:** Point Claude at docker logs to troubleshoot distributed systems - it's surprisingly capable at this.

---

## 13. Long-Running Tasks

### Handle Long-Running Tasks

For very long-running tasks, ensure Claude can work uninterrupted:

**Options:**

- **(a)** Prompt Claude to verify with a background agent when done
- **(b)** Use an agent Stop hook for deterministic checks
- **(c)** Use the "ralph-wiggum" plugin (community idea by @GeoffreyHuntley)

For sandboxed environments, use `--permission-mode=dontAsk` or `--dangerously-skip-permissions` to avoid blocks.

---

## 14. Verification (The #1 Tip)

### Give Claude a Way to Verify Its Work

"Probably the most important thing to get great results out of Claude Code - give Claude a way to verify its work. If Claude has that feedback loop, it will 2-3x the quality of the final result."

**Verification varies by domain:**

- Bash commands
- Test suites
- Simulators
- Browser testing (Claude Chrome extension)

The key is giving Claude a way to close the feedback loop. Invest in domain-specific verification for optimal performance.

---

## 15. Learning with Claude

### Use Claude for Learning

- Enable "Explanatory" or "Learning" output style in /config to have Claude explain the _why_ behind changes
- Have Claude generate visual HTML presentations explaining unfamiliar code
- Ask Claude to draw ASCII diagrams of new protocols and codebases
- Build a spaced-repetition learning skill: explain your understanding, Claude asks follow-ups to fill gaps

**Key takeaway:** Claude Code isn't just for writing code - it's a powerful learning tool when you configure it to explain and teach.

---

## 16. Auto-Memory & Auto-Dream — Persistent, Self-Cleaning Memory

Claude Code has a built-in memory system. Run `/memory` to configure it.

**Auto-memory:** When enabled, Claude automatically saves preferences, corrections, and patterns between sessions. User memory goes to `~/.claude/CLAUDE.md`, project memory to `./CLAUDE.md`.

**Auto-dream:** As memory accumulates, it can get messy — outdated assumptions, overlapping notes, low-signal entries. Auto-dream runs a subagent that periodically reviews past sessions, keeps what matters, removes what doesn't, and merges insights into cleaner structured memory. Run `/dream` to trigger manually, or enable auto-dream in `/memory` settings.

The naming maps to how REM sleep consolidates short-term memory into long-term storage.

---

## 17. Effort Level

### Adjust Effort Level

Run `/model` to pick your preferred effort level. Opus 4.7 exposes five tiers:

- **`low` / `medium`** — cost- and latency-sensitive work. Still beats Opus 4.6 at equivalent settings.
- **`high`** — balance intelligence and cost; good for multiple concurrent sessions.
- **`xhigh`** _(default)_ — "Best setting for most coding and agentic uses." Strong autonomy without runaway tokens.
- **`max`** — reserve for genuinely hard problems (gnarly debugging, architecture decisions). Diminishing returns vs `xhigh` in most cases.

Don't port old effort configurations blindly — experiment with `xhigh` before assuming you need `max`.

---

## 17a. Adaptive Thinking (Opus 4.7)

Opus 4.7 decides per-step whether to think. You steer it by prompting, not by setting a fixed thinking budget.

- **More thinking:** "Think carefully and step-by-step before responding; this problem is harder than it looks."
- **Less thinking:** "Prioritize responding quickly rather than thinking deeply. When in doubt, respond directly."

### Behavior changes worth knowing

- **Reduced tool invocation.** 4.7 calls tools less and reasons more. If you want aggressive search or file reading, say so explicitly: "Grep the repo thoroughly before answering — don't rely on memory."
- **Judicious subagent spawning.** 4.7 delegates less often than 4.6. Spell out parallelization: "Spawn multiple subagents in the same turn when fanning out across items or reading multiple files."
- **Response length calibrates to task.** Explicitly state preferred length/style in prompts using positive examples.
- **Front-load the spec.** Every user turn adds reasoning overhead. State intent, constraints, acceptance criteria, and file locations in the first turn.
- **Batch interactions.** Consolidate questions. Prefer one rich prompt over five narrow follow-ups.

---

## 18. Plugins

### Install Plugins, MCPs, and Skills

Plugins let you install LSPs (now available for every major language), MCPs, skills, agents, and custom hooks.

Install a plugin from the official Anthropic plugin marketplace, or create your own marketplace for your company. Then, check the `settings.json` into your codebase to auto-add the marketplaces for your team.

Run `/plugin` to get started.

---

## 19. Custom Agents

### Create Custom Agents

Drop `.md` files in `.claude/agents`. Each agent can have a custom name, color, tool set, pre-allowed and pre-disallowed tools, permission mode, and model.

**Little-known feature:** Set the default agent used for the main conversation. Just set the `"agent"` field in your `settings.json` or use the `--agent` flag.

Run `/agents` to get started.

---

## 20. Permissions Management

### Pre-Approve Common Permissions

Claude Code uses a sophisticated permission system with prompt injection detection, static analysis, sandboxing, and human oversight.

Out of the box, we pre-approve a small set of safe commands. To pre-approve more, run `/permissions` and add to the allow and block lists. Check these into your team's `settings.json`.

**Wildcard syntax:** We support full wildcard syntax. Try `"Bash(bun run *)"` or `"Edit(/docs/**)"`.

---

## 21. Sandboxing

### Enable Sandboxing

Opt into Claude Code's open source sandbox runtime to improve safety while reducing permission prompts.

Run `/sandbox` to enable it. Sandboxing runs on your machine, and supports both file and network isolation.

**Modes:**

- Sandbox BashTool, with auto-allow
- Sandbox BashTool, with regular permissions
- No Sandbox

---

## 22. Status Line

### Add a Status Line

Custom status lines show up right below the composer. Show model, directory, remaining context, cost, and anything else you want to see while you work.

Everyone on the Claude Code team has a different statusline. Use `/statusline` to get started — Claude will generate one based on your `.bashrc`/`.zshrc`.

---

## 23. Keybindings

### Customize Your Keybindings

Every key binding in Claude Code is customizable. Run `/keybindings` to re-map any key. Settings live reload so you can see how it feels immediately.

Keybindings are stored in `~/.claude/keybindings.json`.

---

## 24. Hooks (Advanced)

### Set Up Hooks

Hooks are a way to deterministically hook into Claude's lifecycle. Use them to:

- Automatically route permission requests to Slack or Opus
- Nudge Claude to keep going when it reaches the end of a turn (you can even kick off an agent or use a prompt to decide whether Claude should keep going)
- Pre-process or post-process tool calls, e.g. to add your own logging

Ask Claude to add a hook to get started.

---

## 25. Spinner Verbs

### Customize Your Spinner Verbs

It's the little things that make CC feel personal. Ask Claude to customize your spinner verbs to add or replace the default list with your own verbs.

Check the `settings.json` into source control to share verbs with your team.

---

## 26. Output Styles

### Use Output Styles

Run `/config` and set an output style to have Claude respond using a different tone or format.

- **Explanatory** — great when getting familiar with a new codebase, to have Claude explain frameworks and code patterns as it works
- **Learning** — have Claude coach you through making code changes
- **Custom** — create your own output styles to adjust Claude's voice the way you like

---

## 27. Customize Everything

### Customize All the Things!

Claude Code is built to work great out of the box. When you do customize, check your `settings.json` into git so your team can benefit, too.

We support configuring for your codebase, for a sub-folder, for just yourself, or via enterprise-wide policies.

**By the numbers:** 37 settings and 84 env vars. Use the `"env"` field in your `settings.json` to avoid wrapper scripts.

---

## 28. Built-in Git Worktree Support

### Use `claude --worktree` for Isolation

Claude Code now has built-in git worktree support. Each agent gets its own worktree and can work independently, without interfering with other sessions.

```bash
# Start Claude in its own worktree
claude --worktree my_worktree

# Optionally launch in its own Tmux session too
claude --worktree my_worktree --tmux
```

**Desktop app:** Head to the Code tab in the Claude Desktop app and check the **worktree** checkbox.

### Subagents Support Worktrees

Subagents can also use worktree isolation to do more work in parallel. This is especially powerful for large batched changes and code migrations. Available in CLI, Desktop app, IDE extensions, web, and Claude Code mobile app.

**Example prompt:** "Migrate all sync io to async. Batch up the changes, and launch 10 parallel agents with worktree isolation. Make sure each agent tests its changes end to end, then have it put up a PR."

### Custom Agents with Worktree Isolation

Make subagents always run in their own worktree by adding `isolation: worktree` to your agent frontmatter:

```yaml
# .claude/agents/worktree-worker.md
---
name: worktree-worker
model: haiku
isolation: worktree
---
```

### Non-Git Source Control

Mercurial, Perforce, or SVN users can define `WorktreeCreate` and `WorktreeRemove` hooks in `settings.json` to benefit from isolation without Git.

---

## 29. /simplify — Improve Code Quality

Use parallel agents to improve code quality, tune code efficiency, and ensure CLAUDE.md compliance. Append `/simplify` to any prompt after making changes.

```
> hey claude make this code change then run /simplify
```

Boris uses this daily to shepherd PRs to production. The skill runs parallel agents that review changed code for reuse, quality, and efficiency — all in one pass.

---

## 30. /batch — Parallel Code Migrations

Interactively plan out code migrations, then execute in parallel using dozens of agents. Each agent runs with full isolation using git worktrees, testing its work before putting up a PR.

```
> /batch migrate src/ from Solid to React
```

You plan the migration interactively, then `/batch` fans out the work to parallel agents — each in its own worktree, each testing and creating a PR independently.

---

## 31. /loop — Schedule Recurring Tasks

Use `/loop` to schedule recurring tasks for up to 3 days at a time. Claude runs your prompt on an interval, handling long-running workflows autonomously.

```
> /loop babysit all my PRs. Auto-fix build issues and when comments come in, use a worktree agent to fix them
```

```
> /loop every morning use the Slack MCP to give me a summary of top posts I was tagged in
```

Use it for PR babysitting, Slack summaries, deploy monitoring, or any repeating workflow.

## 32. Code Review — Agents Hunt for Bugs

When a PR opens, Claude dispatches a team of agents to hunt for bugs. Anthropic built it for themselves first — code output per engineer is up 200% this year, and reviews were the bottleneck.

Each agent focuses on a different concern — logic errors, security issues, performance regressions — then posts inline comments directly on the PR. Boris personally used it for weeks before launch; it catches real bugs he wouldn't have noticed otherwise.

## 33. /btw — Ask Questions While Claude Works

A slash command for side-chain conversations while Claude is actively working. Single-turn, no tool calls, but has full context of the conversation.

```
> /btw what does the retry logic do?
```

Claude responds inline without stopping its work. Built by @ErikSchluntz as a side project — 1.5M views on the launch tweet.

## 34. /effort — Per-Session Effort

Activate a higher effort level for a session with `/effort <level>`. On Opus 4.7 the levels are `low`, `medium`, `high`, `xhigh` (default), `max` — see section 17 for when to use which.

```
> /effort max
```

`max` burns usage faster; scope it to a session rather than leaving it on globally.

## 35. Remote Control — Spawn New Sessions

Run `claude remote-control` and spawn a new local session from the mobile app. Available on Max, Team, and Enterprise (v2.1.74+).

```bash
$ claude remote-control
# Open Claude mobile app → tap "Code" → start new session
```

Walk away from your desk, think of something, kick off a task from mobile — Claude runs on your machine.

## 36. Voice Mode

Voice mode is now rolled out to 100% of users, including Claude Code Desktop and Cowork. Click the microphone icon and talk naturally.

Useful for hands-free coding, dictating complex requirements, or when you think faster than you type.

## 37. Setup Scripts for Cloud Environments

Add a setup script in Claude Code on web and desktop. It runs before Claude Code launches on a cloud environment — install dependencies, configure settings, set env vars.

```bash
# Setup script (runs on new session start, skipped on resume):
#!/bin/bash
yarn install
```

Particularly useful for installing dependencies, settings, and configs before Claude starts working.

## 38. claude --name — Name Your Sessions

Name your session at launch with the `--name` flag.

```bash
$ claude --name "auth-refactor"
```

Especially useful when juggling multiple worktrees or sessions — you can tell at a glance which session is doing what.

---

## 39. Auto Session Naming After Plan Mode

After plan mode, Claude automatically names your session based on what you're working on. No manual naming needed.

Pairs well with `claude --name` — use `--name` when you know what you're doing upfront, let auto-naming handle it when you start by planning.

---

## 40. /color — Customize Prompt Color

Change the color of the prompt input with `/color`. When you have 3-5 sessions open in different terminals, color-coding them makes it instantly clear which is which.

```
> /color
```

---

## 41. PostCompact Hook

A new hook event that fires after Claude compresses its conversation context. Use it to re-inject critical instructions that might get lost during compaction, log when compaction happens, or trigger automation.

```json
"hooks": {
  "PostCompact": [{
    "matcher": "",
    "hooks": [{ "type": "command", "command": "echo 'Context was compacted'" }]
  }]
}
```

---

## 42. Auto Mode — Safer Permission Skipping

Instead of approving every file write and bash command, or skipping permissions entirely, auto mode lets Claude make permission decisions on your behalf. Classifiers evaluate each action before it runs — safe operations get auto-approved, risky ones still get flagged.

```bash
# Enable auto mode
claude --enable-auto-mode

# Or cycle with shift+tab during a session:
# plan mode → auto mode → normal mode
```

Boris's take: "no 👏 more 👏 permission prompts 👏"

---

## 43. /schedule — Cloud Jobs from Your Terminal

Use `/schedule` to create recurring cloud-based jobs for Claude, directly from the terminal. Unlike `/loop` (which runs locally for up to 3 days), scheduled jobs run in the cloud — they work even when your laptop is closed.

```
> /schedule a daily job that looks at all PRs shipped since yesterday
  and update our docs based on the changes. Use the Slack MCP to
  message #docs-update with the changes
```

The Anthropic team uses these internally to automatically resolve CI failures, push doc updates, and power automations that need to exist beyond a closed laptop.
