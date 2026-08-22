---
paths:
  - "/knowledge/**"
---

# Knowledge base

Loads when you read anything under `knowledge/`. The instance `CLAUDE.md` keeps
the index-first rule itself, because "scan the index before you research" has to
be in context *before* the first read — by the time this file loads you are
already reading a `knowledge/` doc.

- `knowledge/` is an OKF knowledge base in this bundle — a `Service` catalog,
  `Finding`s (decisions/learnings), `Runbook`s, `Team`s, and `Reference`s
  (durable specs/contracts) (see `SCHEMA.md`).
- The `cataloguer` agent builds/refreshes it (read-only on product repos); task
  agents **capture `Finding`s as a byproduct** of their work and link them from
  the task.
- **Use it index-first, to avoid re-deriving what's already known.** Before
  researching or implementing, scan `knowledge/index.md` (a compact one-line-per-
  entry catalog) for the service/area you're touching, then open only the 1–3
  specific `Finding`s / `Service` / `Runbook` / `Team` docs that match — **never bulk-read
  `knowledge/`**. If a relevant `Finding` already answers a question, cite it and
  move on. The KB is **pull-based** (read on demand); it is deliberately *not*
  auto-loaded into context, so it never bloats a session.
