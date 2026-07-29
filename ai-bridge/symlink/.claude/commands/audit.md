---
description: Run the slow-cadence audit loop — the counter-metric that grounds objectives against reality and flags Goodhart drift, stale knowledge, and green-but-not-progressing work. The audit agent is read-only; the command's only write is prepending its report to log.md; never promotes, merges, or dispatches.
allowed-tools: Bash(pwd), Bash(ls:*), Bash(date:*), Read, Edit, Agent
---

Run one **audit pass** over this control-panel instance — the slow counter-metric loop
that complements `/pm-loop`. It is **read-only**: it surfaces drift, it never promotes,
merges, dispatches, or changes task status.

## Preconditions
Run from a control-panel instance root — confirm `SCHEMA.md`, `.claude/agents`, and
`instance.config.json` exist in the cwd; if not, tell the user to `cd` into the instance
and stop.

## Steps
1. Read `instance.config.json`. **Resolve the auditor's model** the same way the PM
   routes dispatches: look up `auditor` in `roleTiers` (default `deep`), map it to an
   alias via `models`; if those maps are absent, inherit the session model.
2. Dispatch the **`auditor`** agent (`subagent_type: auditor`) for one pass, passing the
   resolved model. It's read-only — it grounds each objective's `success_criteria`
   against live `gh`/`git` reality, flags the four drift modes (Goodhart · measurement
   decay · green-but-not-progressing · weakened anchors), and **returns** a dated audit
   report (it writes nothing itself).
3. **Persist it.** Prepend the returned report as a dated `## Audit — <date>` entry to
   the root `log.md` (date via `date -u +%Y-%m-%d`).
4. Relay its verdict + findings. These are **advisory** — acting on them (adjusting
   objectives/targets, re-validating stale findings, unwinding a Goodharted metric) is
   your governance call; the audit never does it for you.

## Cadence
This is a **slow** loop — run it weekly, or after a batch of projects close, not every
tick. It can be scheduled to run periodically (e.g. a cron job or your scheduler of
choice). It changes no task state, but it **prepends to `log.md`** — as does each `/pm-loop`
tick — so run it **between** ticks, not concurrently, to avoid a write race on that file.
