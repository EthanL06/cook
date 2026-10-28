---
name: verifier-data
description: Verify database migrations, data jobs and scrapers of <project> against a local database - the migration applies cleanly, the schema and data are what the change says, and nothing else is lost. Use for changes to <migrations/**>, models, queries, jobs or scrapers.
---

# verifier-data

Local data only. Never connect to a shared or production database, also not to read.

## Setup

1. Start the local database: <command, for example `pnpm db:start` or "wrangler uses local D1 automatically">.
2. Reset it to the base state: <command, for example `supabase db reset` or delete the local D1 state in `.wrangler/state`>.

## Steps

1. Apply every migration from scratch: <command>. It must finish with no error. Save the log.
2. Check the schema the change says: tables, columns, types, indexes, constraints (<query command, for example `wrangler d1 execute <db> --local --command "PRAGMA table_info(<table>)"`>).
3. With seed or sample data, apply the new migration on top of the previous state and check that existing rows survive with the right values.
4. For jobs and scrapers: run one cycle locally (<command>), then query the rows it wrote. Check the counts and two or three sample rows.
5. When the migration is not reversible, say so in the result, so the deploy steps can warn about it.

## Result

PASS, FAIL or BLOCKED for each claim, with the commands, query outputs and log paths.

## Track record
