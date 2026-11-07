// Supabase integration over plain REST (GoTrue auth, PostgREST, Storage).
// Uses only the project URL + public anon key. Row Level Security on the server protects every table.
// Secret keys (service role, AI provider keys) NEVER ship in the app — they live in Supabase Edge Function secrets.
import { getState, update, State, Post, SocialUser } from './store';

declare const __FV_CLOUD_URL__: string; declare const __FV_CLOUD_KEY__: string;
/** Project details baked into the build (config/cloud.json); Settings can override them. */
export const BAKED = { url: typeof __FV_CLOUD_URL__ === 'string' ? __FV_CLOUD_URL__ : '', key: typeof __FV_CLOUD_KEY__ === 'string' ? __FV_CLOUD_KEY__ : '' };
const cfg = () => { const s = getState().settings; const url = (s.supabaseUrl || BAKED.url).replace(/\/$/, ''); return { url, key: s.supabaseUrl ? s.supabaseAnon : BAKED.key }; };
export const cloudReady = () => { const c = cfg(); return !!(c.url && c.key); };

let refreshing: Promise<void> | null = null;
async function call(path: string, init: RequestInit & { auth?: boolean } = {}, retried = false): Promise<any> {
  const { url, key } = cfg();
  if (init.auth !== false) { const s0 = getState(); if (s0.session?.mode === 'cloud' && s0.session.refresh && s0.session.exp && s0.session.exp < Date.now() + 60e3) { refreshing = refreshing || cloudRefresh().finally(() => { refreshing = null; }); await refreshing; } }
  if (init.auth !== false) fixSessionUser();
  const s = getState();
  if (init.auth !== false && s.session?.mode === 'cloud' && !s.session.token) throw new Error('Please sign in again (Community → Continue with email).');
  const headers: Record<string, string> = { apikey: key, 'Content-Type': 'application/json', ...(init.headers as any) };
  if (init.auth !== false && s.session?.token) headers.Authorization = `Bearer ${s.session.token}`;
  const res = await fetch(url + path, { ...init, headers });
  const text = await res.text();
  let body: any = null; try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  if (!res.ok) {
    const msg = body?.msg || body?.message || body?.error_description || body?.error || `Request failed (${res.status})`;
    // Expired sign-in: renew it quietly and try once more.
    if (!retried && init.auth !== false && s.session?.refresh && (res.status === 401 || /jwt expired|invalid jwt|token is expired/i.test(String(msg)))) {
      refreshing = refreshing || cloudRefresh().finally(() => { refreshing = null; });
      await refreshing;
      return call(path, init, true);
    }
    throw new Error(msg);
  }
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
  let raw: any;
  try { raw = await call('/auth/v1/token?grant_type=refresh_token', { method: 'POST', auth: false, body: JSON.stringify({ refresh_token: s.session.refresh }) }); }
  catch (e: any) {
    if (/invalid refresh|refresh token|not found|revoked/i.test(e.message)) { signOutCloud(); throw new Error('Your sign-in ended — please sign in again in Community.'); }
    throw e;
  }
  const b = tok(raw);
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
  applySession({ token, refresh, exp, userId: u.id, email: u.email }, u.user_metadata);
  return true;
}

