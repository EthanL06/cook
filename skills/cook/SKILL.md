---
name: cook
description: Take one issue or prompt to a pull request that is ready for review. Asks the intake questions, makes or reads the issue, starts a Paseo agent in a fresh worktree, iterates a Lavish spec with mockups until the user approves, then builds, runs /cook-verify, opens the PR, runs the review loop and /cook-learn, and sends a push when it is blocked or ready. The invoking session stays a hub that reports every build. On "cleanup" it removes merged builds after the user approves. Never merges or force-pushes. Use when the user invokes /cook, or asks the hub to clean up builds.
argument-hint: "[#42 | ENG-123 | issue URL | prompt] [on <machine>] [from <branch>] | cleanup [ref ...]"
---

# cook

One command from an issue or a prompt to a PR that is ready for review. The user takes part in three places: the intake, the spec and the final review. A fourth only when a build is blocked. Everything between is autonomous.

All project facts come from `.agents/cook.md` in the repo (read it with `config.py`). This file holds only the process. When `cook.md` or the project's `AGENTS.md` is stricter than this file, follow them.

Modes:

- **Intake** (the user typed `/cook ...`): steps 1 to 3, then **Watch**. This session becomes a hub. It can start more builds, on any machine, and it reports what each build does.
- **Build** (the prompt starts with `COOK BUILD`): steps 4 to 10, in the Paseo agent that step 3 starts. Skip the intake. Take every answer from the brief.
- **Cleanup** (the user says "clean up", types `/cook cleanup [ref ...]`, or accepts a cleanup suggestion): **Cleanup**, in the hub. It never starts by itself.

Helpers in this skill folder:

```sh
S="$(cd "$(dirname "$(readlink -f ~/.agents/skills/cook/SKILL.md 2>/dev/null || readlink -f ~/.claude/skills/cook/SKILL.md)")" && pwd)"
C="python3 -I $S/config.py"      # $C get base | $C get commands.dev | $C json
T="$S/tracker.sh"                # view, search, create, comment, state, url, branch
```

- `$S/machines.py [--origin <remote>] [--json]`: the machines that can run the build and what each one is missing. Without Tailscale, only this machine.
- `$S/launch.sh --machine <m> --repo <checkout> --ref <ref> --title <title> --branch <b> --base <base> --brief <file> [-- <paseo flags>]`: checks the machine and the branch, then starts the build agent.
- `$S/report.sh <step> <ref> "<text>" [url]`: the build agent tells the hub its step. Steps: `plan build verify review learn blocked ready`.
- `$S/notify.sh plan|blocked|ready <ref> "<message>" [url]`: the phone push (ntfy or Pushover, from `~/.config/cook/notify.env`). Exit 3 means pushes are not set up. Say so once and continue.
- `$S/watch.sh <machine>:<agent-id>:<ref> ...`: the hub's event stream.
- `$S/cleanup.sh list [ref ...]` and `$S/cleanup.sh run <build> ...`.
- `/cook-status` (its own skill) shows every build at any time. Use it when the user asks for status.
- Skills it calls: `cook-verify`, `cook-learn`, `lavish`, `paseo`, the review skill from `cook.md` (`no-mistakes` or a Greptile loop), and `mobbin-axi` when `ui_refs: mobbin`.

## Rules

- Never merge, force-push, rebase a pushed branch, close the PR, or push to a branch other than the build's own branch.
- Never write data, apply a migration or deploy to a shared environment (staging included) unless the user says so for that change. Deploy steps go in a comment for a person.
- Stop only the processes, servers and browsers you started. Do not touch other worktrees.
- Run every browser headless, so it never takes focus and builds can run side by side. agent-browser and playwright-axi are headless by default; use the headless mode of chrome-devtools-axi too. Use a headed window only when a check cannot work without one: the user wants to watch or must act in the browser (sign-in, CAPTCHA, a permission prompt), real hover, the real OS clipboard, or a smooth high-frame-rate recording. Say why in the report, and go back to headless after that check.
- Write issue, PR and push text in plain, short sentences. Never use the em dash.
- One push for each blocker. Never send the same blocker twice.

## 1. Intake (intake mode)

