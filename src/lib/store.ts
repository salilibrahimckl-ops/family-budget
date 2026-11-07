// Global app state with persistence (localStorage) and media blobs (IndexedDB).
import { useSyncExternalStore } from 'react';
import type { Activity, Goal, Sex } from './calc';
import type { Equip, Exercise } from '../data/exercises';
import type { Food } from '../data/foods';
import { seedSocial } from './seed';

export type MealSlot = 'breakfast' | 'lunch' | 'dinner' | 'snacks';
export interface Profile {
  userId: string; name: string; username: string; age: number; sex: Sex; height: number; weight: number; targetWeight: number;
  experience: 'beginner' | 'intermediate' | 'advanced'; activity: Activity; days: number; minutes: number; goal: Goal; equipment: Equip;
  diet: 'nonveg' | 'eggetarian' | 'vegetarian' | 'vegan' | 'pescatarian'; allergies: string[]; photos: string[]; bio: string;
  avatar?: string; private: boolean; showStats: boolean; leaderboard: boolean; createdAt: number;
}
export interface MealEntry { id: string; date: string; slot: MealSlot; foodId: string; name: string; grams: number; unit: string; kcal: number; p: number; c: number; f: number; fib: number; estimated: boolean }
export interface SetLog { w: number; r: number; done: boolean }
export interface WorkoutLog { id: string; date: string; start: number; end: number; name: string; programId?: string; entries: { exId: string; sets: SetLog[] }[]; volume: number; prs: string[] }
export interface SocialUser { id: string; name: string; username: string; bio: string; avatarColor: string; private: boolean; sample: boolean; creator?: boolean; suspended?: boolean }
export interface Post {
  id: string; userId: string; ts: number; kind: 'photo' | 'video' | 'workout' | 'transformation' | 'achievement' | 'tip' | 'text' | 'challenge';
  text: string; media: { id?: string; art?: string; type: 'image' | 'video' }[]; workout?: { name: string; volume: number; minutes: number; exercises: number };
  likes: number; removed?: boolean;
}
export interface Comment { id: string; postId: string; userId: string; text: string; ts: number; parentId?: string }
export interface Notif { id: string; ts: number; type: 'like' | 'comment' | 'follow' | 'request' | 'mention' | 'achievement' | 'challenge' | 'system'; text: string; read: boolean; fromId?: string; postId?: string }

export interface State {
  v: 1;
  accounts: { email: string; salt: string; hash: string; userId: string }[];
  session: { userId: string; email: string; mode: 'local' | 'cloud'; token?: string; refresh?: string; exp?: number } | null;
  profile: Profile | null;
  settings: {
    theme: 'dark' | 'light'; units: 'metric' | 'imperial'; asianBmi: boolean; hotClimate: boolean; lang: 'en' | 'ml';
    reminders: { water: boolean; every: number; from: number; to: number; workout: boolean };
    supabaseUrl: string; supabaseAnon: string; admin: boolean; plan: 'free' | 'premium'; seenIntro: boolean; hideChecklist?: boolean; watchedDemo?: boolean;
    notify?: { meals: boolean; times: [string, string, string]; workout: boolean; workoutTime: string; nudges: boolean; asked?: boolean };
  };
  custom: { kcal?: number; protein?: number; water?: number };
  weights: { date: string; kg: number }[];
  measures: { date: string; waist?: number; hip?: number; bodyFat?: number; muscle?: number; chest?: number; arm?: number; thigh?: number }[];
  meals: MealEntry[];
  favourites: { id: string; name: string; items: { foodId: string; grams: number }[] }[];
  customFoods: Food[];
  water: { id: string; date: string; ts: number; ml: number }[];
  plan: { programId: string; schedule: (number | null)[] } | null;
  routines: { id: string; name: string; items: { id: string; sets: number; reps: string }[] }[];
  workouts: WorkoutLog[];
  active: { name: string; programId?: string; start: number; entries: { exId: string; sets: SetLog[] }[]; home: boolean } | null;
  prs: Record<string, { w: number; r: number; e1rm: number; date: string }>;
  social: { users: SocialUser[]; posts: Post[]; comments: Comment[]; follows: { from: string; to: string; status: 'accepted' | 'pending' }[]; likes: { postId: string; userId: string }[]; bookmarks: string[]; blocks: string[]; reports: { id: string; postId: string; reason: string; ts: number; status: 'open' | 'removed' | 'dismissed' }[] };
  notifications: Notif[];
  challenges: Record<string, { joined: number; log: Record<string, number> }>;
  customChallenges: { id: string; name: string; desc: string; days: number; unit: string; target: number; emoji: string }[];
  achievements: Record<string, number>;
  exOverrides: Record<string, Partial<Exercise>>;
  extraExercises: Exercise[];
  foodOverrides: Record<string, Partial<Food>>;
  coach: { role: 'user' | 'coach'; text: string; ts: number }[];
  steps: Record<string, number>;
}

const KEY = 'fitverse.v1';
export const uid = () => Math.random().toString(36).slice(2, 10) + Date.now().toString(36).slice(-4);
export const today = (d = new Date()) => { const z = new Date(d.getTime() - d.getTimezoneOffset() * 60000); return z.toISOString().slice(0, 10); };
export const dayOffset = (n: number) => { const d = new Date(); d.setDate(d.getDate() + n); return today(d); };

