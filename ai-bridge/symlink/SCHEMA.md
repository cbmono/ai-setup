---
type: Reference
title: OKF Producer Types & Status Reference
description: Custom concept types and the task lifecycle used by this control panel.
timestamp: 2026-06-18T00:00:00Z
---

OKF defines no task/project/objective/agent constructs — they are
producer-defined extensions. This document is the contract for the custom
`type`s and frontmatter fields used in this bundle. All consumers must tolerate
missing optional fields and unknown keys (per the OKF spec).

> **Generic template file.** This file is symlinked from the `ai-bridge`
> template and is identical across every instance. Instance-specific values
> (`<org>`, the clone root, the author identity, team routing) live in
> `instance.config.json` and this instance's `CLAUDE.md` — never hardcode them here.

# Schema

## type: Objective  (`objectives/<slug>.md`)

```yaml
---
type: Objective
title: <short goal>
description: <one line>
status: active | paused | achieved | dropped
success_criteria: [ "<measurable signal>", ... ]   # optional
timestamp: <ISO 8601>
---
```

## type: Project  (`projects/<slug>/project.md`)

```yaml
---
type: Project
title: <project name>
description: <one line>
kind: build | research                # build = ships code via PRs (default); research = produces in-bundle deliverables
objective: /objectives/<slug>.md      # link up to the objective it serves
target_repo: <org>/<repo>             # BUILD only: default repo for this project's tasks (<org> from instance.config.json). Omit for research.
deliverables: [ "<artifact>", ... ]   # RESEARCH only: what this project produces, e.g. "tech landscape per domain (md)", "exec summary deck (marp)"
status: active | paused | done
timestamp: <ISO 8601>
---
```

**Two kinds of project.** `kind: build` (default) ships changes to a product repo
as PRs, executed by role agents — the full `draft → ready → dispatch → PR → merge`
loop. `kind: research` produces **deliverables inside this bundle** (markdown,
marp/pptx decks, assets) — strategic/discovery work that has no `target_repo` and
opens no PRs, and is often the **entry point** whose conclusions graduate into
`knowledge/` and spawn new objectives and build projects. Research artifacts live
under `projects/<slug>/deliverables/` (one file per chunk — e.g. per domain/team).
Research tasks are **human-driven**: the PM refines and tracks them but never
dispatches them to role agents (see the lifecycle note).

## type: Phase  (`projects/<slug>/phases/<n>-<slug>.md`)

For large projects sliced into sequential stages.

```yaml
---
type: Phase
title: <phase name>
description: <one line>
project: /projects/<slug>/project.md
order: 1                              # sequence within the project
status: not-started | active | done
depends_on: [ /projects/<slug>/phases/<prev>.md ]   # optional
exit_criteria: [ "<what must be true to close the phase>", ... ]
timestamp: <ISO 8601>
---
```

## type: Task  (`projects/<slug>/tasks/<id>.md`)

```yaml
---
type: Task
title: <imperative summary>
description: <one line>
kind: build | research                # inherits the project's kind if omitted
status: draft                         # initial state; see lifecycle below
assignee:                             # BUILD: role slug set by PM (software-engineer | devops-engineer | qa-reviewer). RESEARCH: usually empty (human-driven)
target_repo: <org>/<repo>             # BUILD only: inherits project default if omitted
objective: /objectives/<slug>.md
phase: /projects/<slug>/phases/<n>-<slug>.md          # optional, links task to its phase
depends_on: [ /projects/<slug>/tasks/<id>.md, ... ]   # optional
acceptance_criteria: [ "<testable outcome>", ... ]    # PM fills/expands during refine
open_questions: [ "Q1: <blocking question for the human>", "Q2: ...", ... ]   # PM-managed; number every entry (Q1, Q2, …) so the human can answer by number
pr: [ ]                               # BUILD only: PR URL(s) set by the role agent(s) — a task may fan out to several
artifacts: [ /projects/<slug>/deliverables/<file>, ... ]   # RESEARCH only: the deliverable file(s) this task produces
timestamp: <ISO 8601>
---
```

The task **body** uses these conventional headings: `# Context`, `# Notes`
(PM refinement notes), `# Result` (role agent summary, or — for research — a
pointer to the finished deliverable(s) on completion).

## type: Agent  (`agents/index.md` lists the roster)

Executable definitions live in `.claude/agents/<role>.md`. The roster doc is a
human-readable routing reference.

## Knowledge base types  (`knowledge/`)

