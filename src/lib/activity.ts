// Sports & everyday activity: calories from MET values (2024 Adult Compendium of Physical Activities).
// kcal ≈ MET × body weight (kg) × hours. Estimates — real burn varies ±20–30% by fitness, technique and heart rate.
import { State, today, dayOffset } from './store';

export type Sport = { key: string; name: string; emoji: string; met: [number, number, number]; levels: [string, string, string]; distance?: boolean };
export const SPORTS: Sport[] = [
  { key: 'walk', name: 'Brisk walking', emoji: '🚶', met: [3.5, 4.3, 5.0], levels: ['Easy (4 km/h)', 'Brisk (5.5 km/h)', 'Very brisk (6.5 km/h)'], distance: true },
  { key: 'run', name: 'Running', emoji: '🏃', met: [7.0, 9.3, 11.5], levels: ['Jog (7 km/h)', 'Run (9.5 km/h)', 'Fast (12 km/h)'], distance: true },
  { key: 'badminton', name: 'Badminton', emoji: '🏸', met: [5.5, 7.0, 8.5], levels: ['Casual', 'Game', 'Competitive'] },
  { key: 'football', name: 'Football', emoji: '⚽', met: [7.0, 8.0, 10.0], levels: ['Casual kick-about', 'Match', 'Competitive'] },
  { key: 'swim', name: 'Swimming', emoji: '🏊', met: [5.8, 8.3, 10.0], levels: ['Easy laps', 'Moderate freestyle', 'Fast / butterfly'], distance: true },
  { key: 'cycle', name: 'Cycling', emoji: '🚴', met: [5.8, 7.5, 10.0], levels: ['Leisure (<16 km/h)', 'Moderate (16–20)', 'Fast (>20 km/h)'], distance: true },
  { key: 'cricket', name: 'Cricket', emoji: '🏏', met: [4.8, 5.5, 7.0], levels: ['Fielding / casual', 'Match', 'Bowling / nets'] },
  { key: 'volleyball', name: 'Volleyball', emoji: '🏐', met: [3.0, 4.0, 6.0], levels: ['Casual', 'Game', 'Competitive'] },
  { key: 'basketball', name: 'Basketball', emoji: '🏀', met: [4.5, 6.5, 8.0], levels: ['Shooting', 'Game', 'Competitive'] },
  { key: 'tennis', name: 'Tennis', emoji: '🎾', met: [5.0, 7.3, 8.0], levels: ['Doubles', 'Singles', 'Competitive'] },
  { key: 'tt', name: 'Table tennis', emoji: '🏓', met: [3.5, 4.0, 5.5], levels: ['Casual', 'Game', 'Competitive'] },
  { key: 'skip', name: 'Skipping rope', emoji: '🪢', met: [8.8, 11.8, 12.3], levels: ['Slow', 'Moderate', 'Fast'] },
  { key: 'hike', name: 'Hiking / trekking', emoji: '🥾', met: [5.3, 6.0, 7.8], levels: ['Easy trail', 'Hills', 'Steep with pack'], distance: true },
  { key: 'yoga', name: 'Yoga', emoji: '🧘', met: [2.3, 3.0, 4.0], levels: ['Gentle / stretching', 'Hatha', 'Power yoga'] },
  { key: 'dance', name: 'Dance / Zumba', emoji: '💃', met: [4.5, 6.0, 7.3], levels: ['Light', 'Aerobic', 'High energy'] },
  { key: 'martial', name: 'Martial arts / Kalari', emoji: '🥋', met: [5.3, 7.5, 10.3], levels: ['Drills', 'Training', 'Sparring'] },
  { key: 'stairs', name: 'Stair climbing', emoji: '🪜', met: [4.0, 8.8, 9.5], levels: ['Slow', 'Moderate', 'Fast'] },
  { key: 'other', name: 'Watch workout', emoji: '⌚', met: [4.0, 6.0, 8.0], levels: ['Light', 'Moderate', 'Hard'] },
  { key: 'house', name: 'Housework / gardening', emoji: '🧹', met: [2.5, 3.5, 4.5], levels: ['Light', 'Moderate', 'Heavy'] },
];
export const sportOf = (k: string) => SPORTS.find((x) => x.key === k) || SPORTS[0];
export const weightOf = (s: State) => (s.weights.length ? s.weights[s.weights.length - 1].kg : s.profile?.weight || 70);
export const estKcal = (s: State, sport: string, minutes: number, level: 1 | 2 | 3) => Math.round(sportOf(sport).met[level - 1] * weightOf(s) * (minutes / 60));
/** Gym sessions: ~5 METs for typical resistance training (rest periods included). */
export const workoutKcal = (s: State, w: { start: number; end: number; entries?: { sets: { done?: boolean }[] }[] }) => {
  const byTime = 5.0 * weightOf(s) * Math.min(4, Math.max(0, (w.end - w.start) / 3.6e6));
  // If the timer was short (sets ticked off quickly), count ~2.5 min of work+rest per completed set instead.
  const sets = (w.entries || []).reduce((a, e) => a + e.sets.filter((x) => x.done !== false).length, 0);
  const bySets = 5.0 * weightOf(s) * (sets * 2.5 / 60);
  return Math.round(Math.max(byTime, bySets));
};

