// Pops up once per new version when the app opens: one big Update button does everything.
import React, { useEffect, useState } from 'react';
import { Sheet, Btn } from '../ui';
import { checkForUpdate, smartUpdate, needsNewApk, isNativeApp, UpdateInfo } from '../lib/updater';
import { toast } from '../lib/extras';

export function UpdatePrompt() {
  const [u, setU] = useState<UpdateInfo | null>(null); const [busy, setBusy] = useState('');
  useEffect(() => {
    if (!isNativeApp()) return;
    const t = setTimeout(() => checkForUpdate().then((v) => {
      if (!v) return;
      const key = 'fv.upd.later.' + v.build + (needsNewApk(v) ? 'n' : '');
      try { if (sessionStorage.getItem(key)) return; } catch { /* */ }
      setU(v);
    }).catch(() => undefined), 1800);
    return () => clearTimeout(t);
  }, []);
  if (!u) return null;
  const later = () => { try { sessionStorage.setItem('fv.upd.later.' + u.build + (needsNewApk(u) ? 'n' : ''), '1'); } catch { /* */ } setU(null); };
  return (
    <Sheet open onClose={later} title="New update ✨">
      <p><b>Version 1.0.{u.build}</b></p>
      <ul className="cue small">{u.notes.slice(0, 5).map((n, i) => <li key={i}>{n}</li>)}</ul>
      {needsNewApk(u) && <p className="muted small">This one adds new phone features. After it downloads, Android shows an install screen — tap <b>Update</b>. Your workouts, meals and account stay.</p>}
      <Btn full disabled={!!busy} onClick={() => smartUpdate(u, setBusy).catch((e) => { toast(e.message); setBusy(''); })}>{busy || 'Update now'}</Btn>
      <button className="link center" onClick={later}>Later</button>
    </Sheet>
  );
}