OKF's native use: curated knowledge about systems and decisions. The `knowledge/`
section is part of this bundle, so its docs cross-link freely to/from objectives,
projects, and tasks. **No customer PII** in any knowledge doc; authoritative
*data* questions route to the owning team (see `knowledge/teams/`), not the KB.

### type: Service  (`knowledge/services/<name>.md`)

```yaml
---
type: Service
title: <service name>
description: <one line>
repo: <org>/<repo>                # owning repo (or monorepo)
path: services/<name>             # path within a monorepo, if applicable
owner:                            # team / person, optional
stack: [ <framework>, <orm>, ... ]
runtime: node-<major>
status: active | deprecated
timestamp: <ISO 8601>
---
```
Body headings: `# Overview`, `# Stack & data`, `# Dependencies`, `# Notes`.

### type: Finding  (`knowledge/findings/<slug>.md`)

A durable learning or architecture decision (ADR-style).

```yaml
---
type: Finding
title: <the statement / decision>
description: <one line>
category: decision | learning | gotcha
status: current | superseded
source:                           # where it came from, e.g. /projects/.../tasks/<id>.md or a PR URL
timestamp: <ISO 8601>
---
```
Body headings: `# Context`, `# Finding` (or `# Decision`), `# Rationale`,
`# Implications`. Link to the Services/tasks it concerns.

### type: Team  (`knowledge/teams/<slug>.md`)

Who owns what. Used to route questions and clarify responsibility boundaries.

```yaml
---
type: Team
title: <team name>
description: <one line>
owns: [ <system/area>, ... ]          # what this team is the authority for
contact:                              # lead / channel, optional — no PII beyond work contact
timestamp: <ISO 8601>
---
```
Body headings: `# Responsibilities`, `# Owns`, `# Contact`, `# Notes`.

### type: Runbook  (`knowledge/runbooks/<slug>.md`)

```yaml
---
type: Runbook
title: <procedure>
description: <one line>
applies_to: [ <service or area>, ... ]
timestamp: <ISO 8601>
---
```
Body headings: `# When to use`, `# Steps`, `# Verification`, `# References`.

# Task lifecycle

```
draft ──│ HUMAN promotes │──► ready ──► in-progress ⇄ in-review ──► done
                                            └─ changes requested ─┘

  · a `draft` with non-empty open_questions is blocked on a human answer
  · any active state ⇄ blocked     (returns to its prior status when cleared)
  · any state ──► cancelled        (terminal: abandoned / superseded / decided-against)
```

| Status | Meaning | Who sets it |
|---|---|---|
| `draft` | **Initial state.** Refined once `acceptance_criteria` are filled; **awaiting human approval**. Non-empty `open_questions` = blocked on a human answer (don't promote). | Human or PM |
| `ready` | **Human-approved for execution — ONLY the human sets this.** | Human only |
| `in-progress` | Dispatched to a role; agent is working (no PR yet, or changes requested). | PM (on dispatch) / role agent |
| `in-review` | PR(s) open, awaiting review/merge. Returns to `in-progress` if review requests changes. | Role agent |
| `blocked` | External / dependency blocker; returns to its prior status when cleared. | Anyone |
| `cancelled` | Abandoned, superseded, or decided-against (terminal). | Human / PM |
| `done` | **All** of the task's PR(s) merged. | PM (reflects merge) / Human |

**Multi-PR tasks.** A task may fan out to several PRs (e.g. one per service); `pr:`
is a list. It stays `in-progress`/`in-review` until **all** its PRs merge, then
`done`. Keep per-PR detail in the `# Result` section.

**Two human authorities** keep this semi-autonomous:
1. **Promote `draft → ready`** — the only way work enters execution. The PM must **never** set `ready`.
2. **Merge the PR(s)** — the PM only *reflects* a merge by setting `done`; it never merges.

**Research tasks (`kind: research`) are human-driven.** Same statuses, but no PRs
and no role-agent dispatch — the human (with Claude in-session) produces the
deliverable. The PM still **refines** them (turns `deliverables` into concrete
`acceptance_criteria`, surfaces `open_questions`) and **tracks/reflects** status,
but **never dispatches** them. The mapping: `ready` = approved to work on now;
`in-progress` = being drafted; `in-review` = a draft deliverable is up for human
review; `done` = the deliverable is **approved** (record paths in `artifacts:` and
point to them from `# Result`). Approval of the deliverable replaces the merge gate.

Everything between `ready` and `done` is the PM's to drive autonomously.
