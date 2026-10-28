---
base: main                       # PRs go to this branch
tracker: github                  # github | linear | none
# linear_team: ENG               # only for linear
branch: "{type}-{slug}"          # placeholders: {type} {slug} {id} {user}
# branch_max: 34                 # cut the slug to fit, when a tool limits branch length
commit: "{type}: {summary}"      # or: conventional
review: no-mistakes              # no-mistakes | greptile | none
browser: agent-browser           # agent-browser | chrome-devtools-axi | playwright-axi
specs: local                     # local (.lavish/, copy on the issue) | committed (docs/specs/)
notify: on                       # on | off (the service is set per person in ~/.config/cook/notify.env)
commands:
  install: <pnpm install>
  dev: <pnpm dev>                # what verifiers start
  check: <pnpm check>            # the full static check: lint, typecheck, tests
deploy_steps:                    # files in a diff that mean a person must do a step
  - <migrations/**>
verifiers: [<browser>, <api>, <tests>]
---

# <Project name>

<One paragraph: what the apps are, and how they talk to each other.>

## Rules

- <Each rule an agent must follow here, for example "Use local D1 only. Never run wrangler with --remote.">

## Deploy steps

<How each kind of deploy step is done here, or a link to the doc that says it.>