// ─── One sign-in for everything: Google, or just your email (6-digit code / magic link) ───
export function redirectTarget() {
  const native = !!(window as any).Capacitor?.isNativePlatform?.();
  return native ? OAUTH_REDIRECT_APP : location.origin + location.pathname;
}
export async function sendEmailCode(email: string) {
  await call('/auth/v1/otp?redirect_to=' + encodeURIComponent(redirectTarget()), { method: 'POST', auth: false, body: JSON.stringify({ email, create_user: true }) });
}
export async function verifyEmailCode(email: string, code: string) {
  const b = await call('/auth/v1/verify', { method: 'POST', auth: false, body: JSON.stringify({ type: 'email', email, token: code.trim() }) });
  const t = tok(b); applySession(t, b.user?.user_metadata);
}
/** Switch the app to the signed-in cloud account. Local data (workouts, meals, profile) is kept. */
export function applySession(t: { token: string; refresh: string; exp: number; userId: string; email: string }, meta?: any) {
  update((d) => {
    const guest = !d.session || d.session.email === 'guest' || d.session.mode === 'local';
    // Linking this phone's existing profile to the account: move "me" to the account id everywhere.
    const old = d.profile?.userId;
    if (d.profile && old && old !== t.userId && (guest || d.session?.userId === old)) {
      d.social = JSON.parse(JSON.stringify(d.social).split(old).join(t.userId));
      d.profile.userId = t.userId;
    }
    d.session = { userId: t.userId, email: t.email, mode: 'cloud', token: t.token, refresh: t.refresh, exp: t.exp };
    if (!d.accounts.find((a) => a.userId === t.userId)) d.accounts.push({ email: t.email, salt: '', hash: '', userId: t.userId });
    const nm = meta?.full_name || meta?.name;
    if (d.profile && nm && guest && (!d.profile.name || /^(friend|guest|you)$/i.test(d.profile.name))) d.profile.name = nm;
    if (meta?.avatar_url) (d.settings as any).photo = meta.avatar_url;
  });
  setTimeout(() => { bg(ensureProfile().then(() => pullFeed())); }, 50);
}
export function signOutCloud() { update((d) => { if (d.session) d.session = { userId: d.session.userId, email: 'guest', mode: 'local' }; }); }
/** Which sign-in providers are switched on in the server (public endpoint). Cached per session. */
let provP: Promise<{ google: boolean }> | null = null;
export function providers() {
  if (!provP) provP = (async () => { try { const { url, key } = cfg(); const r = await fetch(url + '/auth/v1/settings', { headers: { apikey: key } }); const j = await r.json(); return { google: !!j?.external?.google }; } catch { provP = null; return { google: false }; } })();
  return provP;
}
export const OWNER_EMAILS = ['salilibrahimckl@gmail.com'];
const slug = (x: string) => x.toLowerCase().replace(/[^a-z0-9_.]/g, '').slice(0, 16) || 'athlete';
/** Make sure this account has a public community profile (unique username). */
export async function ensureProfile() {
  const s = getState(); if (!isCloud(s) || !s.profile) return;
  const uid = s.session!.userId;
  const have = await call(`/rest/v1/profiles?id=eq.${uid}&select=id,username,is_admin`);
  // Developer tools: only the app owner (or accounts marked is_admin on the server).
  const owner = OWNER_EMAILS.includes((s.session!.email || '').toLowerCase()) || !!have?.[0]?.is_admin;
  if (owner !== !!s.settings.admin && (owner || s.settings.admin)) update((d) => { d.settings.admin = owner || d.settings.admin; });
  if (have?.length) { if (have[0].username !== s.profile.username) update((d) => { if (d.profile) d.profile.username = have[0].username; }); return; }
  let base = slug(s.profile.username || s.profile.name || s.session!.email.split('@')[0]);
  if (base.length < 2) base = 'athlete';
  for (let i = 0; i < 5; i++) {
    const username = i === 0 ? base : (base.slice(0, 14) + Math.floor(Math.random() * 900 + 100));
    try {
      await call('/rest/v1/profiles', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ id: uid, username, display_name: s.profile.name, bio: s.profile.bio || '', is_private: !!s.profile.private, avatar_path: (s.settings as any).photo || null }) });
      update((d) => { if (d.profile) d.profile.username = username; });
      return;
    } catch (e: any) { if (!/duplicate|unique|23505/i.test(e.message)) throw e; }
  }
}

// ─── People ───
const toUser = (pr: any): SocialUser => ({ id: pr.id, name: pr.display_name || pr.username, username: pr.username, bio: pr.bio || '', avatarColor: '#8BC34A', private: !!pr.is_private, sample: false, photo: pr.avatar_path || undefined } as SocialUser);
function remember(rows: any[]) {
  if (!rows?.length) return;
  update((d) => { for (const pr of rows) { const u = toUser(pr); const i = d.social.users.findIndex((x) => x.id === u.id); if (i >= 0) d.social.users[i] = { ...d.social.users[i], ...u }; else d.social.users.push(u); } });
}
export async function searchPeople(q: string) {
  const s = getState(); if (!isCloud(s)) return [];
  const t = q.replace(/[^a-zA-Z0-9_. ]/g, '').trim();
  const filter = t ? `&or=(username.ilike.*${encodeURIComponent(t)}*,display_name.ilike.*${encodeURIComponent(t)}*)` : '&order=created_at.desc';
  const rows = await call(`/rest/v1/profiles?select=id,username,display_name,bio,is_private,avatar_path${filter}&limit=30`);
  const mine = s.session!.userId; const list = (rows || []).filter((r: any) => r.id !== mine);
  remember(list); return list.map(toUser);
}
async function loadProfiles(ids: string[]) {
  const s = getState(); const need = [...new Set(ids)].filter((id) => id !== s.session?.userId && !s.social.users.find((u) => u.id === id && !u.sample));
  if (!need.length) return;
  remember(await call(`/rest/v1/profiles?select=id,username,display_name,bio,is_private,avatar_path&id=in.(${need.join(',')})`));
}

