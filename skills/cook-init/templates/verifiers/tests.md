---
name: verifier-tests
description: Run <project>'s static checks and automated tests on the worktree under test - lint, format, typecheck and unit or integration tests - and check that new behavior has a test. Use for every change.
---

# verifier-tests

## Steps

1. The full check: `<pnpm check>`. Save the output. When it is slow, run only the affected packages first (<for example `pnpm --filter <pkg> test`>), then the full check once at the end.
2. A failure that also happens on the base branch is not this change's fault. Prove it: run the same command in a scratch worktree of the base. Report it as "already broken on base", not as FAIL.
3. New behavior needs a test. When the diff adds or changes logic and no test covers it, the claim "has a test" is FAIL. Write the missing test only if the task allows it.
4. Never skip, delete or loosen a test or a lint rule to get a pass.

## Result

PASS, FAIL or BLOCKED, with each command, its exit code and the log path.

## Track record
