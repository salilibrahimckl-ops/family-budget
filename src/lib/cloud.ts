// Supabase integration over plain REST (GoTrue auth, PostgREST, Storage).
// Uses only the project URL + public anon key. Row Level Security on the server protects every table.
// Secret keys (service role, AI provider keys) NEVER ship in the app — they live in Supabase Edge Function secrets.
import { getState, update, State, Post, SocialUser } from './store';

const cfg = () => { const s = getState().settings; return { url: s.supabaseUrl.replace(/\/$/, ''), key: s.supabaseAnon }; };
export const cloudReady = () => { const c = cfg(); return !!(c.url && c.key); };

async function call(path: string, init: RequestInit & { auth?: boolean } = {}) {
  const { url, key } = cfg();
  const s = getState();
  const headers: Record<string, string> = { apikey: key, 'Content-Type': 'application/json', ...(init.headers as any) };
  if (init.auth !== false && s.session?.token) headers.Authorization = `Bearer ${s.session.token}`;
  const res = await fetch(url + path, { ...init, headers });
  const text = await res.text();
  let body: any = null; try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  if (!res.ok) throw new Error(body?.msg || body?.message || body?.error_description || body?.error || `Request failed (${res.status})`);
  return body;
}

export async function cloudSignUp(email: string, password: string) {
  const b = await call('/auth/v1/signup', { method: 'POST', auth: false, body: JSON.stringify({ email, password }) });
  if (!b.access_token) return { needsConfirm: true as const, userId: b.id || b.user?.id };
  return { needsConfirm: false as const, ...tok(b) };
}
export async function cloudSignIn(email: string, password: string) {
  return tok(await call('/auth/v1/token?grant_type=password', { method: 'POST', auth: false, body: JSON.stringify({ email, password }) }));
}
export async function cloudRecover(email: string) {
  await call('/auth/v1/recover', { method: 'POST', auth: false, body: JSON.stringify({ email }) });
}
export async function cloudRefresh() {
  const s = getState(); if (!s.session?.refresh) return;
  const b = tok(await call('/auth/v1/token?grant_type=refresh_token', { method: 'POST', auth: false, body: JSON.stringify({ refresh_token: s.session.refresh }) }));
  update((d) => { if (d.session) Object.assign(d.session, { token: b.token, refresh: b.refresh, exp: b.exp }); });
}
function tok(b: any) { return { token: b.access_token as string, refresh: b.refresh_token as string, exp: Date.now() + (b.expires_in || 3600) * 1000, userId: b.user?.id as string, email: b.user?.email as string }; }

