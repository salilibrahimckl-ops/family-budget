// Settings card: connect a smartwatch (through Android Health Connect).
import React, { useState } from 'react';
import { useStore } from '../lib/store';
import { Card, Btn, Icon, fmt } from '../ui';
import { hasBridge, isAndroidApp, connectWatch, disconnectWatch, syncWatch, openHealthSettings, installHealthConnect } from '../lib/watch';
import { UpdatesCard } from './Profile';
import { toast } from '../lib/extras';
import { ask } from '../lib/dialog';

const BRANDS: [string, string][] = [
  ['⌚ Samsung Galaxy Watch', 'Samsung Health → ⋮ → Settings → Health Connect → allow all. Then Connect below.'],
  ['⌚ Fitbit / Pixel Watch', 'Fitbit app → You → Settings → Health Connect → turn on.'],
  ['⌚ Garmin', 'Garmin Connect → More → Settings → Health Connect (or use Google Fit sync).'],
  ['⌚ G-SHOCK / Casio', 'In the CASIO WATCHES / G-SHOCK MOVE app, turn on Health Connect or Google Fit sharing (supported models only).'],
  ['⌚ Mi / Amazfit / Noise / boAt', 'In the watch’s app, turn on Health Connect or Google Fit sharing if offered.'],
  [' Apple Watch', 'Apple only allows App Store apps to read Apple Health, so it can’t connect to the iPhone web app. Log sports manually for now.'],
];

export function WatchCard() {
  const w = useStore((s) => s.watch);
  const [busy, setBusy] = useState(false);
  const [help, setHelp] = useState(false);
  const bridge = hasBridge();
  async function connect() {
    setBusy(true);
    try {
      const r = await connectWatch();
      if (r === 'ok') toast('Connected ✓ — steps, calories and workouts will sync');
      else if (r === 'missing') { if (await ask('Health Connect isn’t installed or set up on this phone. Open the Play Store to get it?')) installHealthConnect(); }
      else { if (await ask('No permission was given. Open Health Connect to allow Bro’s Fitness?')) openHealthSettings(); }
    } catch (e: any) { toast('Could not connect: ' + e.message); } finally { setBusy(false); }
  }
  return (
    <Card><span className="lbl">⌚ Smartwatch & health apps</span>
      {!isAndroidApp() ? <p className="muted small">Watch sync works in the Android app through Health Connect. On iPhone, Apple Watch data can’t be read by a web app — log sports manually.</p>
        : !bridge ? <>
          <p className="muted small">Watch sync comes with the newest app version. Tap Update — your data stays.</p>
          <UpdatesCard compact />
        </>
        : w?.connected ? <>
          <p className="muted small">Connected through Health Connect · last sync {w.lastSync ? fmt.ago(w.lastSync) : '—'}. Steps, active calories and sports sessions from your watch are added automatically.</p>
          <div className="row"><Btn small disabled={busy} onClick={async () => { setBusy(true); try { await syncWatch(14); toast('Synced ✓'); } catch (e: any) { toast(e.message); } setBusy(false); }}>{busy ? 'Syncing…' : 'Sync now'}</Btn>
            <Btn small kind="soft" onClick={() => openHealthSettings()}>Permissions</Btn>
            <Btn small kind="soft" onClick={async () => { if (await ask('Disconnect the watch? Synced watch sessions will be removed from the app.')) disconnectWatch(); }}>Disconnect</Btn></div>
        </> : <>
          <p className="muted small">Connect Samsung, Fitbit, Garmin, G-SHOCK (supported models) and other watches through Android’s Health Connect. Read-only — nothing is changed in your watch data.</p>
          <Btn full disabled={busy} onClick={connect}>{busy ? 'Connecting…' : 'Connect watch'}</Btn>
        </>}
      <button className="link" onClick={() => setHelp(!help)}><Icon n="chev" s={14} /> {help ? 'Hide' : 'How to link'} your watch brand</button>
      {help && <div className="watch-help">{BRANDS.map(([b, t]) => <div key={b}><b>{b}</b><small>{t}</small></div>)}</div>}
    </Card>
  );
}