// ─── Direct messages (polling; no extra servers needed) ───
export interface Msg { id: string; from: string; to: string; text: string; ts: number; read: boolean }
const toMsg = (r: any): Msg => ({ id: r.id, from: r.sender_id, to: r.recipient_id, text: r.body, ts: Date.parse(r.created_at), read: !!r.read_at });
export async function inbox(): Promise<{ other: string; last: Msg; unread: number }[]> {
  const s = getState(); if (!isCloud(s)) return [];
  const me = s.session!.userId;
  const rows: any[] = await call(`/rest/v1/messages?select=id,sender_id,recipient_id,body,created_at,read_at&or=(sender_id.eq.${me},recipient_id.eq.${me})&order=created_at.desc&limit=300`);
  const map = new Map<string, { other: string; last: Msg; unread: number }>();
  for (const r of rows) {
    const m = toMsg(r); const other = m.from === me ? m.to : m.from;
    const c = map.get(other) || { other, last: m, unread: 0 };
    if (m.to === me && !m.read) c.unread++;
    map.set(other, c);
  }
  await loadProfiles([...map.keys()]);
  return [...map.values()];
}
export async function thread(other: string): Promise<Msg[]> {
  const me = getState().session!.userId;
  const rows: any[] = await call(`/rest/v1/messages?select=id,sender_id,recipient_id,body,created_at,read_at&or=(and(sender_id.eq.${me},recipient_id.eq.${other}),and(sender_id.eq.${other},recipient_id.eq.${me}))&order=created_at.desc&limit=200`);
  await loadProfiles([other]);
  return rows.map(toMsg).reverse();
}
export async function sendMessage(other: string, text: string) {
  const me = getState().session!.userId;
  const r = await call('/rest/v1/messages', { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ sender_id: me, recipient_id: other, body: text.slice(0, 2000) }) });
  return toMsg(Array.isArray(r) ? r[0] : r);
}
export async function markRead(other: string) {
  const me = getState().session!.userId;
  await call(`/rest/v1/messages?recipient_id=eq.${me}&sender_id=eq.${other}&read_at=is.null`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ read_at: new Date().toISOString() }) });
}
export async function unreadMessages(): Promise<number> {
  const s = getState(); if (!isCloud(s)) return 0;
  const rows: any[] = await call(`/rest/v1/messages?select=id&recipient_id=eq.${s.session!.userId}&read_at=is.null&limit=99`);
  return rows.length;
}
/** Map a cloud user id to the id used for "me" in local state. */
export const localId = (s: State, id: string) => (id === s.session?.userId ? s.profile!.userId : id);

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
  const rows: any[] = await call('/rest/v1/social_posts?select=id,user_id,kind,body,created_at,like_count,post_media(storage_path,media_type),comments(id,user_id,body,created_at,parent_id)&order=created_at.desc&limit=40');
  // posts link to auth users, not profiles, so fetch the authors separately
  const authorIds = [...new Set(rows.map((r: any) => r.user_id).concat(rows.flatMap((r: any) => (r.comments || []).map((c: any) => c.user_id))))].filter((id) => id !== s.session!.userId);
  const authors: any[] = authorIds.length ? await call(`/rest/v1/profiles?select=id,username,display_name,bio,is_private,avatar_path&id=in.(${authorIds.join(',')})`) : [];
  const byId = new Map(authors.map((a) => [a.id, a]));
  const { url } = cfg();
  update((d) => {
    for (const r of rows) {
      const pr = byId.get(r.user_id); if (pr) { const u = toUser(pr); const k = d.social.users.findIndex((x) => x.id === u.id); if (k >= 0) d.social.users[k] = { ...d.social.users[k], ...u }; else d.social.users.push(u); }
      for (const c of r.comments || []) { const cp = byId.get(c.user_id); if (cp && !d.social.users.find((x) => x.id === cp.id)) d.social.users.push(toUser(cp)); if (!d.social.comments.find((x) => x.id === c.id)) d.social.comments.push({ id: c.id, postId: r.id, userId: localId(s, c.user_id), text: c.body, ts: Date.parse(c.created_at), parentId: c.parent_id || undefined }); }
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
/** The account id inside the sign-in token (the server trusts only this). */
function jwtSub(token?: string): string | null {
  try { const p = token!.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'); return JSON.parse(decodeURIComponent(escape(atob(p + '==='.slice((p.length + 3) % 4))))).sub || null; } catch { return null; }
}
/** If the saved account id doesn't match the sign-in token (e.g. after signing in with another email), fix it everywhere. */
function fixSessionUser() {
  const s = getState(); if (s.session?.mode !== 'cloud' || !s.session.token) return;
  const sub = jwtSub(s.session.token); if (!sub || (sub === s.session.userId && (!s.profile || s.profile.userId === sub))) return;
  const old = s.session.userId;
  update((d) => {
    d.session!.userId = sub;
    if (d.profile) {
      let j = JSON.stringify(d.social); for (const id of [old, d.profile.userId]) if (id && id !== sub) j = j.split(id).join(sub);
      d.social = JSON.parse(j); d.profile.userId = sub;
    }
  });
}
/** Fire-and-forget wrapper so cloud failures never block the on-device action. */
export function bg(p: Promise<any> | null | undefined, onErr?: (e: Error) => void) { p?.catch((e) => { console.warn('[cloud]', e); onErr?.(e); }); }

// ─── Friends leaderboard (public weekly totals only — no weight, meals or body data) ───
export interface Board { userId: string; kcal: number; minutes: number; workouts: number; streak: number; updated: number }
export const statsSync: { at: number; err: string } = { at: 0, err: '' };
export async function pushStats(st: { week: string; kcal: number; minutes: number; workouts: number; streak: number }) {
  const s = getState(); if (!isCloud(s) || !s.profile) return;
  try { await pushStatsRaw(s, st); statsSync.at = Date.now(); statsSync.err = ''; } catch (e: any) { statsSync.err = e.message || String(e); throw e; }
}
async function pushStatsRaw(s: State, st: { week: string; kcal: number; minutes: number; workouts: number; streak: number }) {
  if (s.profile.leaderboard === false) { await call(`/rest/v1/weekly_stats?user_id=eq.${s.session!.userId}`, { method: 'DELETE' }).catch(() => undefined); return; }
  await call('/rest/v1/weekly_stats?on_conflict=user_id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify({ user_id: s.session!.userId, week: st.week, kcal: st.kcal, active_min: st.minutes, workouts: st.workouts, streak: st.streak, updated_at: new Date().toISOString() }) });
}
export async function leaderboard(week: string): Promise<Board[]> {
  const s = getState(); if (!isCloud(s)) return [];
  const rows: any[] = await call(`/rest/v1/weekly_stats?select=user_id,kcal,active_min,workouts,streak,updated_at&week=eq.${week}&order=kcal.desc&limit=50`);
  await loadProfiles(rows.map((r) => r.user_id));
  // Members who haven't logged anything this week still appear (with 0), so friends show up straight away.
  let members: any[] = [];
  try { members = await call('/rest/v1/profiles?select=id,username,display_name,bio,is_private,avatar_path&order=created_at.desc&limit=50'); remember(members.filter((m) => m.id !== s.session!.userId)); } catch { /* */ }
  for (const m of members) if (!rows.find((r) => r.user_id === m.id)) rows.push({ user_id: m.id, kcal: 0, active_min: 0, workouts: 0, streak: 0, updated_at: new Date(0).toISOString() });
  return rows.map((r) => ({ userId: localId(getState(), r.user_id), kcal: r.kcal, minutes: r.active_min, workouts: r.workouts, streak: r.streak, updated: Date.parse(r.updated_at) }));
}

// ─── Account changes ───
export async function changePassword(pw: string) {
  if (pw.length < 6) throw new Error('Use at least 6 characters.');
  await call('/auth/v1/user', { method: 'PUT', body: JSON.stringify({ password: pw }) });
}
/** Change the public @username (must be unique across the community). */
export async function changeUsername(name: string) {
  const u = name.trim().toLowerCase().replace(/^@/, '');
  if (!/^[a-z0-9_.]{3,20}$/.test(u)) throw new Error('3–20 letters, numbers, _ or . only.');
  const s = getState();
  if (isCloud(s)) {
    const me = s.session!.userId;
    const taken: any[] = await call(`/rest/v1/profiles?select=id&username=eq.${encodeURIComponent(u)}`);
    if (taken.some((r) => r.id !== me)) throw new Error('@' + u + ' is already taken.');
    try { await call(`/rest/v1/profiles?id=eq.${me}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ username: u }) }); }
    catch (e: any) { if (/duplicate|unique|23505/i.test(e.message)) throw new Error('@' + u + ' is already taken.'); throw e; }
  }
  update((d) => { if (d.profile) d.profile.username = u; });
  return u;
}

// ─── Friend challenges ───
export type Metric = 'kcal' | 'minutes' | 'sessions';
export interface FChallenge { id: string; creator: string; title: string; metric: Metric; start: string; end: string; members: { userId: string; status: 'invited' | 'accepted' | 'declined'; progress: number; updated: number }[] }
export async function createFriendChallenge(o: { title: string; metric: Metric; start: string; end: string; friends: string[] }) {
  const s = getState(); const me = s.session!.userId;
  const r = await call('/rest/v1/friend_challenges', { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ creator_id: me, title: o.title, metric: o.metric, starts_on: o.start, ends_on: o.end }) });
  const ch = Array.isArray(r) ? r[0] : r;
  await call('/rest/v1/challenge_members', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify([{ challenge_id: ch.id, user_id: me, status: 'accepted' }, ...o.friends.map((f) => ({ challenge_id: ch.id, user_id: f, status: 'invited' }))]) });
  return ch.id as string;
}
export async function myFriendChallenges(): Promise<FChallenge[]> {
  const s = getState(); if (!isCloud(s)) return [];
  const me = s.session!.userId;
  const mine: any[] = await call(`/rest/v1/challenge_members?select=challenge_id,friend_challenges(id,creator_id,title,metric,starts_on,ends_on)&user_id=eq.${me}&status=neq.declined`);
  const ids = mine.map((m) => m.challenge_id); if (!ids.length) return [];
  const all: any[] = await call(`/rest/v1/challenge_members?select=challenge_id,user_id,status,progress,updated_at&challenge_id=in.(${ids.join(',')})`);
  await loadProfiles(all.map((m) => m.user_id));
  const st = getState();
  return mine.filter((m) => m.friend_challenges).map((m) => { const c = m.friend_challenges; return {
    id: c.id, creator: localId(st, c.creator_id), title: c.title, metric: c.metric, start: c.starts_on, end: c.ends_on,
    members: all.filter((x) => x.challenge_id === c.id).map((x) => ({ userId: localId(st, x.user_id), status: x.status, progress: x.progress, updated: Date.parse(x.updated_at) })),
  }; }).sort((a, b) => b.end.localeCompare(a.end));
}
export async function respondChallenge(id: string, status: 'accepted' | 'declined') {
  const me = getState().session!.userId;
  await call(`/rest/v1/challenge_members?challenge_id=eq.${id}&user_id=eq.${me}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ status, updated_at: new Date().toISOString() }) });
}
export async function pushChallengeProgress(id: string, progress: number) {
  const me = getState().session!.userId;
  await call(`/rest/v1/challenge_members?challenge_id=eq.${id}&user_id=eq.${me}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ progress: Math.max(0, Math.round(progress)), updated_at: new Date().toISOString() }) });
}
export async function deleteFriendChallenge(id: string) { await call(`/rest/v1/friend_challenges?id=eq.${id}`, { method: 'DELETE' }); }
