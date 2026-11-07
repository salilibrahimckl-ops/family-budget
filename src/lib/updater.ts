// In-app updates: downloads the newest app bundle from the project's build branch and applies it on restart.
// Native features (new permissions/plugins) still need a new APK; the update screen says so when required.
export const REPO_RAW = 'https://raw.githubusercontent.com/salilibrahimckl-ops/family-budget/fitverse-builds/';
export const APK_URL = REPO_RAW + 'FITVERSE.apk';
export const currentBuild = () => Number((window as any).__FV_BUILD || 0);
export const builtInBuild = () => Number((window as any).__FV_BUILT_IN || 0);
export const isNativeApp = () => !!(window as any).Capacitor?.isNativePlatform?.();

export interface UpdateInfo { build: number; notes: string[]; date: string; minBuiltIn: number }
export async function checkForUpdate(): Promise<UpdateInfo | null> {
  const r = await fetch(REPO_RAW + 'version.json?t=' + Date.now(), { cache: 'no-store' });
  if (!r.ok) throw new Error('Could not reach the update server');
  const v = (await r.json()) as UpdateInfo;
  return v.build > currentBuild() ? v : null;
}
export function needsNewApk(u: UpdateInfo) { return builtInBuild() < (u.minBuiltIn || 0); }
export async function applyUpdate(onProgress?: (t: string) => void) {
  onProgress?.('Downloading…');
  const r = await fetch(REPO_RAW + 'bundle.json?t=' + Date.now(), { cache: 'no-store' });
  if (!r.ok) throw new Error('Download failed');
  const b = await r.json();
  if (!b.js || !b.css || !b.build || b.js.length < 50000) throw new Error('Update file looks incomplete — try again later');
  onProgress?.('Installing…');
  try {
    localStorage.setItem('fv.ota.js', b.js); localStorage.setItem('fv.ota.css', b.css); localStorage.setItem('fv.ota.v', String(b.build));
    localStorage.removeItem('fv.ota.bad'); localStorage.removeItem('fv.ota.booting');
  } catch { throw new Error('Not enough storage space for the update'); }
  onProgress?.('Restarting…');
  setTimeout(() => location.reload(), 400);
}
export function markBootOk() { try { localStorage.removeItem('fv.ota.booting'); } catch { /* */ } }
