<p align="center"><img src="docs/logo/cook-wordmark-light.svg#gh-light-mode-only" height="72"><img src="docs/logo/cook-wordmark-dark.svg#gh-dark-mode-only" height="72"></p>

<p align="center"><b>From issue to reviewed PR. You write the spec. Agents do the rest.</b></p>

<p align="center"><img src="docs/demo.gif" width="100%" alt="cook demo: you run /cook on an issue, shape the spec in Lavish, agents build, verify and learn, and you review a PR with proof"></p>

cook is a kit of agent skills. It takes one issue or prompt to a pull request that is ready for review. You do three things: the intake, the spec and the review. Agents do the rest, each build in its own git worktree, and every build leaves the project easier for the next agent. cook works with any agent that can use shell, git and files.

- **Spec.** Spend the most time on the spec. Specs and mockups go through a [Lavish](https://github.com/kunchenguid/lavish-axi) review loop. No code is written before you approve.
- **Verify.** Verification is as important as the build. Each project has verifier skills, and a build is ready only when they pass with fresh evidence.
- **Learn.** Each build ends with a retro. Verifiers get better, and recipes and scripts keep the next agent from the same mistakes.

## Quick start

```bash
npx skills add EthanL06/cook
~/.agents/skills/cook/doctor.sh --fix
```

Then, in your agent, inside your project:

```text
/cook-init            set up this project once: cook.md, verifiers, recipes
/cook #42             take issue #42 to a reviewed PR
/cook-status          see every build and who it waits on
/cook resume #42      continue a build after a crash or a restart
/cook cleanup         remove merged worktrees, agents and branches
```

## Install

| Way | Command |
| --- | --- |
| skills CLI | `npx skills add EthanL06/cook`, then `~/.agents/skills/cook/doctor.sh --fix` |
| git clone | `git clone https://github.com/EthanL06/cook ~/Developer/cook && ~/Developer/cook/install.sh add` |
| Your agent | Paste the prompt below |

<details>
<summary>Prompt to paste into your agent</summary>

```text
Install the cook kit from https://github.com/EthanL06/cook.

1. Clone the repo to ~/Developer/cook.
2. Run ~/Developer/cook/install.sh add. It links the skills and checks the tools.
3. Show me the report: what is missing, what is required, and what is optional.
4. Ask me once if I want the missing tools installed. On yes, run
   ~/Developer/cook/skills/cook/doctor.sh --fix --yes and show me the result.
5. Walk me through the steps under "Do these yourself" (sign-ins, API keys).
6. Ask me which optional parts I want: ntfy push, Tailscale machines, a CLI proxy.
7. Offer to run /cook-init in my project.

Never type or store a secret for me. This includes tokens, API keys, and passwords.
When a tool needs a secret, tell me where to put it and let me do it.
```

</details>

## The skills

| Skill | What it does |
| --- | --- |
| `/cook` | Takes an issue, URL or prompt to a reviewed PR. Your session stays a hub that reports plan links, blockers and PRs. Also `resume` and `cleanup`. |
| `/cook-init` | Sets up one project: `.agents/cook.md`, one verifier per area, recipes. Runs each verifier once before it writes it. |
| `/cook-verify` | Proves a build works with the project's verifiers. Ends with PASS, FAIL or BLOCKED. |
| `/cook-learn` | The retro. Turns repeated problems into tests, verifier checks, scripts or recipes. |
| `/cook-status` | Read-only view of every build. `--watch` keeps it live. |

## What you need

**Required:** [Lavish](https://github.com/kunchenguid/lavish-axi), [Paseo](https://paseo.sh), [agent-browser](https://github.com/vercel-labs/agent-browser), `gh`, `git`, Node.js, and Claude Code or Codex.
**Pluggable:** tracker (GitHub, Linear, none), review loop ([no-mistakes](https://kunchenguid.github.io/no-mistakes/), Greptile, none), browser, Mobbin references.
**Optional:** ntfy pushes to your phone, Tailscale for builds on other machines.

`doctor.sh` checks all of it for the current project and installs what it can after you say yes.

## Hard rules

cook never merges, never force-pushes, never rebases a pushed branch, and never writes data or applies migrations to a shared environment. It stops only the processes it started, never redoes an approved spec, and sends one push per blocker.

## Reference

<details>
<summary>install.sh commands</summary>

| Command | What it does |
| --- | --- |
| `install.sh add [--project <dir>]` | Links the skills. With `--project`, installs into the `.agents/skills` folder of one repo. |
| `install.sh update [--project <dir>]` | Pulls the latest kit. Global links update by themselves. With `--project`, copies the new version into the repo. |
| `install.sh remove [--project <dir>]` | Removes the skills that install.sh put there. Your `cook.md`, verifiers and recipes stay. |
| `install.sh doctor [--fix]` | Checks each tool the project needs. With `--fix`, it lists the install commands, asks once, and runs only what you approve. |

</details>

<details>
<summary>Missing tools and doctor.sh</summary>

`doctor.sh` checks what this machine needs for the current project. It reads `.agents/cook.md`, so a Linear project needs `LINEAR_API_KEY`, `review: greptile` needs a Greptile skill, and `ui_refs: mobbin` needs a Mobbin sign-in.

- `doctor.sh` shows the report. Nothing changes.
- `doctor.sh --fix` lists the install commands (brew, npm, npx, the agent-browser Chrome download, the no-mistakes installer), asks once, runs what you approve, and checks again.
- Steps that need an account, a password or a secret are never run. Doctor lists them under "Do these yourself": `gh auth login`, the Claude Code or Codex sign-in, API keys, Mobbin and ntfy.
- `/cook` runs `doctor.sh --quick` at the start of each build. It is silent when the last check passed in the past 24 hours.

</details>

<details>
<summary>What /cook-init creates</summary>

| Path | Content |
| --- | --- |
| `.agents/cook.md` | Project facts: a YAML header and Markdown rules. |
| `.agents/skills/verifier-*` | One verifier for each area the repo has. |
| `.agents/recipes/` | `README.md` index and `dev-setup.md`. |
| `AGENTS.md` | A "Cooking" section. |
| `scripts/qa/` | Not made at init. The retro makes it later. |

The init preflight needs a GitHub remote (it offers `gh repo create --private` and runs it only after you say yes) and a clean, committed tree (it stops and asks you to commit, and never commits for you).

</details>

<details>
<summary>All tools and options</summary>

| Part | Default | Status | Role |
| --- | --- | --- | --- |
| Specs and mockups | [Lavish](https://github.com/kunchenguid/lavish-axi) (`npx -y lavish-axi`) | Required | Review loop for the spec |
| Agents | [Paseo](https://paseo.sh) | Required | Agents in git worktrees, parallel builds |
| CLIs | [AXI](https://axi.md) tools: lavish-axi, and linear-sdk-axi for Linear | Required | Used in place of MCP servers. Use fewer tokens. |
| Browser | [agent-browser](https://github.com/vercel-labs/agent-browser) | Required | Browser verifier |
| Git host | `gh` and `git` | Required | Push and PR |
| Tracker | github | Pluggable | `github`, `linear`, or `none` |
| Review loop | [no-mistakes](https://kunchenguid.github.io/no-mistakes/) | Pluggable | `no-mistakes`, `greptile`, or `none` |
| Browser option | agent-browser | Pluggable | `agent-browser`, `chrome-devtools-axi`, or `playwright-axi` |
| UI references | Mobbin (`mobbin-axi`) | Pluggable | `ui_refs: mobbin` or `none` (default). Needs a Mobbin account. |
| Push to phone | ntfy | Optional | Pushover also works. Config is in `~/.config/cook/notify.env`. |
| Many machines | Tailscale | Optional | Run builds on other machines. Lavish links open on your phone. |
| Many accounts | CLI proxy | Optional | Guide only. cook does not use it directly. |

</details>

<details>
<summary>Resume a build</summary>

Each build saves its state at each step in `~/.local/state/cook/runs/` on its machine: the step, the agent, the branch and the latest commit, and copies of the brief, the approved spec and the verify receipts. When an agent crashes or a machine restarts, `/cook resume <ref>` sends the agent a message, or starts a new agent in the same worktree. The new agent continues from the saved step. `/cook resume` with no ref lists the builds that can continue. See [Resume a build that stopped](docs/guide.md#resume-a-build-that-stopped).

</details>

<details>
<summary>Tests</summary>

```bash
tests/run.sh
```

This command runs shellcheck and the workflow tests: install, launch and branch conflicts, configs, run state, resume, status and cleanup. The tests use stubs for `paseo`, `gh`, `ssh`, `brew`, `npx` and `tailscale`, and temporary git repos. They never touch your real home folder. GitHub Actions runs them on macOS and Ubuntu. See [Tests](docs/guide.md#tests).

</details>

## Docs

- [Workflow guide](docs/guide.md): every tool, why it is in the flow, and how to use it.
- [cook.md reference](docs/cook-md.md): every field in `.agents/cook.md`.
- [The flow as a diagram](docs/flow.svg)

## Credits

cook builds on the work of Kun Chen: [L8 Principal's Agentic Engineering Workflow](https://www.youtube.com/watch?v=iQyg-KypKAA), [How This Ex-Meta L8 Engineer Ships 40 PRs a Day with AI Agents](https://www.youtube.com/watch?v=88B6DimMD2g), and his tools [Lavish](https://github.com/kunchenguid/lavish-axi), [AXI](https://github.com/kunchenguid/axi) and [no-mistakes](https://kunchenguid.github.io/no-mistakes/).

## License

MIT
