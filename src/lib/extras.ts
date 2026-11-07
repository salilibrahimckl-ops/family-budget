// Challenges, achievements, i18n and native helpers.
import { State, today, dayOffset, notify, update, getState } from './store';
import { dayTotals, userTargets } from './coach';

export interface Challenge { id: string; name: string; desc: string; days: number; unit: string; emoji: string; auto?: 'water' | 'workout' | 'steps'; targetFor: (day: number) => number; weekly?: boolean }
export const CHALLENGES: Challenge[] = [
  { id: 'pushup30', name: '30-Day Push-Up Challenge', emoji: '💪', days: 30, unit: 'reps', desc: 'Start at 10 push-ups and add one each day. Knee or incline push-ups count — keep a straight body line.', targetFor: (d) => 10 + d },
  { id: 'plank30', name: '30-Day Plank Challenge', emoji: '🧱', days: 30, unit: 'seconds', desc: 'Begin with 20 s and add 5 s per day. Total time may be split into sets.', targetFor: (d) => 20 + d * 5 },
  { id: 'steps10k', name: 'Daily 10,000 Steps', emoji: '👟', days: 30, unit: 'steps', auto: 'steps', desc: 'Walk 10,000 steps a day for 30 days. Enter your steps from your phone\'s step counter.', targetFor: () => 10000 },
  { id: 'transform30', name: '30-Day Transformation', emoji: '🔄', days: 30, unit: 'check-in', desc: 'Train, hit your protein and log daily. Take progress photos on day 1 and day 30 (kept private unless you share).', targetFor: () => 1 },
  { id: 'gymweek', name: 'Weekly Gym Consistency', emoji: '📅', days: 28, unit: 'workouts', auto: 'workout', weekly: true, desc: 'Complete at least 4 logged workouts each week for 4 weeks. Counts automatically from your workout log.', targetFor: () => 4 },
  { id: 'hydrate14', name: '14-Day Hydration Streak', emoji: '💧', days: 14, unit: 'ml', auto: 'water', desc: 'Hit your daily water target 14 days in a row. Counts automatically from your water log.', targetFor: () => 0 },
];

export function challengeProgress(s: State, c: Challenge) {
  const j = s.challenges[c.id]; if (!j) return null;
  const start = new Date(j.joined); start.setHours(0, 0, 0, 0);
  const dayIdx = Math.floor((Date.now() - start.getTime()) / 864e5);
  let done = 0;
  const waterT = s.profile ? userTargets(s).water : 2500;
  for (let i = 0; i <= Math.min(dayIdx, c.days - 1); i++) {
    const d = new Date(start); d.setDate(d.getDate() + i); const key = today(d);
    if (c.auto === 'water') { if (dayTotals(s, key).water >= waterT) done++; }
    else if (c.auto === 'steps') { if ((s.steps[key] || j.log[key] || 0) >= c.targetFor(i)) done++; }
    else if (c.auto === 'workout') { /* weekly, below */ }
    else if ((j.log[key] || 0) >= c.targetFor(i)) done++;
  }
  let total = c.days;
  if (c.auto === 'workout') {
    total = 4; done = 0;
    for (let w = 0; w < 4; w++) {
      const ws = new Date(start); ws.setDate(ws.getDate() + w * 7); const we = new Date(ws); we.setDate(we.getDate() + 7);
      if (s.workouts.filter((x) => x.start >= ws.getTime() && x.start < we.getTime()).length >= 4) done++;
    }
  }
  return { dayIdx: Math.min(dayIdx, c.days - 1), done, total, pct: done / total, todayTarget: c.targetFor(Math.min(dayIdx, c.days - 1)), complete: done >= total };
}

export const ACHIEVEMENTS: { id: string; name: string; desc: string; emoji: string; test: (s: State) => boolean }[] = [
  { id: 'first-workout', name: 'First Rep', desc: 'Log your first workout', emoji: '🏁', test: (s) => s.workouts.length >= 1 },
  { id: 'ten-workouts', name: 'Ten Strong', desc: 'Log 10 workouts', emoji: '🔟', test: (s) => s.workouts.length >= 10 },
  { id: 'fifty-workouts', name: 'Iron Habit', desc: 'Log 50 workouts', emoji: '🏆', test: (s) => s.workouts.length >= 50 },
  { id: 'first-pr', name: 'New Record', desc: 'Set a personal record', emoji: '📈', test: (s) => Object.keys(s.prs).length >= 1 },
  { id: 'protein-day', name: 'Protein Pro', desc: 'Hit your protein target in a day', emoji: '🥚', test: (s) => !!s.profile && dayTotals(s).p >= userTargets(s).protein },
  { id: 'hydrated', name: 'Hydrated', desc: 'Hit your water target in a day', emoji: '💧', test: (s) => !!s.profile && dayTotals(s).water >= userTargets(s).water },
  { id: 'logger7', name: 'Food Logger', desc: 'Log food on 7 different days', emoji: '📒', test: (s) => new Set(s.meals.map((m) => m.date)).size >= 7 },
  { id: 'first-post', name: 'Hello Community', desc: 'Share your first post', emoji: '📣', test: (s) => !!s.profile && s.social.posts.some((p) => p.userId === s.profile!.userId) },
  { id: 'challenger', name: 'Challenger', desc: 'Join a challenge', emoji: '🎯', test: (s) => Object.keys(s.challenges).length >= 1 },
  { id: 'weigh-in', name: 'Tracking Progress', desc: 'Log 5 weigh-ins', emoji: '⚖️', test: (s) => s.weights.length >= 5 },
];