const CH_INFO: Record<string, { name: string; emoji: string; unit: string }> = {
  pushup30: { name: 'Push-up challenge', emoji: '💪', unit: 'reps' }, plank30: { name: 'Plank challenge', emoji: '🧱', unit: 'seconds' }, steps10k: { name: 'Steps challenge', emoji: '👟', unit: 'steps' },
};
/** Calories from challenge check-ins (push-ups, plank, steps, custom reps/minutes) logged that day. */
export function challengeBurn(s: State, date: string) {
  const kg = weightOf(s); const out: { id: string; name: string; emoji: string; amount: number; unit: string; kcal: number; minutes: number }[] = [];
  for (const [id, j] of Object.entries(s.challenges || {})) {
    const amt = j.log?.[date] || 0; if (!amt) continue;
    const cc = (s.customChallenges || []).find((c) => c.id === id);
    const info = CH_INFO[id] || (cc ? { name: cc.name, emoji: cc.emoji, unit: cc.unit } : null); if (!info) continue;
    const u = info.unit.toLowerCase();
    let kcal = 0, minutes = 0;
    if (/rep/.test(u)) { kcal = amt * 0.45 * kg / 70; minutes = amt * 3 / 60; }
    else if (/sec/.test(u)) { kcal = 3.8 * kg * amt / 3600; minutes = amt / 60; }
    else if (/min/.test(u)) { kcal = 5 * kg * amt / 60; minutes = amt; }
    else if (/step/.test(u)) { if (s.watch?.connected && s.watch.daily[date]?.steps) continue; kcal = amt * 0.04 * kg / 70; minutes = amt / 110; }
    else if (/km/.test(u)) { kcal = amt * kg * 0.9; minutes = amt * 10; }
    else continue;
    out.push({ id, name: info.name, emoji: info.emoji, amount: amt, unit: info.unit, kcal: Math.round(kcal), minutes: Math.round(minutes) });
  }
  return out;
}

export function burnFor(s: State, date = today()) {
  const acts = (s.activities || []).filter((a) => a.date === date);
  const chs = challengeBurn(s, date);
  const wos = s.workouts.filter((w) => w.date === date);
  const sport = acts.reduce((a, x) => a + x.kcal, 0) + chs.reduce((a, x) => a + x.kcal, 0), gym = wos.reduce((a, w) => a + workoutKcal(s, w), 0);
  const minutes = acts.reduce((a, x) => a + x.minutes, 0) + chs.reduce((a, x) => a + x.minutes, 0) + wos.reduce((a, w) => a + Math.round((w.end - w.start) / 60000), 0);
  // A connected watch measures the whole day's active calories (it already includes workouts), so use whichever is higher.
  const w = s.watch?.connected ? s.watch.daily[date] : undefined;
  const watchKcal = Math.round(w?.kcal || 0);
  return { kcal: Math.max(sport + gym, watchKcal), sport, gym, minutes, acts, wos, watchKcal, steps: w?.steps || s.steps[date] || 0, fromWatch: watchKcal > sport + gym, chs };
}
/** This calendar week (Mon–Sun) totals used for the friends leaderboard. */
export function weekStats(s: State) {
  const d = new Date(); const dow = (d.getDay() + 6) % 7;
  const days = Array.from({ length: dow + 1 }, (_, i) => dayOffset(-i));
  let kcal = 0, minutes = 0, workouts = 0;
  for (const day of days) { const b = burnFor(s, day); kcal += b.kcal; minutes += b.minutes; workouts += b.wos.length + b.acts.length + b.chs.length; }
  // streak: consecutive days (ending today or yesterday) with any training
  let streak = 0; for (let i = 0; i < 365; i++) { const b = burnFor(s, dayOffset(-i)); if (b.wos.length || b.acts.length || b.chs.length) streak++; else if (i > 0) break; }
  return { week: days[days.length - 1], kcal, minutes, workouts, streak };
}

/** Total for a metric between two dates (inclusive), from this phone's workouts, sports and watch. */
export function metricBetween(s: State, metric: 'kcal' | 'minutes' | 'sessions', start: string, end: string) {
  let v = 0; const t = today();
  for (let d = new Date(start + 'T12:00:00'); ; d.setDate(d.getDate() + 1)) {
    const k = today(d); if (k > end || k > t) break;
    const b = burnFor(s, k); v += metric === 'kcal' ? b.kcal : metric === 'minutes' ? b.minutes : b.wos.length + b.acts.length + b.chs.length;
  }
  return v;
}
