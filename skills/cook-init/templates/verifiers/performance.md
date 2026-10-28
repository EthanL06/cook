---
name: verifier-performance
description: Measure load time, rendering, memory or bundle size of <app name> before and after a change, on the same machine with the same steps. Use only when the user asks for performance checks or the change can change performance a lot.
---

# verifier-performance

Compare, do not guess. Every number has a base number next to it.

## Setup

1. A production-like build, not the dev server: `<pnpm --filter web build && pnpm --filter web start>`.
2. The same build of the base branch, from a scratch worktree, on another port.

## Steps

1. Run each measurement 5 times on each build and keep the median: page load and Core Web Vitals (`agent-browser vitals <url> --json`), bundle size (<command>), and the metric the task names (<for example time to render 500 rows>).
2. Report base, change, and the difference in percent. A change worse than <10>% on a metric the task touches is a FAIL unless the spec accepted it.
3. Note the machine, the load on it, and anything that makes the numbers noisy.

## Result

PASS, FAIL or BLOCKED, with a table of the medians and the raw runs.

## Track record