1. **Config.** Run `$C check`. Exit 2 means there is no `cook.md`: stop and offer `/cook-init`. Exit 4 means it is not valid: show the problems it lists and stop until the user fixes them. Do not guess the project facts.
   **Tools.** Run `$S/doctor.sh --quick`. It is silent and fast when the last check passed. If it exits 1, show its report and ask: "Install the missing tools now?" On yes, run `$S/doctor.sh --fix --yes`. Steps it lists under "Do these yourself" (sign-ins, API keys, accounts) are for the user. Stop until a required one is done. Never type a secret for the user.
2. **Parse the arguments:** an issue ref or URL, or a prompt; a machine (`on desktop-pc`); a base branch (`from release-2`). The base is `$C get base` unless the user names one. Do not ask about it.
3. **Read what exists.** With a ref: `$T view <ref>`. With a prompt: `$T search "<key words>"` for a related open issue.
4. **Machines.** `python3 -I $S/machines.py --origin "$(git remote get-url origin)"`. Skip the machine question when this is the only machine.
5. **Ask only what the issue, the prompt and the arguments do not answer**, in one batch (the harness question tool if there is one, else one message). Give a recommended answer for each:
   - **Done:** what "done" means, as checks a person can see.
   - **Out of scope:** what must not change.
   - **Variations:** only when the work adds or changes UI that a user sees: how many mockup variations (1 to 4). Recommend 3, or 2 when the design space is small.
   - **Evidence:** what the user wants as proof (default: screenshots and short text; they can ask for video, numbers, benchmarks).
   - **Review loop:** run the `cook.md` review loop, yes or no. Recommend yes.
   - **Performance:** run `verifier-performance`, yes or no. Recommend yes only when the change can change load time, rendering or memory a lot.
   - **Machine:** only with more than one ready machine. Show each with "ready" or what it is missing. Recommend this machine if it is ready.
   - Only when they apply: "Is this the same as <related issue>?", and test data the flow cannot make itself.
6. **Preflight.** The base branch must exist on `origin`, and the chosen machine must be ready. If the machine only misses the cook skill, offer `install.sh add` there. For anything else, ask for another machine.

## 2. Issue and branch (intake mode)

- No issue and the tracker is not `none`: write a short issue body (problem, done checks, out of scope) to a scratch file, then `$T create "<title>" <file>`. Use the ref it prints.
- With tracker `none`, the ref is a short slug of the prompt (`csv-export`).
- **Branch:** use `$T branch <ref>` when the tracker has one. Else fill `$C get branch` (placeholders: `{type}` feat, fix, chore...; `{slug}` 2 to 5 words; `{id}` the issue number or key, lowercase; `{user}` the GitHub login). If `cook.md` sets `branch_max`, cut the slug to fit and tell the user the name.
- If the branch already exists, `launch.sh` continues on it (step 3) and says so in its `note`. Tell the user.

## 3. Start the build agent (intake mode)

Every build runs in a Paseo worktree, also on this machine. `H` is empty for this machine and `--host ssh://<machine>` for another (`paseoHost` in `machines.py --json`). `R` is the machine's checkout (`repo`).

1. Write the brief from `$S/templates/brief.md` to a scratch file: every intake answer word for word, the issue ref, URL and title, branch, base, machine, and its Tailscale DNS name and IP.
2. Pick the provider and model with the `paseo` skill (configured profiles first). Run the agent with no permission prompts: `--mode bypassPermissions` for Claude, `--mode full-access` for Codex, unless the user asks for another mode.
3. Start it with `launch.sh`. It fetches the base, checks the branch, and starts the agent with the title `<ref>: <title>` and the `cook` labels that status, resume and cleanup read:
   ```sh
   $S/launch.sh --machine <machine or local> --repo "$R" --ref <ref> --title "<title>" \
     --branch <branch> --base <base> --brief <brief file> -- <provider and mode flags>
   ```
   It prints `build=<machine>:<agent-id>:<ref>`, `mode` (`new`, `origin` or `local`) and a `note`.
4. Tell the user the machine, the agent ID, the branch, the `note`, and how to open it (the Paseo app, or `paseo $H attach <agent-id>`). Then **Watch**.

When `launch.sh` fails, nothing has started. Tell the user what it printed and stop:

| Exit | Meaning | What to offer |
| --- | --- | --- |
| 3 | The machine or its Paseo daemon does not answer. | Another machine, or wait until it is back. |
| 4 | No checkout on that machine, or the base is not on `origin`. | Clone the repo there, or another base. |
| 5 | The branch is checked out in another worktree, or local and `origin` differ. | `/cook resume <ref>` when a build already uses it, else another branch name. |
| 6 | `paseo run` failed (for example the provider is not signed in). | Fix what it says, then start again. |

## Watch (hub)

Keep the list of builds this session started as `<machine>:<agent-id>:<ref>`.

1. Run `$S/watch.sh <every build>` with the harness tool that wakes you on each new output line (Monitor in Claude Code). If there is none, run it in the background and read its output at the start of each turn. Restart it with the full list when you start another build. It never prints a line twice.
2. Report each event in one line: ref, machine, step, text, link. Report every spec version, not only the first.
3. `blocked`: give the reason and the `Next:` reply, and tell the user to answer in the build agent (Paseo app or `paseo attach`). Never answer for the user.
4. `permission`: say in one line which tool the hub allowed.
5. `merged` or `closed`: say so and suggest **Cleanup** for that build. A closed build is only a suggestion.
6. When the user asks for status, run `/cook-status`.

The build agent answers its own questions. The hub only reports and allows permission requests.

## Cleanup (hub)

A build leaves its agent, worktree, local branch, the processes it started and its event log. Cleanup removes them. It never touches the issue, the PR, the remote branch, other worktrees or `origin`.

1. When the hub starts, and on each `merged` event, run `$S/cleanup.sh list`. If it shows a `target` or `suggest` line or a `full` machine, suggest a cleanup in one line. Do not wait for the answer.
2. On "clean up": run `$S/cleanup.sh list <refs the user named>`. Show a table: ref, machine, PR, verdict, reason. Show `suggest` builds apart. For each `skip`, show what is not saved and the worktree path.
3. Ask which builds to remove (all, some, none). Then `$S/cleanup.sh run <each approved build>`. It checks again for unsaved work. Never get around a skip with `--force` or `git branch -D`.
4. Report one line per build, and restart `watch.sh` with the builds that are left.

## 4. Spec in Lavish (build mode)

The spec is the longest step. The more exact it is, the less rework the build needs.

1. `$S/report.sh plan <ref> "Reading the code."` Then read the issue, `cook.md`, `AGENTS.md` and the nested ones in the area, `.agents/recipes/README.md` and the recipes that apply, and the code. Find the active code path, not a dead copy. Read-only subagents can research in parallel.
2. Write the spec at the place `$C get specs` names: `local` is `.lavish/cook-spec.html` (git-ignored), `committed` is `docs/specs/<ref>.html`. Use the `lavish` skill and its `plan` playbook: done checks, approach, files to change, how the work splits (step 5), the verification and evidence plan, out of scope, risks and open questions with answer controls. For UI work, add **Mockups** below.
3. On a machine that is not the user's, the link must open from the user's devices. Before the first `lavish-axi` command, `export LAVISH_AXI_ALLOWED_HOSTS=<tailscale name>,<tailscale DNS name>,<tailscale IP>` (`npx -y lavish-axi stop` first if a server runs). Give the URL with the Tailscale name.
4. Open it, `$S/report.sh plan <ref> "Spec v1 is ready to review." <url>`, `$S/notify.sh plan <ref> "Spec is ready to review." <url>`, then poll for feedback (`npx -y lavish-axi poll <file>`).
5. Apply each round of feedback, `$S/report.sh plan <ref> "Spec v<n>: <what changed>." <url>`, and poll again with `--agent-reply`. Start coding only when the feedback says "approve". A question is not approval.
6. On approve: `$T state <ref> in-progress` and `$S/report.sh build <ref> "Spec approved. Build started."`. With `specs: local`, export the approved spec (`npx -y lavish-axi export`) and attach it to the issue in step 6.

### Mockups

Open the `comparison` and `input` playbooks too.

1. **Research first.** Screenshots of the current UI at the affected screens. Read the app's design tokens, theme and shared components, so the mockups use the real colors, type, spacing and components. When `$C get ui_refs` is `mobbin`, use `mobbin-axi` to show 3 to 5 good production references with one line each. With `none`, skip the references and say so in the spec.
2. **Variations** from the intake answer. Each is a different direction (layout, flow or interaction model), with real copy and realistic data. For each: a name, the idea in one sentence, pros, cons and the open questions it adds. Mark the recommended one and say why.
3. **Working prototypes** when there is interaction, with a state switcher (empty, loading, filled, long content, error, success, disabled, roles), a viewport switch and a light and dark switch when the app has dark mode. Keep the state when the user changes the variation.
4. **Compare views:** all variations side by side in one state, one at full size, and current versus proposed.
5. **Choice** with `input` playbook controls: pick one, or mix parts, with a note.

