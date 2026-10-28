---
name: cook-verify
description: Prove that the implementation on the current branch works, with fresh evidence. Reads the task and the diff, finds the affected systems, runs the project's verifier skills (verifier-* in the main checkout's .agents/skills/), saves evidence under .context/, repairs real failures, and ends with a PASS, FAIL or BLOCKED receipt. Use when /cook reaches its verify step, when the user invokes /cook-verify, or when the user asks to verify or prove that an implementation is complete.
argument-hint: "[task, issue ref or done checks] [--no-fix] [--performance]"
---

# cook-verify

Proves that the code on the current branch does what the task asks, with evidence made in this run. It routes to the project's verifiers. It holds no project facts itself.

The spec answers "are we building the right thing?". Verify answers "did we build it correctly?".

Use only shell, git and files. Do not depend on a harness feature.

## Rules

- **Fresh evidence only.** A claim passes only on evidence made in this run: command output, screenshots, recordings, API captures, logs. These are not evidence: code that looks correct, tests that passed before, an agent saying it works, typecheck or lint alone.
- **Runtime behavior needs a runtime check.** If the tools cannot reach the behavior, the claim is BLOCKED.
- **Never skip silently.** Every affected system gets a verifier or a NOT COVERED line.
- **Match the checks to the risk.** A change that cannot alter runtime behavior (rename, comments, docs, formatting, type-only, deleted dead code) needs static checks, proof that behavior did not change, and one short smoke check. Write each skipped check as `SKIPPED (behavior-neutral): <reason>`. If you are not sure, run the check.
- **Performance only when asked.** Run `verifier-performance` only with `--performance`, or when the task says so.
- **Never weaken a check to get a pass.** Do not delete, skip or loosen tests, assertions or verifier steps. Change a test only when it contradicts the intended behavior, and say so in the receipt.
- **No outward actions:** no commit, push, PR, deploy, migration, or job trigger on a shared environment. Repairs stay uncommitted (/cook commits them).
- **Shared machine.** Stop only processes and browsers you started.
- Follow `.agents/cook.md` and `AGENTS.md` where they are stricter than this file.

## A. Context

```sh
top=$(git rev-parse --show-toplevel)
common=$(git rev-parse --path-format=absolute --git-common-dir)
case "$common" in */.git) main=${common%/.git} ;; *) main=$top ;; esac
run="$top/.context/verify/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run"
git -C "$top" check-ignore -q "$run" || { echo '.context/' >> "$common/info/exclude"; echo "added .context/ to $common/info/exclude"; }
printf 'top=%s\nmain=%s\nrun=%s\n' "$top" "$main" "$run"
```

- `$top` is the code under test. Run every check from `$top`.
- `$main` holds the verifiers and recipes.
- Base branch: `base` in `$main/.agents/cook.md`, else `git symbolic-ref --short refs/remotes/origin/HEAD`.
- Collect: `git status --short`, `git diff --stat <base>...HEAD`, `git diff <base>...HEAD`, `git diff HEAD`, `git ls-files --others --exclude-standard`. Verify all of it, not only the commits.
- Read `AGENTS.md` (or `CLAUDE.md`), the nested ones in the changed folders, and `cook.md`. Read them as files.

## B. Plan

- Get the task: the request, the issue, the approved spec, the PR, or the branch name. With no task, say the claims come from the diff only.
- Write `$run/plan.md`:
  - **Claims:** each intended behavior as one testable sentence.
  - **Affected systems:** web UI, API, data, mobile, build...
  - **Regression surfaces:** nearby behavior the change could break.
  - **Evidence needed** for each claim, and the verifier that makes it.

## C. Verifiers

```sh
for f in "$main"/.agents/skills/verifier-*/SKILL.md; do
  [ -f "$f" ] || continue
  echo "== $f"; awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f' "$f"
done
```

- Use only the verifiers that exist. Read the full `SKILL.md` of each one that matches an affected system and follow it. It runs against `$top`.
- Make a coverage table: system, verifier, or **NOT COVERED**. Do not invent an ad-hoc verifier in place of a missing one. Do the closest safe checks that the project's instructions describe, and keep the item NOT COVERED unless those checks fully prove the claim.

## D. Recipes

Read `$main/.agents/recipes/README.md` and the recipes for the areas this change touches. Recipes say how to reach and set up a product area. Verifiers say how to check it. Use both.

## E. Execute

- Static checks first, then runtime checks.
- Save every command's output: `<cmd> > "$run/<step>.log" 2>&1; echo "exit=$?" >> "$run/<step>.log"`.
- Screenshots, recordings and captures go in `$run/`, with absolute paths.
- Give each claim PASS, FAIL or BLOCKED, with evidence paths. Do the adjacent probes the verifier asks for.
- Classify each failure: implementation, environment (build, auth, service down, port taken), test or verifier problem, or already broken on the base branch. Only an implementation failure goes to F.
- Record each verifier's own result in `$run/verifiers.tsv`: `verifier<TAB>result<TAB>checks run<TAB>problems it found<TAB>flaky steps`. /cook-learn reads it.

## F. Repair loop

Skip with `--no-fix` and report failures as FAIL.

1. Find the root cause of the implementation failure.
2. Fix only what is necessary, inside the task's scope.
3. List the evidence the fix makes invalid: every claim on the changed code path, and the static checks of each affected package.
4. Run those checks again into `$run/round-<n>/`. Do not reuse old evidence for invalid claims.
5. After 3 rounds on the same failure, stop and report FAIL with what you tried.

List every repair (file, reason) in the receipt.

## G. Receipt

- **PASS:** every claim is PASS with fresh evidence, and no affected system is NOT COVERED.
- **FAIL:** at least one claim fails because of the implementation.
- **BLOCKED:** no FAIL, but at least one claim is BLOCKED or NOT COVERED.

Write `$run/receipt.md` and print it:

```
VERIFY: PASS | FAIL | BLOCKED
Target: <branch>@<short sha> (+ uncommitted changes, if any) vs <base>
Task: <one line, or "diff only">

Claims
- [PASS] <claim> - <evidence path(s)>
- [FAIL] <claim> - expected <x>, saw <y> - <evidence>
- [BLOCKED] <claim> - <reason> - <what was tried>

Coverage
- <system>: <verifier> | NOT COVERED

Checks run: <command> -> exit <n> (<log path>)
Skipped: <check - SKIPPED (behavior-neutral): reason> | none
Repairs: <file - reason> | none
Verifier notes: <a verifier step that was wrong, flaky or slow, for /cook-learn> | none
Evidence folder: <run>
```

Do not change verifiers or recipes here. /cook-learn does that, with the bar it holds.

## Verifier contract

Each verifier is `.agents/skills/verifier-<kind>/SKILL.md` with `name` and `description` frontmatter. The description says which changes it covers. A verifier:

- runs against the worktree under test, never against the main checkout,
- writes evidence to the run folder it gets, with absolute paths,
- ends with PASS, FAIL or BLOCKED for each claim it checked, with evidence paths,
- keeps a short `## Track record` section at its end, which only /cook-learn changes.

## Request

$ARGUMENTS