export const OAUTH_REDIRECT_APP = 'com.fitverse.app://auth-callback';
export function oauthUrl(provider: 'google' | 'apple') {
  const { url } = cfg();
  const native = !!(window as any).Capacitor?.isNativePlatform?.();
  const redirect = native ? OAUTH_REDIRECT_APP : location.origin + location.pathname;
  return `${url}/auth/v1/authorize?provider=${provider}&redirect_to=${encodeURIComponent(redirect)}`;
}
/** Parse #access_token=… returned by Supabase OAuth. */
export async function consumeOAuthHash(hash: string) {
  const q = new URLSearchParams(hash.replace(/^#/, '').replace(/^.*\?/, ''));
  const token = q.get('access_token'); if (!token) return false;
  const refresh = q.get('refresh_token') || ''; const exp = Date.now() + Number(q.get('expires_in') || 3600) * 1000;
  const { url, key } = cfg();
  const u = await (await fetch(`${url}/auth/v1/user`, { headers: { apikey: key, Authorization: `Bearer ${token}` } })).json();
  update((d) => { d.session = { userId: u.id, email: u.email, mode: 'cloud', token, refresh, exp }; });
  return true;
}

// ─── Sync (local-first: device data is pushed up; cloud feed is pulled down) ───
export async function syncUp() {
  const s = getState(); if (s.session?.mode !== 'cloud' || !s.profile) return;
  if (s.session.exp && s.session.exp < Date.now() + 60e3) await cloudRefresh();
  const uid = s.session.userId; const p = s.profile;
  const up = (table: string, rows: any[], conflict: string) => rows.length ? call(`/rest/v1/${table}?on_conflict=${conflict}`, { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify(rows) }) : null;
  await up('profiles', [{ id: uid, username: p.username, display_name: p.name, bio: p.bio, is_private: p.private, show_stats: p.showStats }], 'id');
  await up('user_profiles', [{ user_id: uid, age: p.age, sex: p.sex, height_cm: p.height, weight_kg: p.weight, target_weight_kg: p.targetWeight, experience: p.experience, activity_level: p.activity, training_days: p.days, session_minutes: p.minutes, goal: p.goal, equipment: p.equipment, diet: p.diet, allergies: p.allergies }], 'user_id');
  await up('weight_history', s.weights.map((w) => ({ user_id: uid, date: w.date, weight_kg: w.kg })), 'user_id,date');
  await up('body_measurements', s.measures.map((m) => ({ user_id: uid, date: m.date, waist_cm: m.waist, hip_cm: m.hip, body_fat_pct: m.bodyFat, muscle_kg: m.muscle, chest_cm: m.chest, arm_cm: m.arm, thigh_cm: m.thigh })), 'user_id,date');
  await up('water_intake_logs', s.water.map((w) => ({ id: w.id, user_id: uid, date: w.date, ml: w.ml, logged_at: new Date(w.ts).toISOString() })), 'id');
  await up('meal_logs', s.meals.map((m) => ({ id: m.id, user_id: uid, date: m.date, meal: m.slot, food_ref: m.foodId, food_name: m.name, grams: m.grams, kcal: m.kcal, protein_g: m.p, carbs_g: m.c, fat_g: m.f, fibre_g: m.fib, is_estimate: m.estimated })), 'id');
  await up('workout_sessions', s.workouts.map((w) => ({ id: w.id, user_id: uid, name: w.name, program_ref: w.programId, started_at: new Date(w.start).toISOString(), ended_at: new Date(w.end).toISOString(), volume_kg: w.volume })), 'id');
  await up('workout_logs', s.workouts.flatMap((w) => w.entries.flatMap((e, ei) => e.sets.map((st, si) => ({ id: `${w.id}-${ei}-${si}`, session_id: w.id, user_id: uid, exercise_ref: e.exId, set_no: si + 1, weight_kg: st.w, reps: st.r, completed: st.done })))), 'id');
}

export async function pullFeed() {
  const s = getState(); if (s.session?.mode !== 'cloud') return;
  const rows: any[] = await call('/rest/v1/social_posts?select=id,user_id,kind,body,created_at,like_count,post_media(storage_path,media_type),profiles(id,username,display_name,bio,is_private)&order=created_at.desc&limit=30');
  const { url } = cfg();
  update((d) => {
    for (const r of rows) {
      const pr = r.profiles; if (pr && !d.social.users.find((u) => u.id === pr.id)) d.social.users.push({ id: pr.id, name: pr.display_name || pr.username, username: pr.username, bio: pr.bio || '', avatarColor: '#8BC34A', private: pr.is_private, sample: false } as SocialUser);
      const post: Post = { id: r.id, userId: r.user_id === s.session!.userId ? s.profile!.userId : r.user_id, ts: Date.parse(r.created_at), kind: r.kind, text: r.body || '', likes: r.like_count || 0, media: (r.post_media || []).map((m: any) => ({ art: `${url}/storage/v1/object/public/post-media/${m.storage_path}`, type: m.media_type })) };
      const i = d.social.posts.findIndex((x) => x.id === r.id);
      if (i >= 0) d.social.posts[i] = post; else d.social.posts.push(post);
    }
    d.social.posts.sort((a, b) => b.ts - a.ts);
  });
}

export async function cloudCreatePost(post: Post, files: { blob: Blob; type: 'image' | 'video' }[]) {
  const s = getState(); const uid = s.session!.userId; const { url, key } = cfg();
  await call('/rest/v1/social_posts', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ id: post.id, user_id: uid, kind: post.kind, body: post.text }) });
  let i = 0;
  for (const f of files) {
    const path = `${uid}/${post.id}-${i++}.${f.type === 'video' ? 'mp4' : 'jpg'}`;
    const r = await fetch(`${url}/storage/v1/object/post-media/${path}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${s.session!.token}`, 'Content-Type': f.blob.type || 'application/octet-stream' }, body: f.blob });
    if (!r.ok) throw new Error('Upload failed');
    await call('/rest/v1/post_media', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ post_id: post.id, user_id: uid, storage_path: path, media_type: f.type }) });
  }
}
export async function cloudLike(postId: string, on: boolean) {
  const uid = getState().session!.userId;
  if (on) await call('/rest/v1/likes', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ post_id: postId, user_id: uid }) });
  else await call(`/rest/v1/likes?post_id=eq.${postId}&user_id=eq.${uid}`, { method: 'DELETE' });
}
export async function cloudComment(id: string, postId: string, text: string, parentId?: string) {
  await call('/rest/v1/comments', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ id, post_id: postId, user_id: getState().session!.userId, body: text, parent_id: parentId || null }) });
}
export async function cloudFollow(target: string, on: boolean) {
  const uid = getState().session!.userId;
  if (on) await call('/rest/v1/followers', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ follower_id: uid, following_id: target }) });
  else await call(`/rest/v1/followers?follower_id=eq.${uid}&following_id=eq.${target}`, { method: 'DELETE' });
}
export async function cloudReport(postId: string, reason: string) {
  await call('/rest/v1/reports', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ post_id: postId, reporter_id: getState().session!.userId, reason }) });
}
export async function cloudDeleteAccount() {
  // Calls the delete-account Edge Function, which uses the service role server-side.
  const { url } = cfg();
  await call('/functions/v1/delete-account', { method: 'POST', body: '{}' });
  void url;
}
export const isCloud = (s: State) => s.session?.mode === 'cloud';
/** Fire-and-forget wrapper so cloud failures never block the on-device action. */
export function bg(p: Promise<any> | null | undefined, onErr?: (e: Error) => void) { p?.catch((e) => { console.warn('[cloud]', e); onErr?.(e); }); }
