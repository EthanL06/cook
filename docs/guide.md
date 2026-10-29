# cook workflow guide

This guide explains each part of the cook workflow. It tells you what each tool is, why it is in the flow, how to set it up, and what it looks like in a real build.

For a full walkthrough of one build, see the [Quick start in the README](../README.md#quick-start).

## Contents

1. [The three ideas](#the-three-ideas)
2. [The flow](#the-flow)
3. [Lavish: specs and mockups](#lavish-specs-and-mockups)
4. [Paseo and git worktrees](#paseo-and-git-worktrees)
5. [AXI instead of MCP servers](#axi-instead-of-mcp-servers)
6. [agent-browser](#agent-browser)
7. [Verifiers](#verifiers)
8. [Recipes](#recipes)
9. [Turn repeated work into scripts](#turn-repeated-work-into-scripts)
10. [ntfy](#ntfy-optional)
11. [Tailscale](#tailscale-optional)
12. [CLI proxy](#cli-proxy-optional)
13. [Resume a build that stopped](#resume-a-build-that-stopped)
14. [Working with cook day to day](#working-with-cook-day-to-day)
15. [Tests](#tests)
16. [Credits](#credits)

## The three ideas

| Idea | Rule |
| --- | --- |
| **Spec** | Spend the most time on the spec. The spec and the mockups go through a Lavish loop until you approve them. The more detail they have, the less back and forth there is during the build. No code is written before you say "approve". |
| **Verify** | Verification is as important as the build. Each project has verifier skills. A build is ready only when the verifiers pass with fresh evidence. |
| **Learn** | Agents start each session from zero. The retro gives them memory. It improves verifiers, writes recipes, and turns manual work into scripts. |

## The flow

![The cook flow](flow.svg)

The top lane is you. The bottom lane is autonomous.

| Step | Who | What happens |
| --- | --- | --- |
| 1. Intake | You | Run `/cook <issue or prompt>`. Answer one batch of questions. Each question has a default. This takes about 2 minutes. |
| 2. Spec | You | Open the Lavish link from the push. Annotate. Pick a mockup. Repeat until you send "approve". Most of your time goes here. |
| Unblock | You, only if asked | The push gives the reason and the exact reply to send. Most builds never need this. |
| 3. Review | You | The PR holds the evidence, the verify receipt, and the deploy steps. You merge. cook never merges. |

The agent does all other steps: issue, worktree, draft spec, build, verify, PR, review loop, and retro.

### Hard rules

| Rule | Reason |
| --- | --- |
| cook never merges, never force-pushes, and never rebases a pushed branch. | You keep control of history. |
| cook never writes data or applies migrations to a shared environment. | Deploy steps go in a comment. A person does them. |
| cook stops only the processes that it started. | Other worktrees and servers stay safe. |
| cook sends one push for each blocker. | Your phone does not fill with noise. |
| cook never redoes an approved spec, and never resumes into a worktree with uncommitted changes before it tells you. | Your approval and your work stay. |

If `cook.md` or the `AGENTS.md` of the project is stricter than the kit, the stricter rule wins.

---

## Lavish: specs and mockups

### What

Lavish turns an agent answer into an HTML page that you can annotate. You run it with `npx -y lavish-axi`. cook uses it for the spec and for the mockups.

### Why

The spec is the most important step. A clear spec means the agent builds the right thing the first time. Prose in a terminal is hard to review. A page with mockups, tables, and controls is easy to review. You can annotate the page and send the feedback back to the agent.

Plan to spend most of your time here.

### Setup

Lavish is a required tool. Run `doctor.sh` to check it. The `specs` setting in `.agents/cook.md` controls where specs live:

| Value | Result |
| --- | --- |
| `local` (default) | Specs stay in the git-ignored `.lavish/` folder. cook attaches an exported copy to the issue. |
| `committed` | cook writes `docs/specs/<id>.html` and includes it in the PR. |

### What a spec contains

- The done checks.
- The approach and the files to change.
- The work split.
- The verification and evidence plan.
- What is out of scope.
- Risks and open questions, with answer controls.

For UI work, the spec also has:

- Screenshots of the current UI.
- Research from real apps, with `mobbin-axi` when the project sets `ui_refs: mobbin`.
- One to four mockup variations. Each one is a working prototype in the design tokens of the project.
- A state switcher: empty, loading, error, and each role.
- Viewport and theme switches.
- Side-by-side and current-versus-proposed views.

### Example

Issue #42 is "Save recipes offline". The agent writes a spec with three mockup variations of the offline toggle. You open the link on your phone and use the state switcher to see the empty state and the error state. You annotate:

```text
Variation B, but put the toggle in the recipe menu.
```

The agent updates the page and sends a new push. You read the changes and send:

```text
approve
```

The agent starts to write code. A question is not approval. The agent waits for the word "approve".

---

## Paseo and git worktrees

### What

[Paseo](https://paseo.sh) runs agents. Each build gets its own agent in its own git worktree. A worktree is a second checkout of the repo on its own branch.

### Why

- Builds do not touch each other. You can run many builds at the same time.
- Your main checkout stays clean.
- The session you start from becomes a hub. It reports plan links, blockers, and PRs for every build.
- When the work splits, the build agent can use subagents.

### Setup

Paseo is a required tool. The hub starts each build agent with `launch.sh`, on this machine or on a Tailscale machine. The `base` and `branch` settings in `.agents/cook.md` control the starting branch and the branch name:

```yaml
base: main
branch: "{user}/{id}-{slug}"
```

You can set a different starting branch for one build:

```text
/cook #42 from release-2
```

Before `launch.sh` starts the agent, it checks the machine and the branch:

| Case | What happens |
| --- | --- |
| The branch is new. | The worktree branches off `origin/<base>`. |
| The branch is on `origin`. | The build continues on it. A local copy that is behind `origin` moves forward first. |
| The branch is only local. | The build continues on it. |
| The branch is checked out in another worktree. | It stops. A build may use it: use `/cook resume <ref>`. |
| The local branch and `origin` have different commits. | It stops. Merge or push the branch by hand, or pick another name. |
| The machine or its Paseo daemon does not answer, or `paseo run` fails. | It stops and tells you why. Nothing has started. |

### Example

You start two builds from one session:

```text
you> /cook #42
you> /cook "add CSV export to the shopping list"
```

Paseo makes two worktrees and two agents. Build #42 is in `cook/42-offline-recipes`. The second build has its own branch. Both builds run at the same time. The hub reports each plan link when it is ready.

---

## AXI instead of MCP servers

### What

AXI is a set of CLIs made for agents. cook uses `lavish-axi` for specs, `linear-sdk-axi` for Linear, and, when the project chooses them, `chrome-devtools-axi` or `playwright-axi` for the browser and `mobbin-axi` for UI references. For GitHub, cook calls `gh` directly. For your own agent work, `gh-axi` gives the same data with fewer tokens. See [axi.md](https://axi.md) and the [AXI repo](https://github.com/kunchenguid/axi).

### Why

An MCP server loads many tool definitions into the context of the agent. An AXI CLI gives the same data with fewer tokens. A smaller context gives the agent more room for the real work. Agents also run shell commands well.

### Setup

Run `doctor.sh --fix`. It checks the AXI tools this project uses and fetches the missing ones into the npx cache, after you say yes. A tool runs with `npx -y` if it is not on your PATH. For example:

```bash
npx -y linear-sdk-axi
```

Set the tracker in `.agents/cook.md`:

```yaml
tracker: github   # linear | github | none
```

### Example

In build #42 on a Linear project, the agent reads the issue and later posts the evidence with `linear-sdk-axi`. It does not need a Linear MCP server. The agent loads no extra tool definitions, so more context stays free for the code.

---

## agent-browser

### What

agent-browser is a browser tool for agents. The browser verifier uses it to open the app, click through flows, and take screenshots like a real user.

### Why

You should not test by hand. The agent must see the UI that it built. Screenshots in the PR show you the result before you open the branch.

### Setup

agent-browser is the default. Two other tools work: `chrome-devtools-axi` and `playwright-axi`. Change the setting in `.agents/cook.md`:

```yaml
browser: agent-browser   # agent-browser | chrome-devtools-axi | playwright-axi
```

The `dev` command in `.agents/cook.md` starts the app. The verifier uses it.

The browser runs headless by default, so it never takes focus and several builds can verify at the same time. An agent opens a headed window only when a check needs one: you want to watch or must sign in yourself, a real hover, the OS clipboard, or a smooth recording. It says why in the report.

### Example

For build #42, `verifier-browser` starts the dev server. It opens a recipe, turns on the offline toggle, switches the network off, and reloads the page. It takes four screenshots. The screenshots go into the PR.

---

## Verifiers

### What

A verifier is a project skill in `.agents/skills/verifier-*`. Each verifier covers one area of the project. `/cook-init` makes a verifier only for an area that the repo has.

| Verifier | Area |
| --- | --- |
| `verifier-browser` | Web UI in a real browser |
| `verifier-api` | API routes with real requests |
| `verifier-data` | Schema and migrations on a local database |
| `verifier-design` | Design tokens and visual checks |
| `verifier-tests` | Unit tests, lint, and type checks |
| `verifier-mobile` | Mobile app in a simulator |
| `verifier-performance` | Performance checks |

`/cook-verify` reads the task and the diff. It picks the right verifiers and collects fresh evidence under `.context/`. It repairs real failures. It ends with a PASS, FAIL, or BLOCKED receipt. If an area has no verifier, the receipt shows a NOT COVERED line. The retro can then propose a new verifier.

### Why

An agent that says "done" proves nothing. A verifier gives proof. The proof is in the PR, so you can check it in a short time.

### Setup

`/cook-init` runs each verifier once against the base branch before it writes the verifier. A verifier that fails on good code gets fixed first. A verifier that cannot run on this machine (no simulator, no database) is marked BLOCKED, and init says what to install. List the active verifiers in `.agents/cook.md`:

```yaml
verifiers: [browser, design, api, data, tests]
```

### How verifiers improve

Verifiers get better over time. This is how:

1. A bug gets past a verifier. The review loop finds it, or you find it in PR review, or someone reports it later against the PR.
2. `/cook-learn` finds which verifier should have caught the bug.
3. `/cook-learn` adds a check to that verifier, in the same PR.

Each verifier has a short **Track record** section. It records:

- What the verifier caught.
- What the verifier missed.
- Which checks were added or removed, and why.

Two rules protect the quality of a verifier:

- A flaky check is fixed.
- A check is never weakened to get a pass.

Everything goes in the PR of the build. A person reviews the change.

### Example

Build #45 adds a CSV export. `verifier-api` passes. In PR review, you find that the export fails for a list with an emoji in a name. `/cook-learn` finds that `verifier-api` only tests ASCII names. It adds a check with a non-ASCII name and writes this in the Track record:

```markdown
## Track record

- 2026-11-03 #45: missed CSV export failing for non-ASCII names. Added check "export non-ASCII list".
- 2026-10-28 #42: caught offline route returning 500 on an empty cache (check "offline routes").
```

---

## Recipes

### What

A recipe is a short Markdown file in `.agents/recipes/`. Each recipe solves one problem that an agent hit. `README.md` in that folder is the index. `dev-setup.md` is the first recipe.

### Why

Agents start each session from zero. Without recipes, the next agent loses the same 20 minutes on the same error.

### The bar for a new recipe

The bar is strict. A recipe is written only when both of these are true:

- The same problem happened twice, or it cost real time (about 15 minutes or more).
- The fix is not obvious from the code or the docs.

Other rules keep the folder small:

- `/cook-learn` updates an existing recipe before it adds a new one.
- `/cook-learn` deletes recipes that are wrong or no longer apply.
- All changes go in the PR of the build for human review.

A low-value recipe makes the next agent slower. Do not keep one.

### Setup

`/cook-init` makes the folder and adds one line to `AGENTS.md`:

```text
Read .agents/recipes/README.md before you start.
```

### Example

In build #42, the agent lost time because the service worker served an old bundle in dev. The retro wrote this recipe:

```markdown
# .agents/recipes/service-worker-cache-in-dev.md
Problem: the browser verifier sees old UI after a code change.
Cause:   the service worker caches the bundle, also in dev.
Fix:     start dev with SW_DISABLED=1, or run `pnpm sw:clear` before the verifier.
Seen in: #42 (2026-10-28)
```

The agent on #45 read the recipe at start-up and did not lose the time.

---

## Turn repeated work into scripts

### What

When a QA flow is done by hand more than once, the agent writes a script for it. Scripts live in `scripts/qa/`. `/cook-init` does not make this folder. `/cook-learn` makes it the first time a QA flow gets a script.

### Why

A script is faster and more exact than an agent that repeats the steps. A script also gives the same result each time.

### Setup

Ask the agent to automate a QA flow:

```text
Write a script in scripts/qa/ that seeds a test user and opens the saved recipes page.
```

You can also let `/cook-learn` find the flows. It looks for manual QA steps in the session.

### Example

In build #42, the agent seeded a test user and a saved recipe by hand in three steps. The retro turned the steps into `scripts/qa/seed-saved-recipe.sh`. Verifiers and later builds now call this script.

---

## ntfy (optional)

### What

ntfy sends a push to your phone. Pushover also works.

### Why

You do not need to watch the terminal. The push tells you when a plan is ready, when a build is blocked, and when a PR is ready. The push for a blocker gives the exact reply to send.

### Setup

Install the ntfy app on your phone and subscribe to a topic. Then write the config file `~/.config/cook/notify.env`:

```bash
NOTIFY=ntfy
NTFY_TOPIC=your-private-topic-name
```

Use a topic name that others cannot guess: anyone who knows it can read your pushes. This file is personal and stays out of every repo. To stop pushes for one project, set `notify: off` in its `.agents/cook.md`.

### Example

```text
📱 Plan ready for you - #42
📱 Blocked - #47: needs a test account. Reply "use seed user 3"
📱 Ready for review - #42
```

---

## Tailscale (optional)

### What

Tailscale connects your machines in a private network. cook can run a build on another machine in that network.

### Why

- You can use a stronger or idle machine for a long build.
- Lavish links use the Tailscale name, so they open on your phone.

### Setup

Install Tailscale on each machine and sign in. Each machine needs SSH access from the others, the cook skills, and a checkout of the repo. cook finds the machines by itself from Tailscale and checks each one. The intake asks for a machine only when more than one is ready.

### Example

```text
you> /cook #45 on desktop-pc
```

The build runs on `desktop-pc`. `/cook-status` shows it with the machine name:

```text
 #    STEP        WAITING ON   FOR    MACHINE     LAST
 45   verify 2/4  agent        6m     desktop-pc  browser ✓ data ✓ mobile running
```

---

## CLI proxy (optional)

### What

A CLI proxy puts many Claude or Codex accounts behind one endpoint.

### Why

Many parallel builds use a lot of quota. A proxy spreads the load across accounts. This part is a guide only. cook does not use a proxy directly.

### Setup

Run a CLI proxy of your choice. Point your agent CLI at its endpoint. Follow the documentation of the proxy for the exact steps.

### Example

You run five builds at once. The proxy sends each agent request to an account that has quota left. The builds do not stop on a rate limit.

---

## Resume a build that stopped

### What

A build can stop before it is done: the agent crashes, the machine restarts, or verify fails again and again until the agent stops. `/cook resume` continues the build from the step where it stopped. You do not start the build again, and you do not approve the spec again.

### Why

A build saves its state at each step, on the machine that runs it. Each `report.sh` call writes one small file, `~/.local/state/cook/runs/<repo>-<ref>.json`. It holds:

| Field | Content |
| --- | --- |
| Step | The last step, and the step to continue from. After a `blocked` step, this is the step before the block. |
| Agent and machine | The Paseo agent ID, the agents it replaced, and the machine name. |
| Git | The ref, the branch, the base, the worktree, and the latest commit. |
| Brief | A copy of the build brief, with the intake answers word for word. |
| Spec | A copy of the approved spec, its path and link, and the time of the approval. |
| Verify | The verdict and a copy of each receipt, with the commit that it checked and the number of attempts. |

The copies are in the folder `~/.local/state/cook/runs/<repo>-<ref>/`, so they stay when the worktree is gone. Each write replaces the file atomically, so a crash cannot leave half a file. `/cook-status` and `/cook cleanup` read the same files.

### Setup

There is no setup. Every build saves its state.

### How resume works

`/cook resume` with no ref lists the builds that are not done, on each machine:

```text
REF          MACHINE      STEP           AGENT      WORKTREE                 AGE    KEY
#42          studio       verify         gone       clean                    3h     recipe-app-42
csv-export   local        blocked:build  idle       2 uncommitted file(s)    1d     recipe-app-csv-export
```

`/cook resume <ref>` checks the worktree, the branch and the agent. Then it does one of two things:

- The agent is idle in Paseo: the hub sends it a `COOK RESUME` message.
- The agent is gone: the hub starts a new agent in the same worktree, with the same provider, model and mode.

The message names the step to continue from, the copy of the brief, the approved spec, the last receipt and the latest commit. The agent continues from that step. After a spec approval, `report.sh` refuses to go back to the plan step.

Resume stops, and changes nothing, in these cases:

| Case | What resume does |
| --- | --- |
| The worktree has uncommitted changes. | It lists the files. The hub asks you. On yes, the agent keeps the changes. |
| The worktree is gone, but the branch has the latest commit. | It asks you. On yes, it checks out the branch in a new worktree. |
| The branch is gone, or the worktree lost the latest commit. | It tells you where the commit is. It never makes, moves or deletes a branch. |
| The agent is still running, or another agent works in the worktree. | It tells you. There is nothing to resume. |
| The machine does not answer. | It tells you. Try again when the machine is back. |

### Example

The machine of build #42 restarted during verify:

```text
you> /cook-status
     #42   verify   you (resume)   3h   studio   agent is gone. Run /cook resume #42
you> /cook resume #42
     #42 on studio: started agent b81c in the same worktree. It continues at verify,
     with the approved spec and the last receipt (FAIL, attempt 2).
```

---

## Working with cook day to day

| Habit | How |
| --- | --- |
| Run several builds | Start more than one `/cook` from the same session. Worktrees keep them apart. |
| Use `/cook-status` | Run it when you do not want to wait for a push. It is read-only and does not slow the builds. Use `--watch` to redraw every 10 seconds. Use `/cook-status <ref>` for detail on one build. |
| Answer blocks fast | The column WAITING ON shows who must act. Builds that wait on you come first. A block you answer fast is a build that finishes sooner. |
| Review the PR evidence | Read the verify receipt, the screenshots, and the deploy steps. Do not skip the NOT COVERED lines. |
| Apply the deploy steps | cook never changes a shared environment. When the PR has a deploy-steps comment, do the steps yourself. |
| Review the retro changes | New recipes, scripts, and verifier checks are in the PR. Reject a recipe that does not meet the bar. |
| Resume | When a build stopped (a crash, a restart), run `/cook resume <ref>`. It continues from the saved step. |
| Clean up | After you merge, run `/cook cleanup`. It lists the builds, and after you approve, it removes the agent, the worktree, the local branch and the run state. It never removes unsaved work. |

---

## Tests

The scripts have workflow tests in `tests/`. One command runs shellcheck and all the tests:

```bash
tests/run.sh
```

- `tests/run.sh resume` runs only the tests whose name contains `resume`. `-v` shows the output of each test.
- Each test runs in its own sandbox: a temporary `HOME`, `COOK_STATE`, `XDG_*` folders and `TMPDIR`. The tests never read or change your real home folder.
- Stubs in `tests/stubs/` replace `paseo`, `gh`, `ssh`, `brew`, `npx`, `tailscale` and `curl`. Each repo is a temporary git repo with a bare `origin`. The `ssh` stub runs the command on this machine with the `HOME` of the other machine, so tests can cover builds on other machines.
- The tests need `bash`, `git`, `python3` and `jq`. They need no other tool.
- GitHub Actions runs the same command on macOS and Ubuntu for each push and pull request.

---

## Credits

cook builds on the work of Kun Chen.

- Video: https://www.youtube.com/watch?v=iQyg-KypKAA
- Video: https://www.youtube.com/watch?v=88B6DimMD2g
- [Lavish](https://github.com/kunchenguid/lavish-axi)
- [AXI](https://github.com/kunchenguid/axi) and [axi.md](https://axi.md)
- [no-mistakes](https://kunchenguid.github.io/no-mistakes/)
