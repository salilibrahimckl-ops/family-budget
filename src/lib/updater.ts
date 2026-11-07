// In-app updates: downloads the newest app bundle from the project's build branch and applies it on restart.
// Native features (new permissions/plugins) still need a new APK; the update screen says so when required.
export const REPO_RAW = 'https://raw.githubusercontent.com/salilibrahimckl-ops/family-budget/fitverse-builds/';
export const APK_URL = REPO_RAW + 'FITVERSE.apk';
export const currentBuild = () => Number((window as any).__FV_BUILD || 0);
export const builtInBuild = () => Number((window as any).__FV_BUILT_IN || 0);
export const isNativeApp = () => !!(window as any).Capacitor?.isNativePlatform?.();

export interface UpdateInfo { build: number; notes: string[]; date: string; minBuiltIn: number; nativeBuild?: number }
export async function checkForUpdate(): Promise<UpdateInfo | null> {
  const r = await fetch(REPO_RAW + 'version.json?t=' + Date.now(), { cache: 'no-store' });
  if (!r.ok) throw new Error('Could not reach the update server');
  const v = (await r.json()) as UpdateInfo;
  return v.build > currentBuild() || needsNewApk(v) ? v : null;
}
/** The installed app (native part) is older than the newest native features. */
export function needsNewApk(u: UpdateInfo) { return isNativeApp() && builtInBuild() < Math.max(u.minBuiltIn || 0, u.nativeBuild || 0); }
const installer = () => (window as any).Capacitor?.Plugins?.ApkInstaller;
let installing = false;
/** One button does everything: newest app code now, and the new app version when phone features changed. */
export async function smartUpdate(u: UpdateInfo, onProgress: (t: string) => void) {
  if (installing) return; installing = true;
  try {
    if (u.build > currentBuild()) await saveBundle(onProgress);
    if (!needsNewApk(u)) { onProgress('Restarting…'); setTimeout(() => location.reload(), 400); return; }
    const inst = installer();
    if (inst) {
      const ok = (await inst.canInstall()).allowed;
      if (!ok) { onProgress(''); await inst.openInstallSettings(); throw new Error('Allow “Install unknown apps” for Bro’s Fitness, then come back and tap Update again.'); }
      const h = await inst.addListener?.('progress', (e: any) => onProgress('Downloading ' + Math.round((e.progress || 0) * 100) + '%'));
      onProgress('Downloading…');
      await inst.downloadAndInstall({ url: APK_URL + '?v=' + u.build });
      h?.remove?.();
      onProgress('Tap “Update” on the next screen');
    } else {
      // Older installs have no in-app installer: the phone downloads the new version, then one tap on it installs.
      onProgress('Downloading new version…');
      location.href = APK_URL + '?v=' + u.build;
      setTimeout(() => onProgress('Open the download → Install'), 1500);
    }
  } finally { installing = false; }
}
async function saveBundle(onProgress?: (t: string) => void) {
  onProgress?.('Downloading…');
  const r = await fetch(REPO_RAW + 'bundle.json?t=' + Date.now(), { cache: 'no-store' });
  if (!r.ok) throw new Error('Download failed');
  const b = await r.json();
  if (!b.js || !b.css || !b.build || b.js.length < 50000) throw new Error('Update file looks incomplete — try again later');
  try {
    localStorage.setItem('fv.ota.js', b.js); localStorage.setItem('fv.ota.css', b.css); localStorage.setItem('fv.ota.v', String(b.build));
    localStorage.removeItem('fv.ota.bad'); localStorage.removeItem('fv.ota.booting');
  } catch { throw new Error('Not enough storage space for the update'); }
}
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

/** iPhone / browser version: pick up new versions by itself (on open and when brought back), then reload once. */
export function startWebAutoUpdate() {
  if (isNativeApp() || !(window as any).__FV_WEB) return;
  let busy = false;
  const run = async () => {
    if (busy || document.visibilityState !== 'visible') return; busy = true;
    try {
      const v = await (await fetch(REPO_RAW + 'version.json?t=' + Date.now(), { cache: 'no-store' })).json();
      if (!(v.build > currentBuild())) return;
      const t = await (await fetch(REPO_RAW + 'bundle.json?t=' + Date.now(), { cache: 'no-store' })).text();
      const b = JSON.parse(t);
      if (!(b.build > currentBuild()) || !b.js || b.js.length < 50000) return;
      localStorage.setItem('fvw.bundle', t);
      location.reload();
    } catch { /* offline — try later */ } finally { busy = false; }
  };
  setTimeout(run, 2000);
  document.addEventListener('visibilitychange', run);
  setInterval(run, 10 * 60e3);
}
