// Log sports & everyday activity so the day's calorie burn isn't missed.
import React, { useState } from 'react';
import { useStore, update, uid, today } from '../lib/store';
import { Header, BackBtn, Card, Btn, Chip, Icon, NumIn, go, back, fmt } from '../ui';
import { SPORTS, sportOf, estKcal, burnFor, workoutKcal } from '../lib/activity';
import { toast, checkAchievements } from '../lib/extras';
import { ask } from '../lib/dialog';

export function LogActivity() {
  const s = useStore((x) => x);
  const [sport, setSport] = useState<string | null>(() => new URLSearchParams(location.hash.split('?')[1] || '').get('s'));
  const [min, setMin] = useState(30); const [lvl, setLvl] = useState<1 | 2 | 3>(2); const [km, setKm] = useState(0);
  const sp = sport ? sportOf(sport) : null;
  const kcal = sp ? estKcal(s, sp.key, min, lvl) : 0;
  function save() {
    if (!sp || min <= 0) return;
    update((d) => { (d.activities ||= []).push({ id: uid(), date: today(), ts: Date.now(), sport: sp.key, minutes: min, intensity: lvl, kcal, km: km || undefined, source: 'manual' }); });
    checkAchievements(); toast(`${sp.emoji} ${sp.name} logged · ${kcal} kcal`); back();
  }
  return (
    <div className="page">
      <Header left={<BackBtn />} title={sp ? sp.name : 'Log a sport or activity'} />
      {!sp ? <>
        <p className="muted small">Pick what you did. Calories are estimated from your weight and the activity’s intensity (MET values).</p>
        <div className="sport-grid">{SPORTS.map((x) => <button key={x.key} onClick={() => setSport(x.key)}><span>{x.emoji}</span><small>{x.name}</small></button>)}</div>
      </> : <>
        <Card className="sport-head"><span className="sport-emo">{sp.emoji}</span><div><b>{kcal} kcal</b><small>estimated for {min} min</small></div></Card>
        <Card><span className="lbl">How long?</span>
          <div className="chips">{[15, 20, 30, 45, 60, 90, 120].map((m) => <Chip key={m} on={min === m} onClick={() => setMin(m)}>{m < 60 ? m + ' min' : Math.floor(m / 60) + ' h' + (m % 60 ? ' ' + (m % 60) + ' min' : '')}</Chip>)}</div>
          <div className="row" style={{ marginTop: 10 }}><NumIn value={min} onChange={(v) => setMin(Math.max(1, Math.min(600, Math.round(v || 0))))} /><span className="muted">minutes</span></div>
        </Card>
        <Card><span className="lbl">How hard?</span>
          <div className="lvl-list">{sp.levels.map((l, i) => <button key={l} className={lvl === i + 1 ? 'on' : ''} onClick={() => setLvl((i + 1) as 1 | 2 | 3)}><b>{['Light', 'Moderate', 'Hard'][i]}</b><small>{l}</small></button>)}</div>
        </Card>
        {sp.distance && <Card><span className="lbl">Distance (optional)</span><div className="row"><NumIn value={km} onChange={(v) => setKm(Math.max(0, v || 0))} /><span className="muted">km</span></div></Card>}
        <Btn full icon="check" onClick={save}>Log {kcal} kcal</Btn>
        <button className="link center" onClick={() => setSport(null)}>Choose a different activity</button>
        <p className="muted small">Estimate only — real burn varies by fitness, technique and heart rate. A smartwatch reading is more accurate when you have one.</p>
      </>}
    </div>
  );
}

/** Home card: today's calorie burn from gym sessions + sports. */
export function BurnCard() {
  const s = useStore((x) => x); const b = burnFor(s);
  async function del(id: string) { if (await ask('Remove this activity?')) update((d) => { d.activities = (d.activities || []).filter((a) => a.id !== id); }); }
  return (
    <Card className="burn-card">
      <div className="row-b"><span className="lbl"><Icon n="flame" s={16} /> Burnt today</span><button className="link" onClick={() => go('/activity')}>+ Log sport</button></div>
      <div className="burn-top"><b className="big-num">{fmt.n(b.kcal)}<em> kcal</em></b><small>{b.steps ? fmt.n(b.steps) + ' steps · ' : ''}{b.minutes} active min</small></div>
      {b.fromWatch && <p className="muted small" style={{ margin: '-4px 0 6px' }}>⌚ From your watch’s all-day active calories</p>}
      {!s.watch?.connected && <button className="link small" style={{ padding: 0, marginBottom: 6 }} onClick={() => go('/settings')}>⌚ Connect a smartwatch</button>}
      {(b.acts.length > 0 || b.wos.length > 0 || b.chs.length > 0) ? <div className="burn-list">
        {b.wos.map((w) => <div key={w.id}><span>🏋️ {w.name}</span><small>{Math.round((w.end - w.start) / 60000)} min · {workoutKcal(s, w)} kcal</small></div>)}
        {b.chs.map((c) => <div key={c.id} onClick={() => go('/challenges')}><span>{c.emoji} {c.name}</span><small>{fmt.n(c.amount)} {c.unit} · {c.kcal} kcal</small></div>)}
        {b.acts.map((a) => { const sp = sportOf(a.sport); return <div key={a.id} onClick={() => del(a.id)}><span>{sp.emoji} {sp.name}{a.source === 'watch' ? ' ⌚' : ''}</span><small>{a.minutes} min{a.km ? ` · ${a.km} km` : ''} · {a.kcal} kcal</small></div>; })}
      </div> : <p className="muted small" style={{ margin: 0 }}>Played badminton, football, went for a swim or a brisk walk? Log it so no calories are missed.</p>}
      <div className="sport-quick">{['walk', 'run', 'badminton', 'football', 'swim'].map((k) => { const sp = sportOf(k); return <button key={k} onClick={() => go('/activity?s=' + k)}>{sp.emoji}<small>{sp.name.split(' ')[0]}</small></button>; })}</div>
    </Card>
  );
}
