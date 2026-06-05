Draft an implementation plan, grill it with independent adversarial reviewers, and — once the user approves — save the refined plan as a checked-in artifact that rides with the stacked PRs.

Use this for any non-trivial task where a weak plan would compound into a bad implementation.

`/plan` grills an **approach** — before any code exists; it attacks the reasoning. To grill a **diff** you've already written, use `/grill` instead. (Same adversarial fan-out, different target.)

## Steps

1. Derive a slug for the plan file:
   - Grep the current branch name and the last 5 commit subjects for `\b[A-Z]{2,}-\d+\b`. If a Jira-style key matches (e.g. `AUTH-1234`), slug = that key.
   - Otherwise, build a 3–5 kebab-case word summary of `$ARGUMENTS`, prefixed with a verb when one fits — `feat-rotate-oauth-keys`, `fix-auth-race`, `chore-bump-deps`, `refactor-payments-module`. If no prefix fits, drop it (`migrate-to-rsc`).
   - If `$ARGUMENTS` is empty or too thin to summarise, ask the user for a slug before continuing.
2. Draft a plan based on `$ARGUMENTS` (the task). Structure:
   - **Goal** — one sentence.
   - **Files to touch** — concrete paths.
   - **Steps** — GitHub-checkbox list (`- [ ] step`); each small enough that progress is observable as work lands.
   - **Edge cases** — concurrency, retries, partial failure, untrusted inputs.
   - **Out of scope** — explicit non-goals.
   - **Acceptance criteria** — how we'll know it's done.

   Keep the plan tight — 10–20 bullet points, not an essay. Don't save it to disk yet.
