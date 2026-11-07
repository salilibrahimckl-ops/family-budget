# Turn on the shared community + chat (one-time, ~15 minutes, free)

Bro’s Fitness uses one sign-in for everything (Google or email code). Posts, comments and chats live in a free
Supabase project that you own. Do this once; after that nobody pastes anything — the details are built into the app.

1. **Create the project** — supabase.com → New project (Free plan). Pick a region near you (e.g. Mumbai).
2. **Create the tables** — SQL Editor → New query → paste all of `supabase/schema.sql` → Run.
3. **Email sign-in with a code** — Authentication → Emails → Templates. In both **Magic Link** and **Confirm signup**
   add this line to the message: `<h2>Your Bro’s Fitness code: {{ .Token }}</h2>` → Save.
   (The free built-in mailer sends only a few emails per hour — fine for family use.)
4. **Allow the app to come back after sign-in** — Authentication → URL Configuration:
   - Site URL: `https://salilibrahimckl-ops.github.io/family-budget/fitness/`
   - Redirect URLs: add `com.fitverse.app://auth-callback` and `https://salilibrahimckl-ops.github.io/family-budget/fitness/`
5. **Google button** (optional but nicest):
   - console.cloud.google.com → APIs & Services → OAuth consent screen → External → app name “Bro’s Fitness”.
   - Credentials → Create credentials → OAuth client ID → *Web application* →
     Authorized redirect URI: `https://YOUR-PROJECT.supabase.co/auth/v1/callback` → Create.
   - Supabase → Authentication → Sign In / Providers → Google → enable → paste the Client ID and Client secret → Save.
6. **Send the two public values** — Project Settings → API (or “Data API”): copy the **Project URL** and the
   **anon public** key. Put them in `config/cloud.json` (or send them to Claude to do it). Never share the
   `service_role` key — it doesn’t go in the app.

The next build then reaches both phones through the Update button (Android) and the web link (iPhone).

**iPhone:** open `https://salilibrahimckl-ops.github.io/family-budget/fitness/` in Safari → Share → *Add to Home Screen*.
The claude.ai preview can’t connect to servers, so use that link for community and chat.

Notes: free Supabase projects pause after a week with no activity — open the dashboard and press *Restore* if that happens.
