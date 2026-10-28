# `.agents/cook.md` reference

Each project has one `cook.md`. `/cook-init` writes it, and you can edit it by hand. It has two parts:

- A YAML header with the values that scripts read.
- A Markdown body with the rules and notes that agents read.

The cook skills hold the process. This file holds the facts about your project. When the body is stricter than a cook skill, agents follow the body.

cook reads the file from the main checkout. A build in a worktree uses the same file as the repo it came from.

## Header fields

| Field | Default | Values and meaning |
|---|---|---|
| `base` | `main` | The branch that PRs go to. `/cook ... from <branch>` overrides it for one build. |
| `tracker` | `github` | `github` (GitHub Issues), `linear`, or `none` (prompt only, evidence goes only in the PR). |
| `linear_team` | none | The Linear team key, for example `ENG`. Only for `tracker: linear`. |
| `branch` | `{type}-{slug}` | The branch name format. Placeholders: `{type}` (feat, fix, chore...), `{slug}` (2 to 5 words), `{id}` (issue number or key, lowercase), `{user}` (your GitHub login). A tracker that names branches (Linear) wins. |
| `branch_max` | none | The longest branch name. cook cuts the slug to fit. Use it when a tool builds names from the branch (preview deploys, worker names). |
| `commit` | `{type}: {summary}` | The commit subject format, or `conventional` when commitlint checks it. |
| `review` | `no-mistakes` | The review loop after the PR opens: `no-mistakes`, `greptile` or `none`. |
| `browser` | `agent-browser` | The browser tool for verifiers: `agent-browser`, `chrome-devtools-axi` or `playwright-axi`. |
| `specs` | `local` | `local`: the spec stays in git-ignored `.lavish/`, and an exported copy goes on the issue. `committed`: the spec is saved as `docs/specs/<ref>.html` in the PR. |
| `notify` | `on` | `off` stops pushes for this project. The push service is set per person, not here (see below). |
| `commands` | none | Named commands that verifiers and builds use. Common keys: `install`, `dev`, `check`, `test`, `lint`, `build`, `setup`. |
| `deploy_steps` | none | Path patterns. When a diff touches one, the build writes a deploy-steps comment for a person. |
| `verifiers` | none | The verifier kinds this project has, for example `[browser, api, data, tests]`. Each is `.agents/skills/verifier-<kind>/`. |

The header supports a small YAML subset: plain values, quoted strings, inline lists (`[a, b]`), block lists (`- a`), one level of nested keys, and `#` comments.

## Body

Put here what an agent must know and cannot read from the code:

- **Rules.** For example: "Use local D1 only. Never run wrangler with --remote." or "Keep the website base path /app."
- **Deploy steps.** How each kind of step is done in this project, or a link to the doc that says it.
- **Anything a verifier needs to know**, such as where test accounts come from. Never put a secret here. Name the env var and where its value lives.

## Push settings

Pushes are personal, so they live outside the repo, in `~/.config/cook/notify.env`:

```sh
NOTIFY=ntfy                      # ntfy | pushover | none
NTFY_TOPIC=cook-3f9a1c7e2b       # a long random topic: anyone who knows it can read your pushes
# NTFY_SERVER=https://ntfy.sh    # or your own server
# NTFY_TOKEN=...                 # for a protected topic
# PUSHOVER_TOKEN=... PUSHOVER_USER=...
```

## Example

See [examples/cook.md](../examples/cook.md).