export function checkAchievements() {
  const s = getState(); if (!s.profile) return;
  const fresh = ACHIEVEMENTS.filter((a) => !s.achievements[a.id] && a.test(s));
  if (!fresh.length) return;
  update((d) => { for (const a of fresh) { d.achievements[a.id] = Date.now(); notify(d, { type: 'achievement', text: `Badge unlocked: ${a.emoji} ${a.name} — ${a.desc}` }); } });
  toast(`${fresh[0].emoji} Badge unlocked: ${fresh[0].name}`);
}

export function streak(s: State, test: (date: string) => boolean) {
  let n = 0; for (let i = 0; i < 365; i++) { const d = dayOffset(-i); if (test(d)) n++; else if (i > 0) break; }
  return n;
}

// ─── Toasts ───
type T = { id: number; text: string };
let toasts: T[] = []; const tsubs = new Set<() => void>();
export function toast(text: string) { const id = Date.now() + Math.random(); toasts = [...toasts, { id, text }]; tsubs.forEach((f) => f()); setTimeout(() => { toasts = toasts.filter((t) => t.id !== id); tsubs.forEach((f) => f()); }, 2800); }
export const toastStore = { sub: (f: () => void) => { tsubs.add(f); return () => tsubs.delete(f); }, get: () => toasts };

// ─── i18n (English shipped; Malayalam keys ready to be filled) ───
const DICT: Record<string, Record<string, string>> = {
  en: { home: 'Home', train: 'Train', nutrition: 'Nutrition', community: 'Community', profile: 'Profile', today: 'Today', water: 'Water', calories: 'Calories', protein: 'Protein', carbs: 'Carbs', fat: 'Fat' },
  ml: { home: 'ഹോം', train: 'പരിശീലനം', nutrition: 'പോഷണം', community: 'കമ്മ്യൂണിറ്റി', profile: 'പ്രൊഫൈൽ', today: 'ഇന്ന്', water: 'വെള്ളം', calories: 'കലോറി', protein: 'പ്രോട്ടീൻ', carbs: 'കാർബ്', fat: 'കൊഴുപ്പ്' },
};
export const t = (k: string) => DICT[getState().settings.lang]?.[k] || DICT.en[k] || k;

// ─── Native helpers (Capacitor when running as the Android app; web fallbacks) ───
const cap = () => (window as any).Capacitor;
export const isNative = () => !!cap()?.isNativePlatform?.();
export function haptic() { try { cap()?.Plugins?.Haptics?.impact?.({ style: 'LIGHT' }); if (!isNative()) navigator.vibrate?.(8); } catch { /* */ } }
export async function share(text: string, title = 'FITVERSE') {
  try { if (cap()?.Plugins?.Share && isNative()) { await cap().Plugins.Share.share({ title, text }); return true; } if (navigator.share) { await navigator.share({ title, text }); return true; } await navigator.clipboard.writeText(text); toast('Copied to clipboard'); return true; } catch { return false; }
}
export async function scheduleWaterReminders(s: State['settings']['reminders']) {
  const LN = cap()?.Plugins?.LocalNotifications;
  if (!LN) {
    if (!s.water) return 'off';
    if (typeof Notification !== 'undefined' && Notification.permission !== 'granted') await Notification.requestPermission();
    return typeof Notification !== 'undefined' && Notification.permission === 'granted' ? 'web' : 'denied';
  }
  const pending = await LN.getPending(); if (pending?.notifications?.length) await LN.cancel({ notifications: pending.notifications.map((n: any) => ({ id: n.id })) });
  if (!s.water) return 'off';
  const perm = await LN.requestPermissions(); if (perm.display !== 'granted') return 'denied';
  const notifications: any[] = []; let id = 100;
  for (let m = s.from * 60; m <= s.to * 60; m += s.every) notifications.push({ id: id++, title: 'Hydration check 💧', body: 'Time for a glass of water. Tap to log it in FITVERSE.', schedule: { on: { hour: Math.floor(m / 60), minute: m % 60 }, repeats: true, allowWhileIdle: true } });
  await LN.schedule({ notifications });
  return 'native';
}
// Web fallback reminder loop while the page is open.
let webTimer: any; let lastNotified = 0;
export function startWebReminderLoop() {
  clearInterval(webTimer);
  webTimer = setInterval(() => {
    const s = getState(); const r = s.settings.reminders; if (!r.water || isNative()) return;
    const h = new Date().getHours(); if (h < r.from || h > r.to) return;
    const last = s.water.filter((w) => w.date === today()).reduce((a, w) => Math.max(a, w.ts), 0);
    if (Date.now() - last > r.every * 60e3 && Date.now() - lastNotified > r.every * 60e3 && typeof Notification !== 'undefined' && Notification.permission === 'granted') { lastNotified = Date.now(); new Notification('Hydration check 💧', { body: 'Time for a glass of water.' }); }
  }, 5 * 60e3);
}
