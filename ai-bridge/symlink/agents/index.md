# Agent Roster & Routing

The roles the Project Manager can assign tasks to. Executable definitions live
in `.claude/agents/<role>.md`; this is the routing reference.

> **Generic template file** (symlinked from the `ai-bridge` template).

## Roles
* [project-manager](/.claude/agents/project-manager.md) - orchestrator: refines, assigns, reviews, curates. Not a task assignee.
* [software-engineer](/.claude/agents/software-engineer.md) - features and bug fixes in product code
* [devops-engineer](/.claude/agents/devops-engineer.md) - CI/CD, GitHub Actions, Helm, ArgoCD, Terraform, Docker images, observability
* [qa-reviewer](/.claude/agents/qa-reviewer.md) - writing/extending tests and reviewing PRs (the quality gate)
* [cataloguer](/.claude/agents/cataloguer.md) - librarian for the knowledge base (service catalog, findings, runbooks); read-only on product repos. Not a task assignee.
* [oncall-guide](/.claude/agents/oncall-guide.md) - read-only diagnostician for a failing build / red CI / failed deploy (incl. from a pasted PR). Reports root cause + ranked next steps; never changes code. Dispatched ad-hoc (usually in the background). Not a task assignee.

## Routing guide

| If the task is about… | assignee |
|---|---|
| Application code, APIs, business logic, bug fixes | `software-engineer` |
| Pipelines, workflows, infra, deploys, images, monitoring | `devops-engineer` |
| Tests, verification against acceptance criteria, PR review | `qa-reviewer` |
| Diagnosing a red CI / build / failed deploy **without changing code** (incl. from a pasted PR) | `oncall-guide` (read-only, reports back) |

Notes:
- `oncall-guide` **diagnoses only** — it reports root cause + next steps and never
  opens a PR. When the fix is known, dispatch `devops-engineer` (CI/infra) or
  `software-engineer` (product code) to actually make it. It's usually fired in
  the **background** so the main session isn't blocked; not a task assignee.
- A task may benefit from a review pass by `qa-reviewer` after the implementing
  role opens its PR — the PM can chain these.
- No role merges. Merge is always the human's decision (`in-review` → `done`).
