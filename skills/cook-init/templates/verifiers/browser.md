---
name: verifier-browser
description: Verify changes to <app name>'s web UI in a real browser, the way a user uses it - pages load, flows work, no console errors. Use for any change under <apps/web/**> that a user can see or click.
---

# verifier-browser

Drives `<app name>` with agent-browser against the dev server of the worktree under test.

## Setup

1. `cd "$(git rev-parse --show-toplevel)"` and `<pnpm install>` if `node_modules` is missing.
2. Start the dev server on a free port and keep its log: `PORT=<port> <pnpm --filter web dev> > "$run/dev.log" 2>&1 &`. Save the PID. Wait until `curl -sf http://localhost:<port><health path>` answers (at most 90 s), else BLOCKED with the last 30 lines of the log.
3. Use one browser session per run: `export AGENT_BROWSER_SESSION="verify-$(basename "$run")"`.
4. Sign in, when the flow needs it: <how to get a test account: seed script, env var name, or "no auth">.

## Steps

For each claim that touches the UI:

1. `agent-browser open http://localhost:<port><path>` and `agent-browser snapshot -i -c` to find the elements.
2. Do the flow as a user would (`click`, `fill`, `press`, `select`). Use refs from the snapshot, not guessed selectors.
3. Check the result on the page (`get text`, `is visible`), not only that no error appeared.
4. `agent-browser screenshot "$run/<claim>-<state>.png"` for each state the claim names. For UI work, take the same states and viewports as the approved mockup (`set viewport 390 844` for mobile, `set media dark` for dark mode).
5. `agent-browser errors` and `agent-browser console`: a new error or warning from this change is a FAIL.

Adjacent probes: reload the page and check the state survives when it should; go back and forward once.

## Teardown

`agent-browser close`, then stop the dev server PID you started. Stop nothing else.

## Result

PASS, FAIL or BLOCKED for each claim, with the screenshot and log paths.

## Track record