3. **Grill the plan adversarially.** A plan reviewed by the same model that wrote it self-anchors — it confirms its own assumptions instead of attacking them. Instead, fan out independent reviewer subagents, each a fresh context with one adversarial lens. Synthesis and the decision to loop back stay with you (the main loop).

   **Size the grill to the plan** — this is the cost dial; don't throw 8 Opus reviewers at a one-file fix. Announce the setup in one line and let the user retune before launching. Invoking `/plan` is your opt-in to run the Workflow, so don't ask *whether* — only let them change the model or lens set:
   - **Small** (bug fix, refactor, ≤ ~3 files / ≤ ~5 steps) → the core 4 lenses (★) on **Sonnet**.
   - **Large** (greenfield, many files, new abstractions) → all 8 lenses on **Opus**.
   - e.g. *"Small plan → core 4 lenses on Sonnet. Say 'opus' or 'all 8' to widen, otherwise I'll launch."*
   - **Frontend plans** (new/changed UI — components, pages, forms, interactive elements) → invoke the `test-locators` skill first, then add the `locators` lens below. Skip it for backend-only plans.

   The lenses (core 4 marked ★) — each reviewer gets exactly one:
   - ★ **assumptions** — Which single assumption, if wrong, breaks the whole plan? What did the author inherit without confirming?
   - ★ **failure_modes** — What fails silently? Which new codepath has no error handling or a swallowed error?
   - ★ **dependencies** — Does each step really depend on the prior one, or is the order arbitrary? Is every acceptance criterion concrete and testable, not "works correctly"?
   - ★ **alternatives** — Was a simpler approach dismissed too fast? Is there a 1-file fix behind a 5-file plan?
   - **scope_drift** — What snuck in beyond the goal? What belongs in "Out of scope" but isn't there?
   - **testing_gaps** — What edge case passes the plan's checks but still breaks prod? What does each acceptance criterion actually prove?
   - **missing_risks** — What risk is suspiciously absent? (rollback path, data migration, observability gap)
   - **business_fit** — Does the approach serve the actual goal, or has it drifted into a neat solution to the wrong problem?
   - **locators** _(frontend plans only)_ — Apply the `test-locators` skill: does the plan ensure new interactive/asserted elements get stable `data-testid`/`data-test` (business-meaningful, not position/CSS-based)? If the plan adds UI but never mentions test locators, that's the finding.

   Build `args` from the gated decisions, then call the Workflow tool with the script below:
   - `args.planContent` — the drafted plan markdown (it isn't on disk yet)
   - `args.projectRoot` — absolute project root (reviewers resolve "Files to touch" paths against it)
   - `args.model` — `'opus'` or `'sonnet'` (the size default, or the user's override)
   - `args.lenses` — array of `{key, prompt}` for the chosen subset (★ four, or all 8). Use the lens descriptions above as each `prompt`.

   ```js
   export const meta = {
     name: 'plan-grill',
     description: 'Adversarial fan-out review of a draft plan across independent lenses, verifying blockers',
     phases: [
       { title: 'Grill', detail: 'one fresh reviewer per adversarial lens' },
       { title: 'Verify', detail: 'try to refute each blocker-severity finding' },
     ],
   }

   const FINDINGS = {
     type: 'object', required: ['findings'],
     properties: { findings: { type: 'array', items: {
       type: 'object',
       required: ['severity', 'plan_section', 'issue', 'what_it_breaks', 'suggested_fix'],
       properties: {
         severity: { type: 'string', enum: ['blocker', 'concern'] },
         plan_section: { type: 'string' },
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
   if (!a.lenses || a.lenses.length === 0) throw new Error('plan-grill: a.lenses is empty — pass the chosen lens array')

   const reviews = await pipeline(
     a.lenses,
     // Stage 1: one independent reviewer per lens
     lens => agent(
       `You are an adversarial plan reviewer. You did NOT write this plan and owe it no loyalty.\n` +
       `Read the plan below, then read every file it lists under "Files to touch" ` +
       `(resolve relative paths against ${a.projectRoot}) so your critique is grounded in the real code.\n\n` +
       `PLAN:\n${a.planContent}\n\n` +
       `Attack the plan through EXACTLY ONE lens — ignore everything else:\n${lens.prompt}\n` +
       `Be specific and harsh, but "could be cleaner" is never a blocker; only a traceable failure or ` +
       `wrong outcome is. Cite the exact plan section. If the lens turns up nothing real, return an empty ` +
       `findings array — do not invent issues.`,
       { label: `grill:${lens.key}`, phase: 'Grill', schema: FINDINGS, model: a.model },
     ),
     // Stage 2: try to refute each blocker this lens raised (false-positive filter)
     (review, lens) => parallel(
       (review && review.findings ? review.findings : [])
         .filter(f => f.severity === 'blocker')
         .map(f => () => agent(
           `Try to REFUTE this blocker raised against a draft plan. Read the cited section and the ` +
           `referenced code before deciding. A plan-level blocker is real only if a concrete failure or ` +
           `wrong outcome follows from it; default to refuted=true if you are not confident it is real.\n\n` +
           `PLAN:\n${a.planContent}\n\nFINDING: ${JSON.stringify(f)}`,
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
   - **Triage hard** — a finding is a BLOCKER only if a real failure or wrong outcome traces from it. Dismiss reviewers overreaching into ceremony (blanket guards, exhaustive error maps, production test-only hooks) with a stated reason.
   - If BLOCKERS survive, revise the draft to address each and note what changed before presenting.

   **Fallback (Workflow unavailable):** dispatch the `plan-architect` agent with the plan as input — one independent fresh-context reviewer still beats self-grilling. Use its BLOCKER/WARNING/SUGGESTION verdict in place of the grill output.
4. Present the plan and the grill verdict (surviving BLOCKERS, Concerns) to the user side by side. **Do not save anything yet.** Wait for the user to accept, redirect, or revise. Do not start implementation either.
5. Once the user accepts:
   - Apply the grill findings the user explicitly approved.
   - Check whether `.claude/plans/<slug>.md` already exists. If it does, ask the user whether to overwrite, pick a new slug, or merge into the existing file before writing.
   - Save the final plan to `.claude/plans/<slug>.md`.
6. Close with this reminder verbatim:

   > Tick checkboxes as steps land. Once the work merges to main (the last PR in the stack, if stacked), delete `.claude/plans/<slug>.md`.
