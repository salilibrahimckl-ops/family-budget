// Returns all of the calling user's data as JSON (data-portability request).
// Runs with the user's own token, so row-level security limits it to their rows.
import { createClient } from "jsr:@supabase/supabase-js@2";

const TABLES = [
  "profiles", "learning_preferences", "memorisation_records", "word_weakness", "learning_sessions",
  "recitation_attempts", "detected_mistakes", "xp_transactions", "streak_days", "tajweed_progress",
  "user_achievements", "daily_challenges", "subscriptions", "teacher_students",
];

Deno.serve(async (req) => {
  const auth = req.headers.get("Authorization");
  if (!auth) return new Response("Unauthorized", { status: 401 });
  const c = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: { user } } = await c.auth.getUser();
  if (!user) return new Response("Unauthorized", { status: 401 });
  const out: Record<string, unknown> = { exported_at: new Date().toISOString(), user_id: user.id, email: user.email };
  for (const t of TABLES) {
    const { data, error } = await c.from(t).select("*");
    out[t] = error ? { error: error.message } : data;
  }
  return new Response(JSON.stringify(out, null, 2), {
    headers: { "Content-Type": "application/json", "Content-Disposition": "attachment; filename=hifz-export.json" },
  });
});
