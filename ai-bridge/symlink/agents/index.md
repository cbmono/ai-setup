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

## Routing guide

| If the task is about… | assignee |
|---|---|
| Application code, APIs, business logic, bug fixes | `software-engineer` |
| Pipelines, workflows, infra, deploys, images, monitoring | `devops-engineer` |
| Tests, verification against acceptance criteria, PR review | `qa-reviewer` |

Notes:
- A task may benefit from a review pass by `qa-reviewer` after the implementing
  role opens its PR — the PM can chain these.
- No role merges. Merge is always the human's decision (`in-review` → `done`).
