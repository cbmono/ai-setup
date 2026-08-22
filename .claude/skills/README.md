# Skills

Auto-invocable capabilities for Claude. Unlike [commands](../commands/) (explicit `/<name>` invocation), skills are matched against user intent — Claude decides when to fire based on the skill's `description`.

## Layout

```
.claude/skills/
  <skill-name>/
    SKILL.md                          # required — YAML frontmatter + body
    [supporting files, scripts, prompts, etc.]
```

`SKILL.md` frontmatter:

```yaml
---
name: my-skill
description: One-line trigger description — Claude matches user intent against this
---
```

The body of `SKILL.md` is the prompt Claude receives when the skill fires.

## Skills vs. commands

This repo ships mostly [commands](../commands/) — they're explicit, deterministic, and require typing `/<name>`. Reach for a skill here only when proactive invocation is genuinely wanted (i.e. you'd rather have Claude auto-trigger on intent than wait for the slash). See [`.claude/README.md`](../README.md) for the full distinction.

**Shipped here:** `test-locators` — adds stable E2E test attributes (`data-testid`/`data-test`) while building frontend. It's a skill rather than a command precisely because it should fire automatically during UI work, not on a typed `/<name>`.

## Portability

**Skills here are allow-listed one by one in the root `.gitignore`, unlike the other `.claude/` directories.** This one is a *drop-in* directory — installing any third-party skill creates a subdirectory here — so a bare re-include meant `git add -A -- .claude` swept four uninvited ones into this public repo, three of them symlinks to a `.agents/` path that exists under `~/.claude` but not here, i.e. dead links. Since `install.sh` discovers what to link with `git ls-files .claude`, anything tracked here lands in **every consumer's** `~/.claude/skills/`. So adding a `!` line for a skill is the deliberate act of shipping it to everyone; `tests/skills-allowlisted.test.sh` is what notices when it happens by accident instead.

The `SKILL.md` format is shared across the Claude surfaces — Claude Code CLI, the Claude desktop app, IDE extensions, and `claude.ai/code`. Keep skills generic (no project-specific paths, infer the toolchain from `package.json`) so the same folder works everywhere.
