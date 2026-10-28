---
name: verifier-api
description: Verify changes to <service name>'s HTTP API with real requests to a local server - status codes, response bodies, auth and error cases. Use for any change under <apps/worker/**> or to a route, handler or middleware.
---

# verifier-api

## Setup

1. Start the server locally with local data only: `<pnpm --filter worker dev --port 8787>` > "$run/api.log" 2>&1 &. Save the PID. Wait for `curl -sf http://localhost:<port><health path>` (at most 60 s).
2. Local bindings and data: <for example "wrangler dev uses local D1 and KV. Apply migrations with `wrangler d1 migrations apply <db> --local`.">. Never use a remote or shared database.
3. Auth for requests: <how to get a local token or session cookie, or "no auth">.

## Steps

For each changed route or behavior:

1. Send the request the claim describes with `curl -sS -D "$run/<name>.headers" -o "$run/<name>.json" -w '%{http_code}\n'`. Save the command too.
2. Check the status code and the fields in the body that the claim names (`jq`). A 2xx with the wrong body is a FAIL.
3. Error cases: missing or bad input (4xx with a clear message), no auth (401 or 403), not found (404). One request each.
4. When the route changes data, read it back with a second request or a local query, and show the before and after.
5. Read `$run/api.log` for errors and stack traces made during the run.

## Teardown

Stop the server PID you started.

## Result

PASS, FAIL or BLOCKED for each claim, with the request, the response files and the log path.

## Track record
