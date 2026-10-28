---
name: cook-init
description: Set up a project for cook. Checks the repo first (GitHub remote, committed work), reads it to find its apps, commands, tests, deploy config and design system, drafts .agents/cook.md and one working verifier skill per area it finds, runs each verifier once, shows everything in a Lavish page, and writes the files only after the user approves. Safe to run again; it then shows a diff against what exists. Use when the user invokes /cook-init, or when /cook finds no .agents/cook.md.
argument-hint: "[--refresh]"
---

# cook-init

Makes the per-project part of cook. The cook skills hold the process. These files hold the project facts:

| File | What |
|---|---|
| `.agents/cook.md` | Project facts: base branch, tracker, branch and commit format, commands, deploy-step patterns, verifiers, review loop, rules. |
| `.agents/skills/verifier-<kind>/SKILL.md` | One per area the repo really has. Each works on the first day. |
| `.agents/recipes/README.md`, `dev-setup.md` | The index of notes for future agents, and how to set up and run this repo. |
| A "Cooking" section in `AGENTS.md` | Tells any agent where the above are. |

`scripts/qa/` is not made here. /cook-learn makes it the first time a QA flow is worth a script.

```sh
I="$(cd "$(dirname "$(readlink -f ~/.agents/skills/cook-init/SKILL.md 2>/dev/null || readlink -f ~/.claude/skills/cook-init/SKILL.md)")" && pwd)"
```

## Rules

- Write nothing in the repo before the user approves the review page.
- Never commit, push or create anything on GitHub without the user's yes.
- Never put secrets in any file. Name the env var and where its value lives.
- Every fact in `cook.md` comes from a file you read or a command you ran. When you cannot find it, ask.

## 1. Preflight

Run these from the repo root. Stop at the first problem, tell the user, and give the exact command to fix it.

1. **Main checkout.** `git rev-parse --show-toplevel` must equal the main checkout (not a linked worktree).
2. **GitHub remote.** `git remote get-url origin`. With no remote, cook cannot open a PR. Offer: `gh repo create <owner>/<name> --private --source . --push`. Run it only after the user says yes, and with the name they choose.
3. **Committed work.** `git status --porcelain`. With uncommitted files, stop: cook builds start from the base branch on `origin`, so they would not see that work. Show the count and the top folders, and ask the user to commit and push. Never commit for them.
4. **Base on origin.** The base branch exists on `origin` and is not behind the local one.
5. **Tools.** Run `~/.agents/skills/cook/doctor.sh` (or `~/.claude/skills/cook/doctor.sh`). If it exits 1, show the report and ask: "Install the missing tools now?" On yes, run it again with `--fix --yes`. Steps under "Do these yourself" (sign-ins, API keys, accounts) are for the user. A missing required tool stops the init. Optional tools are a note. At the end of step 3, run doctor again on the draft (`COOK_CONFIG=<draft cook.md> doctor.sh`), because the tracker, review loop, browser and `ui_refs` change what is required.

## 2. Read the repo

Read, do not guess:

- `README*`, `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING*`, and the nested agent files.
- Package manager and workspace layout (`package.json` scripts, `pnpm-workspace.yaml`, `turbo.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `Makefile`, `justfile`).
- Each app or service: what it is, how to start it, its port, what it needs (database, env, emulator).
- Tests and lint, and the one command that runs the full check.
- CI (`.github/workflows/`), PR template, commit rules (commitlint, Lefthook, Husky), branch naming in recent history (`git log --format=%D -50` and `git branch -r`).
- Deploy config: migrations, `wrangler.*`, `vercel.json`, `fly.toml`, `supabase/`, Docker, `eas.json`, env examples.
- Design system: Tailwind config, CSS variables, component library, theme files.
- The tracker: GitHub Issues if the repo has issues, Linear if the docs or branch names show Linear keys, else ask. Default: `github`.
- UI references: `ui_refs: mobbin` only when the user has Mobbin (`npx --no -- mobbin-axi auth status` says authenticated) and the repo has a UI. Else `none`. Ask when it is not clear.

## 3. Draft

1. **`cook.md`** from `$I/templates/cook.md`. Fill every field from what you read. Put rules that are only prose (for example "never run with --remote") in its body.
2. **Verifiers.** Map each area to a kind, then fill the template from `$I/templates/verifiers/<kind>.md`:

   | Area | Kind |
   |---|---|
   | Web UI | `browser`, plus `design` when there is a design system or mockups matter |
   | HTTP API, worker, server | `api` |
   | Database, migrations, jobs, scrapers | `data` |
   | Unit and integration tests, lint, typecheck | `tests` (always) |
   | Load time, rendering, memory, bundle size | `performance` (only when the user wants it) |
   | iOS or Android app | `mobile` |

   Replace every `<...>` with the real command, port, URL, test account source and data setup. A verifier with a placeholder left is not done.
3. **Recipes.** `$I/templates/recipes-README.md` as `.agents/recipes/README.md`, and a `dev-setup.md` recipe with the exact steps that worked for you in step 4.
4. **AGENTS.md section** from `$I/templates/agents-section.md`. Add it at the end, or update the section if it is there. If the repo has only `CLAUDE.md`, add it there.

## 4. Prove each verifier

Run each drafted verifier once against the base branch, from a scratch worktree (`git worktree add <tmp> origin/<base>`), with its evidence in `.context/verify/init-<kind>/`. Every verifier must PASS on good code. When one fails, fix the verifier (wrong command, missing setup, slow start), not the code. When a verifier cannot run here (no simulator, no database), mark it BLOCKED with the reason and say what the user must install. Remove the scratch worktree after.

## 5. Review in Lavish

One page (`lavish` skill, `plan` playbook) in `.lavish/cook-init.html`:

- Each file in full, with what it is for. Mark facts you inferred with a badge, so the user checks them.
- The verifier results: PASS, FAIL or BLOCKED, with one screenshot or log line each.
- What is missing (tools, CI, tests), as notes. Do not fix those here.
- An approve control.

Apply feedback until the user says "approve". Then write the files. Do not commit: tell the user to commit them with their next change, or commit them only if the user says to.

## Refresh

`/cook-init --refresh`, or a second run: read the existing files, draft the changes the repo now needs (a new app, a changed command, a removed area), and show only the diff for approval. Never drop a verifier's `## Track record` or a check that /cook-learn added.
