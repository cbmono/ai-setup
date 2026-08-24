Run CodeRabbit review on the current branch against the repo's default branch.

Steps:

1. Detect the default branch — **never assume `main`**:
   `git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@^origin/@@'`
   Call it `BASE`. If it prints nothing, **stop** and tell the user to run
   `git remote set-head origin --auto` (or pass the base explicitly). There is
   deliberately no `main` fallback: a wrong base reviews a diff nobody wrote —
   CodeRabbit reports confidently on it, and the report looks valid.
2. Run `coderabbit review --base "$BASE" --type committed` to review all committed
   changes on this branch vs `BASE`.
3. Present the review output to the user.
