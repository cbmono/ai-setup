Grill the current changes before they become a PR. Fan out independent reviewers to attack your diff from every angle.

`/grill` reviews a **diff** — code you've already written, on its way to a PR. To grill an **approach** before any code exists, use `/plan` instead. (Same adversarial fan-out, different target: `/plan` attacks the reasoning, `/grill` attacks the change.)

## Steps

1. Read the diff: `git diff` and `git diff --cached`. If both are empty, say there's nothing to grill and stop.
2. If the diff is _only_ prose doc/config changes, skip the fan-out — there's nothing to attack. Note it and stop. **Embedded code counts as executable** — a changed `.md` carrying a fenced ` ```js `/` ```ts `/` ```sh ` block (e.g. a slash-command Workflow script) is in scope, even when every changed file is a `.md`.
3. **Grill the diff adversarially.** Reviewing your own diff self-anchors — you defend the choices you just made. Instead, fan out independent reviewer subagents, each a fresh context with one lens, none of them attached to the code. Synthesis stays with you (the main loop).

   **Size the grill to the diff** — this is the cost dial; don't throw 8 Opus reviewers at a one-file change. Announce the setup in one line and let the user retune before launching. Invoking `/grill` is your opt-in to run the Workflow, so don't ask *whether* — only let them change the model or lens set:
   - **Small** (a focused change — one file or one concern) → the core 4 lenses (★) on **Sonnet**.
   - **Large** (cross-cutting, multiple files/subsystems, or security-sensitive) → all 8 lenses on **Opus**.
   - e.g. *"Small diff → core 4 lenses on Sonnet. Say 'opus' or 'all 8' to widen, otherwise I'll launch."*

   The lenses (core 4 marked ★) — each reviewer gets exactly one:
   - ★ **correctness** — What input breaks this hunk? What edge case is assumed away (empty, null, boundary, large)?
   - ★ **failure_modes** — What happens on network error, disk full, parse error, null? Any swallowed error or unhandled rejection?
   - ★ **tests** — What does each test actually assert? Could it pass without the code under test doing anything? What path is untested?
   - ★ **architecture** — Layering, naming, dependency choices, abstraction shape. Does this fight the grain of the surrounding code?
   - **concurrency** — What if two callers hit this simultaneously? What if the request is retried? Any shared mutable state?
   - **observability** — How would we notice if this silently misbehaved in prod? Are the new failure paths logged/measured?
   - **scope** — What was added that the task didn't require? A premature abstraction, an unrelated refactor bundled in?
   - **security** — Untrusted input reaching a sink (SQL, shell, fs, HTML)? A missing authz check? A secret logged or committed?

   Build `args` from the gated decisions, then call the Workflow tool with the script below:
   - `args.diff` — the combined `git diff` + `git diff --cached` output (so every reviewer grills the same snapshot)
   - `args.projectRoot` — absolute project root (reviewers open surrounding files for context)
   - `args.model` — `'opus'` or `'sonnet'` (the size default, or the user's override)
   - `args.lenses` — array of `{key, prompt}` for the chosen subset (★ four, or all 8). Use the lens descriptions above as each `prompt`.

   ```js
   export const meta = {
     name: 'diff-grill',
     description: 'Adversarial fan-out review of the current diff across independent lenses, verifying blockers',
     phases: [
       { title: 'Grill', detail: 'one fresh reviewer per adversarial lens' },
       { title: 'Verify', detail: 'try to refute each blocker-severity finding' },
     ],
   }

   const FINDINGS = {
     type: 'object', required: ['findings'],
     properties: { findings: { type: 'array', items: {
       type: 'object',
       required: ['severity', 'location', 'issue', 'what_it_breaks', 'suggested_fix'],
       properties: {
         severity: { type: 'string', enum: ['blocker', 'concern'] },
         location: { type: 'string' },
         issue: { type: 'string' },
         what_it_breaks: { type: 'string' },
         suggested_fix: { type: 'string' },
       },
     } } },
   }
   const VERDICT = {
     type: 'object', required: ['refuted', 'reasoning'],
     properties: { refuted: { type: 'boolean' }, reasoning: { type: 'string' } },
   }

   // The runtime may hand `args` over as a JSON string — coerce before use.
   const a = typeof args === 'string' ? JSON.parse(args) : args
   if (!a.lenses || a.lenses.length === 0) throw new Error('diff-grill: a.lenses is empty — pass the chosen lens array')

   const reviews = await pipeline(
     a.lenses,
     // Stage 1: one independent reviewer per lens
     lens => agent(
       `You are an adversarial code reviewer. You did NOT write this diff and owe it no loyalty.\n` +
       `Read the DIFF below, then open the changed files and their callers ` +
       `(resolve paths against ${a.projectRoot}) so your critique is grounded, not surface-level.\n\n` +
       `DIFF:\n${a.diff}\n\n` +
       `Attack the change through EXACTLY ONE lens — ignore everything else:\n${lens.prompt}\n` +
       `Be specific and harsh, but "could be cleaner" is never a blocker; only a traceable failure or ` +
       `wrong outcome is. Cite the exact file and line/hunk. If the lens turns up nothing real, return an ` +
       `empty findings array — do not invent issues.`,
       { label: `grill:${lens.key}`, phase: 'Grill', schema: FINDINGS, model: a.model },
     ),
     // Stage 2: try to refute each blocker this lens raised (false-positive filter)
     (review, lens) => parallel(
       (review && review.findings ? review.findings : [])
         .filter(f => f.severity === 'blocker')
         .map(f => () => agent(
           `Try to REFUTE this blocker raised against the current diff. Read the cited file and its ` +
           `callers before deciding. A blocker is real only if a concrete failure or wrong outcome ` +
           `follows from it; default to refuted=true if you are not confident it is real.\n\n` +
           `DIFF:\n${a.diff}\n\nFINDING: ${JSON.stringify(f)}`,
           { label: `verify:${lens.key}`, phase: 'Verify', schema: VERDICT, model: a.model },
         ).then(v => ({ ...f, refuted: !!(v && v.refuted), refute_reason: v && v.reasoning }))),
     ).then(checked => ({
       lens: lens.key,
       findings: review && review.findings ? review.findings : [],
       checkedBlockers: checked.filter(Boolean),
     })),
   )

   return { reviews: reviews.filter(Boolean) }
   ```

   **After the workflow returns, you own synthesis** — don't dump raw agent output on the user:
   - **Merge & dedup** findings across lenses; an issue flagged by N lenses is stronger signal, not N issues.
   - **Apply the refutation filter** — a blocker whose verifier returned `refuted: true` drops to a Concern, or is dropped if the refutation is airtight. Keep blockers that survived.
   - **Triage hard** — a finding is a BLOCKER only if a real failure or wrong outcome traces from it. Dismiss reviewers overreaching into ceremony (blanket guards, defensive checks for impossible states) with a stated reason.
   - **List BLOCKERS at the top** — the things that must be fixed before the PR — then Concerns, then what was grilled and held up.

   **Fallback (Workflow unavailable):** revert to the single-context grill — dispatch the `code-architect` agent for the independent architecture lens, and for each remaining lens above generate the toughest devil's-advocate question and answer it honestly inline ("I don't know" or "not handled" IS the finding). Merge `code-architect`'s BLOCKERs with your own.

Don't be polite. The goal is to find what's wrong before a human reviewer does.
