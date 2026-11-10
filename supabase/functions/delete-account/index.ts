// Deletes the calling user's account. All personal rows cascade from auth.users.
// Deploy: supabase functions deploy delete-account
// The service-role key is provided by Supabase to the function's environment; it never ships in the app.
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const auth = req.headers.get("Authorization");
  if (!auth) return new Response("Unauthorized", { status: 401 });

  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) return new Response("Unauthorized", { status: 401 });

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  // Remove uploaded recordings first (storage objects do not cascade).
  const { data: files } = await admin.storage.from("recordings").list(user.id);
  if (files?.length) {
    await admin.storage.from("recordings").remove(files.map((f) => `${user.id}/${f.name}`));
  }
  const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
  if (delErr) return new Response(delErr.message, { status: 500 });
  return Response.json({ deleted: true });
});
