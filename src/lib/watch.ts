// Smartwatch sync via Android Health Connect (Samsung Health / Galaxy Watch, Fitbit, Garmin Connect, Mi Fitness,
// Google Fit… and any watch app that shares to Health Connect). Read-only. Apple Health needs a native iPhone app.
import { getState, update, today, dayOffset, uid } from './store';
import { estKcal } from './activity';

const H = () => (window as any).Capacitor?.Plugins?.Health;
export const isAndroidApp = () => (window as any).Capacitor?.getPlatform?.() === 'android';
/** The installed APK contains the Health Connect bridge (builds from v1.0.20 onward). */
export const hasBridge = () => !!H() && isAndroidApp();
const PERMS = ['READ_WORKOUTS', 'READ_ACTIVE_CALORIES', 'READ_TOTAL_CALORIES', 'READ_STEPS', 'READ_DISTANCE'];

export async function healthAvailable(): Promise<boolean> { try { return !!(await H().isHealthAvailable()).available; } catch { return false; } }
export async function connectWatch(): Promise<'ok' | 'denied' | 'missing'> {
  if (!(await healthAvailable())) return 'missing';
  const r = await H().requestHealthPermissions({ permissions: PERMS });
  const granted = (r?.permissions || []).some((p: any) => Object.values(p)[0] === true);
  if (!granted) return 'denied';
  update((d) => { d.watch = { connected: true, daily: d.watch?.daily || {}, lastSync: d.watch?.lastSync }; });
  await syncWatch();
  return 'ok';
}
export function disconnectWatch() { update((d) => { if (d.watch) d.watch.connected = false; d.activities = (d.activities || []).filter((a) => a.source !== 'watch'); }); }
export const openHealthSettings = () => H()?.openHealthConnectSettings?.();
export const installHealthConnect = () => H()?.showHealthConnectInPlayStore?.();

const TYPE: Record<string, string> = {
  BADMINTON: 'badminton', SOCCER: 'football', FOOTBALL_AMERICAN: 'football', FOOTBALL_AUSTRALIAN: 'football', RUGBY: 'football',
  SWIMMING_POOL: 'swim', SWIMMING_OPEN_WATER: 'swim', RUNNING: 'run', RUNNING_TREADMILL: 'run', WALKING: 'walk', HIKING: 'hike',
  BIKING: 'cycle', BIKING_STATIONARY: 'cycle', CRICKET: 'cricket', VOLLEYBALL: 'volleyball', BASKETBALL: 'basketball', TENNIS: 'tennis',
  TABLE_TENNIS: 'tt', SQUASH: 'tennis', YOGA: 'yoga', PILATES: 'yoga', STRETCHING: 'yoga', DANCING: 'dance', MARTIAL_ARTS: 'martial', BOXING: 'martial',
  STAIR_CLIMBING: 'stairs', STAIR_CLIMBING_MACHINE: 'stairs',
};
let syncing: Promise<void> | null = null;
export function syncWatch(days = 7): Promise<void> {
  if (!hasBridge() || !getState().watch?.connected) return Promise.resolve();
  if (syncing) return syncing;
  syncing = (async () => {
    const start = new Date(dayOffset(-(days - 1)) + 'T00:00:00'); const end = new Date();
    const range = { startDate: start.toISOString(), endDate: end.toISOString() };
    const daily: Record<string, { steps: number; kcal: number }> = {};
    const dayKey = (iso: string) => today(new Date(iso));
    try { const st = await H().queryAggregated({ ...range, dataType: 'steps', bucket: 'day' }); for (const x of st.aggregatedData || []) { const k = dayKey(x.startDate); (daily[k] ||= { steps: 0, kcal: 0 }).steps += Math.round(x.value || 0); } } catch { /* no permission */ }
    try { const kc = await H().queryAggregated({ ...range, dataType: 'active-calories', bucket: 'day' }); for (const x of kc.aggregatedData || []) { const k = dayKey(x.startDate); (daily[k] ||= { steps: 0, kcal: 0 }).kcal += Math.round(x.value || 0); } } catch { /* */ }
    let workouts: any[] = [];
    try { workouts = (await H().queryWorkouts({ ...range, includeHeartRate: false, includeRoute: false, includeSteps: false })).workouts || []; } catch { /* */ }
    update((d) => {
      d.watch = { connected: true, lastSync: Date.now(), daily: { ...(d.watch?.daily || {}), ...daily } };
      for (const [k, v] of Object.entries(daily)) if (v.steps) d.steps[k] = v.steps;
      const acts = (d.activities ||= []);
      for (const w of workouts) {
        if (/STRENGTH|WEIGHTLIFTING|CALISTHENICS/.test(w.workoutType || '')) continue; // gym sessions are logged in the app
        const key = 'hc-' + (w.id || w.startDate);
        if (acts.find((a) => a.id === key)) continue;
        const minutes = Math.max(1, Math.round((w.duration || (Date.parse(w.endDate) - Date.parse(w.startDate)) / 1000) / 60));
        acts.push({ id: key, date: dayKey(w.startDate), ts: Date.parse(w.startDate), sport: TYPE[w.workoutType] || 'other', minutes, intensity: 2, kcal: Math.round(w.calories || 0) || estKcal(getState(), TYPE[w.workoutType] || 'other', minutes, 2), km: w.distance ? Math.round(w.distance / 100) / 10 : undefined, source: 'watch' });
      }
    });
  })().finally(() => { syncing = null; });
  return syncing;
}
void uid;
