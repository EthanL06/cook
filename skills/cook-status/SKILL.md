---
name: cook-status
description: Show where every cook build is right now - its step, who it waits on (you or the agent), how long it has been in that step, its machine and its last event - with the builds that wait on you first. With a ref, show one build in detail. Read-only, fast, works from any session or terminal, and never interrupts a build. Use when the user invokes /cook-status or asks how their builds are going.
argument-hint: "[ref] [--watch]"
---

# cook-status

Run the script and show its output as it is. Do not add commentary unless the user asks.

```sh
S="$(cd "$(dirname "$(readlink -f ~/.agents/skills/cook-status/SKILL.md 2>/dev/null || readlink -f ~/.claude/skills/cook-status/SKILL.md)")" && pwd)"
"$S/status.sh" [ref]
```

- No argument: one row per build on every machine (Tailscale peers too), then a line that says how many builds wait on the user and which one waits longest.
- A ref (`#42`, `ENG-123`, a slug, or the start of an agent ID): that build's step, links (spec, PR) and its last 10 events, and how long the step usually takes in this repo. It never guesses a finish time.
- `--watch` redraws every 10 seconds (`COOK_STATUS_INTERVAL`). It is for a terminal. In an agent session, run it once.

After the table, for each build that waits on the user, add one line with what to do: open the spec link (`plan`), send the `Next:` reply in the build agent (`blocked`), or review the PR (`ready`).

The script only reads event logs, Paseo step labels and agent titles. It never sends a message to a build agent, so it does not slow a build.
