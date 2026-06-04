Pre-PR verification gate. Runs the project's checks and hands off to diagnosis on failure.

## Usage

- `/verify` — fast mode: typecheck / lint / test / build from `package.json` scripts (parallel when safe, no dep install)
- `/verify --deep` — deep mode: clean-install from the lockfile, then sequenced `unit → integration → e2e`, stopping on first red

## Steps

1. Dispatch the `build-validator` agent. Pass `--deep` through if the user included it.
2. If all green, say so and stop.
3. If anything fails, dispatch the `oncall-guide` agent with the failing output to classify the cause (regression / flake / environment / test data / configuration) and propose next steps.
4. End with `git status --short`.

Do not modify files from this command. Fixes are applied by the user (or by a follow-up prompt), not by the verifier.

This command is the concrete tool that satisfies the `superpowers:verification-before-completion` discipline (no "done" claim without fresh evidence) for the pre-PR gate — report only what the check output actually shows, never "should pass".
