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

The `SKILL.md` format is shared across the Claude surfaces — Claude Code CLI, the Claude desktop app, IDE extensions, and `claude.ai/code`. Keep skills generic (no project-specific paths, infer the toolchain from `package.json`) so the same folder works everywhere.