When a mockup cannot show the real behavior (animation timing, real data volume), say so and propose a prototype on a dev route before the full build.

## 5. Build (build mode)

Split the work only when there are two or more parts that change their own files, need no output of another part, and can be checked alone. Otherwise build it yourself.

When it splits: do the shared parts first (types, contracts, file moves). Then start one subagent per part (the harness subagent tool, else `paseo run --workspace <this workspace>`), each with the goal, the files it owns, the files it must not touch, the done check, and "do not commit or push". Read each diff, fix overlaps, then run the checks from `$C get commands`.

## 6. Verify and evidence (build mode)

1. `$S/report.sh verify <ref> "Build done. Verify started."`, then `/cook-verify` with the ref, the done checks, and the performance answer. Make the evidence the user asked for as part of it. For UI work, take screenshots in the same states and viewports as the approved mockup, and list each difference from the mockup with its reason.
2. FAIL that the repair loop cannot fix, or BLOCKED: **Blocked**.
3. PASS: post the evidence on the issue (`$T comment <ref> <file>`): the receipt summary, the media and the approved spec export. With tracker `none`, the evidence goes only in the PR.

## 7. Pull request (build mode)

1. Commit in the format `$C get commit` (it can be `conventional`). `git push -u origin <branch>`. Retry on network errors. Never force.
2. **Deploy steps.** Compare the diff against `origin/<base>` with the `deploy_steps` patterns in `cook.md`, and read the deploy notes in its body. Fill `$S/templates/deploy-steps.md` and post it on the issue. When nothing matches, post "No deploy steps: code only, normal deploy." Never do the steps yourself.
3. `gh pr create --base <base> --head <branch> --title "<title>" --body-file <file>` from `$S/templates/pr-body.md`. Follow the repo's PR template if it has one. Include `Closes <ref>` for GitHub issues, the issue URL for Linear, a `## Verification` section (result, verified head SHA, evidence link) and `## Deploy steps`.
4. `$S/report.sh review <ref> "PR is open." <PR url>`.

## 8. Review loop (build mode)

Skip if the intake answer was no or `$C get review` is `none`.

- `no-mistakes`: use the `no-mistakes` skill on this branch and follow it until the pipeline passes.
- `greptile`: run the Greptile review loop skill on the PR.

After each round of fixes: if visible behavior or a number the user asked for changed, post new evidence (step 6.3). Otherwise post one line: "Checks pass again on <short sha> after the review fixes." If a fix changed the deploy steps, update the comment and the PR section. A loop that cannot finish goes to **Blocked**.

## 9. Learn (build mode)

`$S/report.sh learn <ref> "Retro started."`, then `/cook-learn` with the ref. It may change recipes, verifiers, tests or `scripts/qa/`. Commit those changes on this branch, push, and add one line per change to the PR under `## Learned`.

## 10. Done (build mode)

1. `$T state <ref> in-review`.
2. `$S/report.sh ready <ref> "<one line: what changed>. PR is ready." <PR url>` and `$S/notify.sh ready <ref> "<same line>" <PR url>`.
3. Final message: PR URL, issue URL, verify result, review result, deploy summary, what was learned, and anything the reviewer must look at.

The PR and the issue hold everything the review needs. Do not make a separate hand-off page.

## Blocked

Only for a thing that stops you and that only the user can fix: a product decision, access or test data you cannot get, or a scope change. Solve everything else yourself.

1. Write one sentence with the real reason, and a `Next:` line with the exact reply that unblocks it (`Next: reply "use seed user 3" or "skip the export check"`).
2. `$S/report.sh blocked <ref> "<reason> Next: <reply>" <issue or PR url>` and `$S/notify.sh blocked <ref> "<reason> Next: <reply>" <url>`. Post the same text on the issue.
3. Wait for the user's answer in this agent. Then report the step you continue (`$S/report.sh build <ref> "Unblocked. Build continues."`) and continue.
