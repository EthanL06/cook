## Deploy steps

**Summary:** <one line, for example "1 D1 migration, then the worker, then the web app. No new secrets or flags.">

### Before merge
- [ ] <each step on the test or staging environment, with what it changes>
- [ ] <a check for each step: a query, a request or a screen, and the result to expect>

### Release order
1. <each production step in order, with the reason for the order>

### Rollback
- <for each part: how to undo it, and what data is lost if it is undone>

### Not needed
<the kinds of steps this change does not need: migrations, env vars, secrets, flags, cron, app store build>

<!-- Examples of steps by platform. Delete this block.
Cloudflare: `wrangler d1 migrations apply <db> --remote`, `wrangler secret put <NAME>`, new bindings in wrangler.jsonc.
Supabase: `supabase db push`, edge functions `supabase functions deploy <name>`.
Expo: a native change (app.config, native modules) needs a new EAS build and a store release, not only an OTA update.
Vercel or Netlify: new env vars in the project settings before the deploy. -->