function initial(): State {
  return {
    v: 1, accounts: [], session: null, profile: null,
    settings: { theme: 'dark', units: 'metric', asianBmi: true, hotClimate: true, lang: 'en', reminders: { water: false, every: 90, from: 8, to: 21, workout: false }, supabaseUrl: '', supabaseAnon: '', admin: false, plan: 'free', seenIntro: false },
    custom: {}, weights: [], measures: [], meals: [], favourites: [], customFoods: [], water: [], plan: null, routines: [], workouts: [], active: null, prs: {},
    social: { ...seedSocial(), follows: [], likes: [], bookmarks: [], blocks: [], reports: [] },
    notifications: [], challenges: {}, customChallenges: [], achievements: {}, exOverrides: {}, extraExercises: [], foodOverrides: {}, coach: [], steps: {},
  };
}

function load(): State {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) { const s = JSON.parse(raw); return { ...initial(), ...s, settings: { ...initial().settings, ...s.settings } }; }
  } catch { /* storage unavailable */ }
  return initial();
}

let state: State = load();
const subs = new Set<() => void>();
let saveTimer: any;
function persist() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => { try { localStorage.setItem(KEY, JSON.stringify(state)); } catch { /* quota / private mode */ } }, 250);
}
export const getState = () => state;
export function update(fn: (draft: State) => void) {
  const draft = structuredClone(state);
  fn(draft);
  state = draft;
  persist();
  subs.forEach((s) => s());
}
export const subscribe = (f: () => void) => { subs.add(f); return () => { subs.delete(f); }; };
export function useStore<T>(sel: (s: State) => T): T {
  return useSyncExternalStore((cb) => { subs.add(cb); return () => subs.delete(cb); }, () => sel(state));
}
export function resetAll() { try { localStorage.removeItem(KEY); } catch { /* */ } state = initial(); subs.forEach((s) => s()); }
export function exportData() {
  const { accounts, session, ...rest } = state;
  return JSON.stringify({ exportedAt: new Date().toISOString(), app: 'Bro’s Fitness', data: rest }, null, 2);
}

export function notify(d: State, n: Omit<Notif, 'id' | 'ts' | 'read'>) {
  d.notifications.unshift({ id: uid(), ts: Date.now(), read: false, ...n });
  d.notifications = d.notifications.slice(0, 200);
}

// ─── Media (IndexedDB) ───
let dbp: Promise<IDBDatabase> | null = null;
const mem = new Map<string, Blob>();
function db(): Promise<IDBDatabase> {
  if (!dbp) dbp = new Promise((res, rej) => {
    try { const r = indexedDB.open('fitverse-media', 1); r.onupgradeneeded = () => r.result.createObjectStore('m'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); } catch (e) { rej(e); }
  });
  return dbp;
}
export async function putMedia(blob: Blob): Promise<string> {
  const id = uid();
  try { const d = await db(); await new Promise<void>((res, rej) => { const t = d.transaction('m', 'readwrite'); t.objectStore('m').put(blob, id); t.oncomplete = () => res(); t.onerror = () => rej(t.error); }); }
  catch { mem.set(id, blob); }
  return id;
}
export async function getMedia(id: string): Promise<Blob | null> {
  if (mem.has(id)) return mem.get(id)!;
  try { const d = await db(); return await new Promise((res) => { const r = d.transaction('m').objectStore('m').get(id); r.onsuccess = () => res(r.result || null); r.onerror = () => res(null); }); }
  catch { return null; }
}
export async function delMedia(id: string) { mem.delete(id); try { const d = await db(); d.transaction('m', 'readwrite').objectStore('m').delete(id); } catch { /* */ } }

/** Validate + compress an image to max 1440px JPEG. */
export async function processImage(file: File): Promise<Blob> {
  if (!/^image\/(jpeg|png|webp|heic|heif|gif)$/.test(file.type)) throw new Error('Unsupported image type. Use JPG, PNG or WebP.');
  if (file.size > 15 * 1024 * 1024) throw new Error('Image is larger than 15 MB.');
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error('Could not read the image.')); i.src = url; });
    const max = 1440; const sc = Math.min(1, max / Math.max(img.width, img.height));
    const c = document.createElement('canvas'); c.width = Math.round(img.width * sc); c.height = Math.round(img.height * sc);
    c.getContext('2d')!.drawImage(img, 0, 0, c.width, c.height);
    return await new Promise((res) => c.toBlob((b) => res(b!), 'image/jpeg', 0.82));
  } finally { URL.revokeObjectURL(url); }
}
export function validateVideo(file: File) {
  if (!/^video\/(mp4|quicktime|webm|3gpp)$/.test(file.type)) throw new Error('Unsupported video type. Use MP4, MOV or WebM.');
  if (file.size > 60 * 1024 * 1024) throw new Error('Video is larger than 60 MB. Trim it or record at a lower resolution.');
  return file;
}

// ─── Auth (on-device accounts; Supabase auth when configured — see lib/cloud.ts) ───
async function sha(s: string) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}
export async function hashPw(pw: string, salt: string) { let h = pw; for (let i = 0; i < 2000; i++) h = await sha(salt + h); return h; }
