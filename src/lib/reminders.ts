// Smart reminders (Android app). Re-planned every time data changes, so messages reflect today's real progress:
// meal logging, water, protein, today's workout and an evening "finish your workout" push.
import { getState, today, State, subscribe } from './store';
import { dayTotals, userTargets, todaysPlan } from './coach';
import { PROGRAMS } from '../data/programs';

export const DEFAULT_NOTIFY = { meals: true, times: ['08:30', '13:30', '20:30'] as [string, string, string], workout: true, workoutTime: '18:00', nudges: true };
const LN = () => (window as any).Capacitor?.Plugins?.LocalNotifications;
export const remindersSupported = () => !!LN() && !!(window as any).Capacitor?.isNativePlatform?.();
export const notifyCfg = (s: State) => ({ ...DEFAULT_NOTIFY, ...(s.settings.notify || {}) });

const at = (dayOffset: number, hhmm: string) => { const [h, m] = hhmm.split(':').map(Number); const d = new Date(); d.setDate(d.getDate() + dayOffset); d.setHours(h, m, 0, 0); return d; };
const dateKey = (d: Date) => today(d);

export async function requestPermission(): Promise<boolean> {
  const ln = LN(); if (!ln) return false;
  try { let p = await ln.checkPermissions(); if (p.display !== 'granted') p = await ln.requestPermissions(); return p.display === 'granted'; } catch { return false; }
}

let busy = false; let again = false;
export async function scheduleAll() {
  const ln = LN(); const s = getState();
  if (!ln || !remindersSupported() || !s.profile) return 'unsupported';
  if (busy) { again = true; return 'queued'; } busy = true;
  try {
    const perm = await ln.checkPermissions(); if (perm.display !== 'granted') return 'denied';
    const pending = await ln.getPending(); if (pending?.notifications?.length) await ln.cancel({ notifications: pending.notifications.map((n: any) => ({ id: n.id })) });
    const cfg = notifyCfg(s); const tg = userTargets(s); const now = Date.now(); const out: any[] = []; let id = 1000;
    const add = (when: Date, title: string, body: string, route: string) => { if (when.getTime() > now + 30e3) out.push({ id: id++, title, body, schedule: { at: when, allowWhileIdle: true }, extra: { route } }); };
    const first = s.profile.name.split(' ')[0];

    for (let d = 0; d < 4; d++) {
      const date = at(d, '12:00'); const key = dateKey(date); const tot = dayTotals(s, key); const meals = s.meals.filter((m) => m.date === key);
      // Meals
      if (cfg.meals) {
        const slots: [string, string, string][] = [['breakfast', cfg.times[0], 'Breakfast time 🍳'], ['lunch', cfg.times[1], 'Lunch check 🍛'], ['dinner', cfg.times[2], 'Dinner log 🌙']];
        for (const [slot, time, title] of slots) {
          if (meals.some((m) => m.slot === slot)) continue;
          const tip = slot === 'breakfast' ? `Start strong, ${first} — aim for ~${Math.round(tg.protein / 4)} g protein this meal.` : slot === 'lunch' ? 'Log your lunch in 10 seconds — just type what you ate.' : `Log dinner to close your day. Target ${tg.kcal} kcal, ${tg.protein} g protein.`;
          add(at(d, time), title, tip, `/food/add?slot=${slot}&mode=text`);
        }
      }
      // Water
      if (s.settings.reminders.water) {
        const r = s.settings.reminders;
        for (let m = r.from * 60; m <= r.to * 60; m += r.every) {
          const t = at(d, `${Math.floor(m / 60)}:${m % 60}`);
          add(t, 'Hydration check 💧', d === 0 && tot.water > 0 ? `${(tot.water / 1000).toFixed(1)} of ${(tg.water / 1000).toFixed(1)} L so far — have a glass now.` : 'Time for a glass of water. Tap to log it.', '/water');
        }
      }
      // Workouts on planned training days
      if (cfg.workout && s.plan) {
        const prog = PROGRAMS.find((p) => p.id === s.plan!.programId); const idx = s.plan.schedule[date.getDay()];
        const doneToday = s.workouts.some((w) => w.date === key);
        if (prog && idx !== null && idx !== undefined && !doneToday) {
          const day = prog.days[idx % prog.days.length];
          add(at(d, cfg.workoutTime), `Today: ${day.name} 💪`, `${day.focus} · ${day.items.length} exercises (~${s.profile.minutes} min). Tap to start.`, '/workout/start/today');
          add(at(d, '21:00'), 'Your workout is still waiting ⏳', `${day.name} isn’t done yet. Even 20 focused minutes counts — don’t break the streak!`, '/workout/start/today');
        }
      }
    }
    // Today's progress nudges (based on what's logged right now)
    if (cfg.nudges) {
      const tot = dayTotals(s); const lowP = tg.protein - tot.p;
      if (lowP > tg.protein * 0.25) add(at(0, '19:30'), 'Protein gap 🥚', `You’re ${Math.round(lowP)} g short of ${tg.protein} g. Easy fixes: curd, eggs, chicken, paneer or kadala.`, '/nutrition');
      if (tot.water < tg.water * 0.6) add(at(0, '17:00'), 'Behind on water 💧', `${(tot.water / 1000).toFixed(1)} of ${(tg.water / 1000).toFixed(1)} L so far. Two glasses now gets you back on track.`, '/water');
      if (!s.meals.some((m) => m.date === today())) add(at(0, '15:00'), 'Nothing logged yet today 📒', 'Quick: type “2 chapati, dal and curd” and we’ll do the maths.', '/food/add?mode=text');
    }
    if (out.length) await ln.schedule({ notifications: out.slice(0, 60) });
    return 'scheduled';
  } catch (e) { console.warn('[reminders]', e); return 'error'; }
  finally { busy = false; if (again) { again = false; setTimeout(scheduleAll, 500); } }
}

export async function testNotification() {
  const ln = LN(); if (!ln) return false;
  if (!(await requestPermission())) return false;
  await ln.schedule({ notifications: [{ id: 999, title: 'Bro’s Fitness 💪', body: 'Reminders are working! You’ll get nudges for meals, water and workouts.', schedule: { at: new Date(Date.now() + 3000) }, extra: { route: '/home' } }] });
  return true;
}

let timer: any;
export function initReminders(go: (r: string) => void) {
  const ln = LN(); if (!ln || !remindersSupported()) return;
  ln.addListener?.('localNotificationActionPerformed', (e: any) => { const r = e?.notification?.extra?.route; if (r) go(r); });
  subscribe(() => { clearTimeout(timer); timer = setTimeout(scheduleAll, 4000); });
  scheduleAll();
}
