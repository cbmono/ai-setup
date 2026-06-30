Run CodeRabbit review on the current branch against the repo's default branch.

Steps:

1. Detect the default branch — don't assume `main`:
   `git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@^origin/@@'`
   (fallback to `main` if that prints nothing). Call it `BASE`.
2. Run `coderabbit review --base "$BASE" --type committed` to review all committed
   changes on this branch vs `BASE`.
3. Present the review output to the user.
