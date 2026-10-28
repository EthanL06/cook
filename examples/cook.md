---
base: main
tracker: github
branch: "{type}-{slug}"
commit: "{type}: {summary}"
review: no-mistakes
browser: agent-browser
specs: local
commands:
  install: pnpm install
  dev: pnpm dev                  # web on :3000, worker on :8787
  test: pnpm --filter worker test
  lint: pnpm --filter web lint
deploy_steps:
  - apps/worker/drizzle/**       # D1 migrations
  - apps/worker/wrangler.jsonc   # bindings and vars
verifiers: [browser, design, api, data, tests]
---

# Example app

A Next.js web app (`apps/web`) that talks to a Cloudflare Worker API (`apps/worker`: Hono, D1 through Drizzle, KV for sessions, Workers AI). The web app calls the worker on `http://localhost:8787` in development.

## Rules

- Use local D1 and KV only (`wrangler dev`). Never run a wrangler command with `--remote`.
- Never run `scripts/clear-data.sh` against a remote binding.
- Generate migrations with `drizzle-kit generate`. Never edit a migration that is on `main`.

## Deploy steps

- D1 migration: `wrangler d1 migrations apply app-db --remote`, before the worker deploy.
- New secret: `wrangler secret put <NAME>`, before the worker deploy.
- Worker: `pnpm --filter worker deploy`. Web: the host deploys `main`.
