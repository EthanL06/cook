---
name: cook-learn
description: The retro at the end of a cook build. Reads what happened in the session and turns real, repeated lessons into the project's recipes, scripts, tests and verifiers, so the next agent does not hit the same problem. Makes verifiers better from the bugs they missed. Holds a strict bar against low-value notes and prunes stale ones. Use when /cook reaches its learn step, when the user invokes /cook-learn, or when the user asks to turn a lesson from this session into a recipe, script or verifier.
argument-hint: "[ref] [--dry-run]"
---

# cook-learn

The project gets better with each build, but only from lessons that pay for themselves. A file that the next agent must read and that saves nobody time is a cost. When in doubt, write nothing.

Everything this skill changes goes on the build branch, in the same PR, so a person reviews it. With `--dry-run`, list the changes and write nothing.

## 1. Collect the evidence

Read, from this build only:

- the session: errors, retries, wrong turns, and the time each one cost (look at timestamps),
- the /cook-verify runs: `.context/verify/*/receipt.md` and `verifiers.tsv` (NOT COVERED lines, verifier notes, flaky steps),
- the review loop: each finding that no-mistakes, Greptile or a person raised after verify had passed,
- the PR and the issue comments,
- `.agents/recipes/README.md`, the recipes and the verifiers' `## Track record` sections.

Also check for **escaped bugs** from earlier builds: issues or PR comments that point at a cook PR in this repo and report a bug it shipped (`gh issue list --search "<PR number or title words>"`, the tracker's search). Each one is a miss to learn from.

## 2. Decide, with the bar

Make one list of candidates. For each, pick at most one outcome, in this order of preference: **test**, **verifier check**, **script**, **recipe**, **nothing**. A test or a check stops a problem. A recipe only describes it.

| Outcome | Only when |
|---|---|
| **Test** | A bug was found that can come back, and a unit or integration test can catch it. |
| **Verifier check** | A problem got past a verifier (found by the review loop, a person, or an escaped bug), or a NOT COVERED area appeared twice. |
| **Script** (`scripts/qa/`) | The agent did the same manual QA or setup steps two or more times in this build, or in two builds. |
| **Recipe** | The same problem happened twice (in this build, or already seen in a past recipe or PR), **or** it cost about 15 minutes or more, **and** the fix is not obvious from the code, the README or the error message. |
| **Nothing** | Everything else: one-off typos, a missing import, facts that only matter for this diff, things any agent finds in a minute, temporary debug commands, ports, personal setup. |

Before you add a recipe, look for one that covers the same area and update it. Never make two recipes for one problem.

## 3. Write

### Verifiers improve from their misses

For each miss:

1. Find the verifier that should have caught it (by the area). If none covers the area, propose a new verifier only when the area has had two misses or two NOT COVERED lines. Use the templates from the `cook-init` skill.
2. Add the smallest check that would have caught it, as a numbered step in the verifier, with the exact command or flow and the result to expect.
3. Run the new check once against this branch and once against the base, to prove it catches the problem and does not fail on good code.
4. Add one line to the verifier's `## Track record`:
   `- <date> <ref>: missed <what>. Added check "<name>".`

When a verifier found a real problem in this build (a FAIL that the build then fixed), add a line for that too:
`- <date> <ref>: caught <what> (check "<name>").` The catches show which checks earn their cost.

Also keep verifiers lean:

- A step that was flaky in `verifiers.tsv` gets fixed (wait for the right signal, not a longer sleep), not removed.
- A step that has run in 10 or more builds, has no "caught" line, and costs more than a minute can be removed or made conditional, with a Track record line that says why. Never remove a step to get a pass.
- When a verifier step was wrong (verifier notes in the receipt), fix the step.

Keep `## Track record` to the 15 newest lines. Older lines go away. Git history keeps them.

### Recipes

`.agents/recipes/<area>-<problem>.md`, at most about 15 lines:

```markdown
# <the symptom, as the next agent would see it>

Problem: <what you see>
Cause:   <why>
Fix:     <the exact command or change>
Seen in: <ref> (<date>)[, <ref> (<date>)]
```

Add a line for it to `.agents/recipes/README.md` (one line: symptom and file). A second sighting adds to `Seen in`, which shows that the recipe earns its place.

**Prune** in the same pass: delete a recipe when the code no longer has the problem (the fix is in the code now, or a test or check covers it), or when it is wrong. Remove its README line. When a recipe becomes a test or a check, delete the recipe.

### Scripts

`scripts/qa/<verb>-<thing>.sh` (create the folder the first time). The script must run without questions, print what it did, and exit non-zero on failure. Add one line to the recipes README that names it, and call it from the verifier that needs it.

### Tests

Put the test next to the code, in the project's test style. Run it: it must fail without the fix and pass with it.

## 4. Report

Print one line per change, and the same lines go into the PR under `## Learned`:

```
LEARN: <n> changes
- verifier-browser: added check "offline recipe opens" (missed in #42, found by review)
- recipe: service-worker-cache-in-dev.md (seen twice: #42, #45)
- removed recipe: old-env-setup.md (fixed in setup.sh)
- nothing for: the type error in export.ts (one-off)
```

Show what you chose not to keep too, so the reviewer sees the bar at work.
