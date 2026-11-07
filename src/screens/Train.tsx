import React, { useEffect, useMemo, useState } from 'react';
import { useStore, update, uid, today, getState, State, notify } from '../lib/store';
import { MUSCLES, EQUIP, EQUIP_RANK, Equip, Exercise, alternativeFor, Muscle } from '../data/exercises';
import { PROGRAMS, Program } from '../data/programs';
import { Header, BackBtn, Card, Btn, Chip, Seg, Icon, Pill, Sheet, Empty, go, back, useRoute, useTicker, fmt, NumIn, Field } from '../ui';
import { allExercises, exById, LEVEL, useUnits } from './common';
import { MuscleMap } from './MuscleMap';
import { todaysPlan, buildSchedule, recommendProgram } from '../lib/coach';
import { e1rm } from '../lib/calc';
import { toast, haptic, checkAchievements, share } from '../lib/extras';

const short = (n: string) => (/^Day [A-Z0-9]/.test(n) ? 'D' + n.slice(4, 5) : n.split(/[ &/]/)[0].slice(0, 5));
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const EQ_NAME = Object.fromEntries(EQUIP.map((e) => [e.key, e.name])) as Record<Equip, string>;

// ─────────── Hub ───────────
export function Train() {
  const s = useStore((x) => x);
  const { q } = useRoute();
  const tab = (q.get('tab') as any) || 'plan';
  return (
    <div className="page">
      <Header big title="Train" right={<button className="icon-btn" onClick={() => go('/train?tab=library')} aria-label="Search exercises"><Icon n="search" /></button>} />
      <Seg value={tab} onChange={(v) => go('/train?tab=' + v)} options={[{ v: 'plan', l: 'Plan' }, { v: 'library', l: 'Exercises' }, { v: 'history', l: 'History' }]} />
      {tab === 'plan' && <PlanTab s={s} />}
      {tab === 'library' && <Library />}
      {tab === 'history' && <History s={s} />}
    </div>
  );
}

function PlanTab({ s }: { s: State }) {
  const tp = todaysPlan(s); const prog = tp?.prog;
  const rec = recommendProgram(s);
  const todayIdx = new Date().getDay();
  const prs = Object.entries(s.prs).sort((a, b) => b[1].e1rm - a[1].e1rm).slice(0, 6);
  return <>
    {s.active && <Card className="resume" onClick={() => go('/workout')}><Icon n="timer" /><div><b>Resume workout</b><small>{s.active.name} · started {fmt.ago(s.active.start)} ago</small></div><Icon n="chev" /></Card>}
    <Card>
      <div className="row-b"><span className="lbl"><Icon n="calendar" s={16} /> Weekly calendar</span>{prog && <button className="link" onClick={() => go('/program/' + prog.id)}>Edit</button>}</div>
      <div className="week">
        {WD.map((d, i) => { const di = s.plan?.schedule[i]; const day = prog && di !== null && di !== undefined ? prog.days[di % prog.days.length] : null;
          const done = s.workouts.some((w) => new Date(w.start).getDay() === i && Date.now() - w.start < 7 * 864e5);
          return <button key={d} className={'wd' + (i === todayIdx ? ' today' : '') + (day ? ' on' : '') + (done ? ' done' : '')} onClick={() => day && go(`/workout/start/day/${prog!.id}/${di}`)}><small>{d}</small><b>{day ? short(day.name) : '—'}</b>{done && <i>✓</i>}</button>; })}
      </div>
      {tp?.day ? <Btn full icon="play" onClick={() => go('/workout/start/today')}>Start {tp.day.name}</Btn> : <Btn full kind="soft" icon="plus" onClick={() => go('/workout/start/empty')}>Start an empty workout</Btn>}
    </Card>
    <div className="row-b sec-h"><h3>Programmes</h3>{!s.plan && <Pill tone="lime">Recommended: {rec.name}</Pill>}</div>
    <div className="hscroll">
      {PROGRAMS.map((p) => (
        <Card key={p.id} className={'prog-card' + (s.plan?.programId === p.id ? ' active' : '')} onClick={() => go('/program/' + p.id)}>
          <div className="row-b"><Pill tone={p.level === 'Beginner' ? 'info' : p.level === 'Advanced' ? 'bad' : 'warn'}>{p.level}</Pill>{p.premium && <Pill tone="pro">PRO</Pill>}</div>
          <b>{p.name}</b><small>{p.perWeek}×/week · {p.goal}{p.home ? ' · Home' : ''}</small>
          {s.plan?.programId === p.id && <span className="prog-cur">Current plan</span>}
        </Card>
      ))}
    </div>
    <div className="row-b sec-h"><h3>My routines</h3><button className="link" onClick={() => go('/routine/new')}>+ New</button></div>
    {s.routines.length ? s.routines.map((r) => (
      <Card key={r.id} className="list-row">
        <div onClick={() => go('/routine/' + r.id)} style={{ flex: 1 }}><b>{r.name}</b><small>{r.items.length} exercises</small></div>
        <Btn small icon="play" onClick={() => go('/workout/start/routine/' + r.id)}>Start</Btn>
      </Card>
    )) : <p className="muted small pad">Build your own routine from any exercises in the library.</p>}
    <div className="row-b sec-h"><h3>Personal records</h3></div>
    {prs.length ? <div className="pr-grid">{prs.map(([id, pr]) => <Card key={id} className="pr" onClick={() => go('/exercise/' + id)}><small>{exById(s, id)?.name}</small><b>{pr.w} kg × {pr.r}</b><span>est. 1RM {Math.round(pr.e1rm)} kg</span></Card>)}</div> : <p className="muted small pad">Log weighted sets to track personal records automatically.</p>}
  </>;
}

// ─────────── Library ───────────
export function Library({ pick }: { pick?: (e: Exercise) => void }) {
  const s = useStore((x) => x);
  const [q, setQ] = useState(''); const [muscle, setMuscle] = useState<Muscle | ''>(''); const [eq, setEq] = useState<Equip | ''>('');
  const [lvl, setLvl] = useState(0); const [mech, setMech] = useState(''); const [where, setWhere] = useState<'' | 'gym' | 'home'>(''); const [type, setType] = useState('');
  const list = useMemo(() => allExercises(s).filter((e) =>
    (!q || (e.name + ' ' + e.secondary.join(' ') + ' ' + e.muscle).toLowerCase().includes(q.toLowerCase())) && (!muscle || e.muscle === muscle) && (!eq || e.equip === eq) && (!lvl || e.level === lvl)
    && (!mech || e.mech === mech) && (!type || e.type === type) && (!where || (where === 'home' ? EQUIP_RANK[e.equip] <= 2 : EQUIP_RANK[e.equip] >= 3))), [s, q, muscle, eq, lvl, mech, where, type]);
  const filtering = q || muscle || eq || lvl || mech || where || type;
  return <>
    <div className="search"><Icon n="search" s={18} /><input placeholder="Search 95+ exercises" value={q} onChange={(e) => setQ(e.target.value)} />{q && <button onClick={() => setQ('')}><Icon n="x" s={16} /></button>}</div>
    <div className="chips scroll">
      <Chip on={where === 'gym'} onClick={() => setWhere(where === 'gym' ? '' : 'gym')}>🏢 Gym</Chip><Chip on={where === 'home'} onClick={() => setWhere(where === 'home' ? '' : 'home')}>🏠 Home</Chip>
      <Chip on={mech === 'compound'} onClick={() => setMech(mech === 'compound' ? '' : 'compound')}>Compound</Chip><Chip on={mech === 'isolation'} onClick={() => setMech(mech === 'isolation' ? '' : 'isolation')}>Isolation</Chip>
      {[1, 2, 3].map((l) => <Chip key={l} on={lvl === l} onClick={() => setLvl(lvl === l ? 0 : l)}>{LEVEL[l]}</Chip>)}
    </div>
    <div className="chips scroll">{EQUIP.map((e) => <Chip key={e.key} on={eq === e.key} onClick={() => setEq(eq === e.key ? '' : e.key)}>{e.name}</Chip>)}
      {['strength', 'bodyweight', 'core', 'cardio', 'plyometric'].map((t) => <Chip key={t} on={type === t} onClick={() => setType(type === t ? '' : t)}>{t[0].toUpperCase() + t.slice(1)}</Chip>)}</div>
    {!filtering && <div className="muscle-grid">{MUSCLES.map((m) => <button key={m.key} onClick={() => setMuscle(m.key)}><span>{m.emoji}</span><b>{m.name}</b><small>{allExercises(s).filter((e) => e.muscle === m.key).length}</small></button>)}</div>}
    {filtering && <>
      {muscle && <div className="row-b"><h3 className="sec-h">{MUSCLES.find((m) => m.key === muscle)?.name}</h3><button className="link" onClick={() => setMuscle('')}>All muscles</button></div>}
      <p className="muted small">{list.length} exercise{list.length === 1 ? '' : 's'}</p>
      {list.map((e) => <ExRow key={e.id} e={e} onClick={() => (pick ? pick(e) : go('/exercise/' + e.id))} />)}
      {!list.length && <Empty icon="search" title="No exercises match" text="Try removing a filter." />}
    </>}
  </>;
}

function ExRow({ e, onClick, right }: { e: Exercise; onClick?: () => void; right?: React.ReactNode }) {
  return (
    <Card className="ex-row" onClick={onClick}>
      <div className="ex-ic">{MUSCLES.find((m) => m.key === e.muscle)?.emoji}</div>
      <div className="ex-t"><b>{e.name}</b><small>{EQ_NAME[e.equip]} · {e.mech} · {LEVEL[e.level]}</small></div>
      {right || <Icon n="chev" s={18} />}
    </Card>
  );
}

// ─────────── Exercise detail ───────────
export function ExerciseDetail({ id }: { id: string }) {
  const s = useStore((x) => x);
  const base = exById(s, id);
  const [home, setHome] = useState(false);
  const [lvl, setLvl] = useState<Equip>(s.profile && EQUIP_RANK[s.profile.equipment] < 3 ? s.profile.equipment : 'none');
  const [addOpen, setAddOpen] = useState(false);
  if (!base) return <div className="page"><Header left={<BackBtn />} title="Not found" /></div>;
  const alt = alternativeFor(base, lvl);
  const e = home && alt ? alt : base;
  const pr = s.prs[e.id];
  const premiumLocked = e.premium && s.settings.plan !== 'premium';
  const isGym = EQUIP_RANK[base.equip] >= 2 && Object.keys(base.alts).length > 0;
  return (
    <div className="page ex-page">
      <Header left={<BackBtn />} title={e.name} sub={`${MUSCLES.find((m) => m.key === e.muscle)?.name} · ${e.mech}`} right={<button className="icon-btn" onClick={() => setAddOpen(true)} aria-label="Add to routine"><Icon n="plus" /></button>} />
      {isGym && (
        <Card className="gymhome">
          <Seg value={home ? 'home' : 'gym'} onChange={(v) => setHome(v === 'home')} options={[{ v: 'gym', l: '🏢 Gym version' }, { v: 'home', l: '🏠 Home version' }]} />
          {home && <div className="chips scroll" style={{ marginTop: 10 }}>{EQUIP.filter((q) => EQUIP_RANK[q.key] < EQUIP_RANK[base.equip]).map((q) => <Chip key={q.key} on={lvl === q.key} onClick={() => setLvl(q.key)}>{q.name}</Chip>)}</div>}
          {home && alt && <p className="small muted">Swapped <b>{base.name}</b> → <b>{alt.name}</b> for {EQ_NAME[lvl].toLowerCase()}.</p>}
          {home && !alt && <p className="small muted">No alternative listed for this equipment level.</p>}
        </Card>
      )}
      <Card className="demo">
        <MuscleMap primary={e.muscle} secondary={e.secondary} />
        {premiumLocked ? <div className="demo-note"><Icon n="lock" s={16} /> Premium video — upgrade to watch.</div>
          : e.video ? <video className="demo-video" src={e.video} controls playsInline preload="metadata" />
            : <div className="demo-note"><Icon n="video" s={16} /> <div><b>Video demonstration not added yet.</b><small>FITVERSE only shows licensed demonstration videos; none is attached to this exercise. An admin can attach one from the Admin dashboard. Meanwhile follow the written cues below.</small></div></div>}
        {!e.video && <a className="demo-link" href={`https://www.youtube.com/results?search_query=${encodeURIComponent(e.name + ' proper form')}`} target="_blank" rel="noreferrer">Search form videos on YouTube ↗</a>}
      </Card>
      <div className="ex-stats">
        <div><small>Sets</small><b>{e.sets}</b></div><div><small>Reps</small><b>{e.reps}</b></div><div><small>Rest</small><b>{e.rest}</b></div><div><small>Level</small><b>{LEVEL[e.level]}</b></div>
      </div>
      {e.tempo && <p className="muted small pad">Tempo {e.tempo} (lower – pause – lift, seconds). A slower lowering phase is the "slow-motion" cue: control every rep.</p>}
      <Section title="Starting position" icon="user"><p>{e.start}</p></Section>
      <Section title="Execution" icon="play"><ol className="cue">{e.steps.map((x, i) => <li key={i}>{x}</li>)}</ol></Section>
      <Section title="Breathing" icon="drop"><p>{e.breath}</p></Section>
      <Section title="Posture & alignment" icon="check"><p>{e.posture}</p></Section>
      <Section title="Muscles" icon="spark"><p><b>Primary:</b> {MUSCLES.find((m) => m.key === e.muscle)?.name}</p><p><b>Secondary:</b> {e.secondary.join(', ') || '—'}</p></Section>
      <Section title="Common mistakes" icon="x"><ul className="bad">{e.mistakes.map((x, i) => <li key={i}>{x}</li>)}</ul></Section>
      <Section title="Safety" icon="shield"><ul className="warn">{e.safety.map((x, i) => <li key={i}>{x}</li>)}<li>Stop if you feel sharp or joint pain. Get medical advice for injuries, recent surgery or heart conditions before training.</li></ul></Section>
      <Section title="Equipment" icon="train"><p>{e.gear}</p></Section>
      {Object.keys(base.alts).length > 0 && <Section title="Alternatives by equipment" icon="swap">
        {(Object.entries(base.alts) as [Equip, string][]).map(([k, aid]) => { const a = exById(s, aid); return a ? <ExRow key={k} e={a} onClick={() => go('/exercise/' + a.id)} right={<Pill>{EQ_NAME[k]}</Pill>} /> : null; })}
      </Section>}
      {pr && <Card className="pr"><small>Your best</small><b>{pr.w} kg × {pr.r}</b><span>est. 1RM {Math.round(pr.e1rm)} kg · {fmt.date(pr.date)}</span></Card>}
      <div className="sticky-cta"><Btn full icon="play" onClick={() => { startWorkout(e.name, [{ id: e.id, sets: 3, reps: e.reps }]); }}>Do this exercise now</Btn></div>
      <AddToRoutine open={addOpen} onClose={() => setAddOpen(false)} ex={e} />
    </div>
  );
}
function Section({ title, icon, children }: { title: string; icon: string; children: React.ReactNode }) {
  return <Card className="section"><h4><Icon n={icon} s={16} /> {title}</h4>{children}</Card>;
}
function AddToRoutine({ open, onClose, ex }: { open: boolean; onClose: () => void; ex: Exercise }) {
  const routines = useStore((s) => s.routines);
  return <Sheet open={open} onClose={onClose} title="Add to routine">
    {routines.map((r) => <Card key={r.id} className="list-row" onClick={() => { update((d) => { d.routines.find((x) => x.id === r.id)!.items.push({ id: ex.id, sets: 3, reps: ex.reps }); }); toast(`Added to ${r.name}`); onClose(); }}><b>{r.name}</b><small>{r.items.length} exercises</small></Card>)}
    <Btn full kind="soft" icon="plus" onClick={() => { const id = uid(); update((d) => { d.routines.push({ id, name: 'My routine ' + (d.routines.length + 1), items: [{ id: ex.id, sets: 3, reps: ex.reps }] }); }); onClose(); go('/routine/' + id); }}>New routine with this exercise</Btn>
  </Sheet>;
}

// ─────────── Programme ───────────
export function ProgramDetail({ id }: { id: string }) {
  const s = useStore((x) => x);
  const p = PROGRAMS.find((x) => x.id === id)!;
  const isCur = s.plan?.programId === id;
  const [sched, setSched] = useState<(number | null)[]>(isCur ? s.plan!.schedule : buildSchedule(s.profile?.days || p.perWeek, p.days.length));
  const locked = p.premium && s.settings.plan !== 'premium';
  return (
    <div className="page">
      <Header left={<BackBtn />} title={p.name} sub={`${p.level} · ${p.perWeek}×/week · ${p.goal}`} />
      <p className="pad muted">{p.desc}</p>
      <Card>
        <span className="lbl">Schedule — tap a day to change it</span>
        <div className="week">{WD.map((d, i) => <button key={d} className={'wd' + (sched[i] !== null ? ' on' : '')} onClick={() => setSched((x) => { const n = [...x]; const cur = n[i]; n[i] = cur === null ? 0 : cur + 1 >= p.days.length ? null : cur + 1; return n; })}><small>{d}</small><b>{sched[i] === null ? 'Rest' : short(p.days[sched[i]!].name)}</b></button>)}</div>
        {locked ? <Btn full kind="soft" icon="lock" onClick={() => go('/premium')}>Premium programme — unlock</Btn>
          : <Btn full onClick={() => { update((d) => { d.plan = { programId: id, schedule: sched }; }); toast(isCur ? 'Schedule updated' : `${p.name} is now your plan`); back(); }}>{isCur ? 'Save schedule' : 'Apply this plan'}</Btn>}
      </Card>
      {p.days.map((d, di) => (
        <Card key={di}>
          <div className="row-b"><div><b>{d.name}</b><small className="muted"> · {d.focus}</small></div>{!locked && <Btn small kind="soft" icon="play" onClick={() => go(`/workout/start/day/${id}/${di}`)}>Start</Btn>}</div>
          {d.items.map((it) => { const e = exById(s, it.id); return e ? <div key={it.id} className="prog-ex" onClick={() => go('/exercise/' + e.id)}><span>{e.name}</span><b>{it.sets} × {it.reps}</b></div> : null; })}
        </Card>
      ))}
    </div>
  );
}

// ─────────── Routine editor ───────────
export function RoutineEditor({ id }: { id: string }) {
  const s = useStore((x) => x);
  const [rid] = useState(() => (id === 'new' ? uid() : id));
  const existing = s.routines.find((r) => r.id === rid);
  const [name, setName] = useState(existing?.name || 'My routine');
  const [items, setItems] = useState(existing?.items || []);
  const [picking, setPicking] = useState(false);
  function save() { if (!items.length) return toast('Add at least one exercise'); update((d) => { const r = d.routines.find((x) => x.id === rid); if (r) Object.assign(r, { name, items }); else d.routines.push({ id: rid, name, items }); }); toast('Routine saved'); back(); }
  return (
    <div className="page">
      <Header left={<BackBtn />} title={existing ? 'Edit routine' : 'New routine'} right={existing && <button className="icon-btn" aria-label="Delete" onClick={() => { update((d) => { d.routines = d.routines.filter((r) => r.id !== rid); }); back(); }}><Icon n="trash" /></button>} />
      <Field label="Name"><input value={name} onChange={(e) => setName(e.target.value)} /></Field>
      {items.map((it, i) => { const e = exById(s, it.id)!; return (
        <Card key={i} className="routine-item">
          <div className="row-b"><b>{e.name}</b><button className="icon-btn" onClick={() => setItems(items.filter((_, k) => k !== i))} aria-label="Remove"><Icon n="x" s={18} /></button></div>
          <div className="row"><Field label="Sets"><NumIn value={it.sets} onChange={(v) => setItems(items.map((x, k) => (k === i ? { ...x, sets: Math.max(1, Math.round(v)) } : x)))} w={44} /></Field>
            <Field label="Reps"><input value={it.reps} onChange={(ev) => setItems(items.map((x, k) => (k === i ? { ...x, reps: ev.target.value } : x)))} style={{ width: 90 }} /></Field>
            <div className="reorder"><button disabled={!i} onClick={() => { const n = [...items]; [n[i - 1], n[i]] = [n[i], n[i - 1]]; setItems(n); }}>↑</button><button disabled={i === items.length - 1} onClick={() => { const n = [...items]; [n[i + 1], n[i]] = [n[i], n[i + 1]]; setItems(n); }}>↓</button></div></div>
        </Card>); })}
      <Btn full kind="soft" icon="plus" onClick={() => setPicking(true)}>Add exercise</Btn>
      <div style={{ height: 12 }} />
      <Btn full onClick={save}>Save routine</Btn>
      <Sheet open={picking} onClose={() => setPicking(false)} title="Add exercise"><Library pick={(e) => { setItems([...items, { id: e.id, sets: 3, reps: e.reps }]); setPicking(false); }} /></Sheet>
    </div>
  );
}

// ─────────── Active workout ───────────
export function startWorkout(name: string, items: { id: string; sets: number; reps: string }[], programId?: string) {
  const s = getState();
  if (s.active && !confirm('A workout is already in progress. Discard it and start a new one?')) { go('/workout'); return; }
  const lastFor = (exId: string) => { for (const w of s.workouts) { const e = w.entries.find((x) => x.exId === exId); if (e) return e.sets; } return null; };
  update((d) => {
    d.active = { name, programId, start: Date.now(), home: false, entries: items.map((it) => {
      const prev = lastFor(it.id); const reps = parseInt(it.reps) || 10;
      return { exId: it.id, sets: Array.from({ length: it.sets }, (_, k) => ({ w: prev?.[k]?.w ?? prev?.[0]?.w ?? 0, r: prev?.[k]?.r ?? reps, done: false })) };
    }) };
  });
  location.replace('#/workout');
}

export function WorkoutStart({ parts }: { parts: string[] }) {
  const s = getState();
  useEffect(() => {
    const [, , kind, a, b] = parts;
    if (kind === 'today') { const tp = todaysPlan(s); if (tp?.day) startWorkout(tp.day.name, tp.day.items, tp.prog!.id); else startWorkout('Workout', []); }
    else if (kind === 'day') { const p = PROGRAMS.find((x) => x.id === a)!; const d = p.days[+b]; startWorkout(d.name, d.items, p.id); }
    else if (kind === 'routine') { const r = s.routines.find((x) => x.id === a)!; startWorkout(r.name, r.items); }
    else startWorkout('Workout', []);
  }, []);
  return null;
}

export function ActiveWorkout() {
  useTicker(1000);
  const s = useStore((x) => x); const a = s.active; const u = useUnits();
  const [rest, setRest] = useState<{ until: number; total: number } | null>(null);
  const [picking, setPicking] = useState(false);
  const [restDefault, setRestDefault] = useState(90);
  useEffect(() => { if (rest && Date.now() >= rest.until) { setRest(null); haptic(); try { navigator.vibrate?.([200, 100, 200]); } catch { /* */ } toast('Rest over — next set 💪'); } });
  if (!a) return <div className="page"><Header left={<BackBtn />} title="Workout" /><Empty icon="train" title="No active workout" action={<Btn onClick={() => go('/train')}>Go to Train</Btn>} /></div>;
  const eqLevel = s.profile?.equipment || 'gym';
  const mod = (fn: (x: NonNullable<State['active']>) => void) => update((d) => { if (d.active) fn(d.active); });
  const doneSets = a.entries.reduce((n, e) => n + e.sets.filter((x) => x.done).length, 0);
  const totalSets = a.entries.reduce((n, e) => n + e.sets.length, 0);
  const volume = a.entries.reduce((v, e) => v + e.sets.filter((x) => x.done).reduce((q, x) => q + x.w * x.r, 0), 0);

  function finish() {
    if (!doneSets) { if (confirm('No sets are ticked as done, so there is nothing to save. Discard this workout?')) { update((d) => { d.active = null; }); go('/train'); } return; }
    const st = getState(); const act = st.active!;
    const prs: string[] = [];
    const entries = act.entries.map((e) => ({ ...e, sets: e.sets.filter((x) => x.done) })).filter((e) => e.sets.length);
    update((d) => {
      for (const e of entries) for (const x of e.sets) {
        if (x.w <= 0) continue; const est = e1rm(x.w, x.r); const cur = d.prs[e.exId];
        if (!cur || est > cur.e1rm + 0.01) { d.prs[e.exId] = { w: x.w, r: x.r, e1rm: est, date: today() }; if (!prs.includes(e.exId)) prs.push(e.exId); }
      }
      const log = { id: uid(), date: today(), start: act.start, end: Date.now(), name: act.name, programId: act.programId, entries, volume, prs };
      d.workouts.unshift(log); d.active = null;
      if (prs.length) notify(d, { type: 'achievement', text: `New personal record${prs.length > 1 ? 's' : ''}: ${prs.map((id) => exById(d, id)?.name).join(', ')} 📈` });
    });
    checkAchievements();
    toast(prs.length ? `Workout saved · ${prs.length} new PR${prs.length > 1 ? 's' : ''}! 🎉` : 'Workout saved 💪');
    go('/workout-summary/' + getState().workouts[0].id);
  }
  return (
    <div className="page wo-page">
      <Header left={<button className="icon-btn" onClick={() => go('/train')} aria-label="Minimise"><Icon n="back" /></button>} title={<input className="wo-name" value={a.name} onChange={(e) => mod((x) => { x.name = e.target.value; })} />} right={<Btn small onClick={finish}>Finish</Btn>} />
      <div className="wo-bar">
        <div><small>Time</small><b>{fmt.dur(Date.now() - a.start)}</b></div><div><small>Sets</small><b>{doneSets}/{totalSets}</b></div><div><small>Volume</small><b>{fmt.n(volume)} kg</b></div>
        <button className={'homebtn' + (a.home ? ' on' : '')} onClick={() => mod((x) => {
          x.home = !x.home;
          x.entries.forEach((en) => { const e = exById(getState(), en.exId); if (!e) return; if (x.home) { const alt = alternativeFor(e, EQUIP_RANK[eqLevel] >= 3 ? 'none' : eqLevel); if (alt) en.exId = alt.id; } });
        })}>{a.home ? '🏠 Home' : '🏢 Gym'}</button>
      </div>
      {a.entries.map((en, ei) => { const e = exById(s, en.exId); if (!e) return null; const pr = s.prs[e.id]; const alt = alternativeFor(e, EQUIP_RANK[eqLevel] >= 3 ? 'none' : eqLevel);
        return (
          <Card key={ei} className="wo-ex-card">
            <div className="row-b"><div onClick={() => go('/exercise/' + e.id)}><b>{e.name}</b><small className="muted">{e.rest} rest · {pr ? `PR ${pr.w}×${pr.r}` : 'no PR yet'}</small></div>
              <div className="row">{alt && <button className="icon-btn" title={`Swap to ${alt.name}`} onClick={() => mod((x) => { x.entries[ei].exId = alt.id; })}><Icon n="swap" s={18} /></button>}
                <button className="icon-btn" onClick={() => mod((x) => { x.entries.splice(ei, 1); })} aria-label="Remove exercise"><Icon n="trash" s={18} /></button></div></div>
            <div className="set-h"><span>Set</span><span>{u.wU}</span><span>Reps</span><span>✓</span></div>
            {en.sets.map((st, si) => (
              <div key={si} className={'set-row' + (st.done ? ' done' : '')}>
                <span>{si + 1}</span>
                <input inputMode="decimal" value={st.w ? u.wNum(st.w) : ''} placeholder={e.type === 'bodyweight' || e.type === 'core' ? 'BW' : '0'} onChange={(ev) => mod((x) => { x.entries[ei].sets[si].w = +u.wIn(parseFloat(ev.target.value) || 0).toFixed(2); })} />
                <input inputMode="numeric" value={st.r || ''} onChange={(ev) => mod((x) => { x.entries[ei].sets[si].r = parseInt(ev.target.value) || 0; })} />
                <button className="tick" onClick={() => { haptic(); mod((x) => { x.entries[ei].sets[si].done = !st.done; }); if (!st.done) { const sec = parseInt(e.rest) ? (e.rest.includes('min') ? parseFloat(e.rest) * 60 : parseInt(e.rest)) : restDefault; setRest({ until: Date.now() + sec * 1000, total: sec }); } }}><Icon n="check" s={18} /></button>
              </div>
            ))}
            <div className="row"><button className="link" onClick={() => mod((x) => { const l = x.entries[ei].sets.slice(-1)[0]; x.entries[ei].sets.push({ w: l?.w || 0, r: l?.r || 10, done: false }); })}>+ Add set</button>
              {en.sets.length > 1 && <button className="link muted" onClick={() => mod((x) => { x.entries[ei].sets.pop(); })}>− Remove set</button>}</div>
          </Card>); })}
      <Btn full kind="soft" icon="plus" onClick={() => setPicking(true)}>Add exercise</Btn>
      <div className="row" style={{ justifyContent: 'center', marginTop: 12 }}>
        <span className="muted small">Default rest</span>{[60, 90, 120, 180].map((r) => <Chip key={r} on={restDefault === r} onClick={() => setRestDefault(r)}>{r}s</Chip>)}
        <Btn small kind="ghost" icon="timer" onClick={() => setRest({ until: Date.now() + restDefault * 1000, total: restDefault })}>Rest</Btn>
      </div>
      <Btn full kind="danger" onClick={() => { if (confirm('Discard this workout? Nothing will be saved.')) { update((d) => { d.active = null; }); go('/train'); } }}>Discard workout</Btn>
      {rest && <div className="rest-ov"><div className="rest-card">
        <small>Rest</small><b>{fmt.dur(Math.max(0, rest.until - Date.now()))}</b>
        <div className="bar"><i style={{ width: `${(1 - (rest.until - Date.now()) / (rest.total * 1000)) * 100}%` }} /></div>
        <div className="row"><Btn small kind="soft" onClick={() => setRest({ ...rest, until: rest.until - 15000 })}>−15s</Btn><Btn small kind="soft" onClick={() => setRest({ ...rest, until: rest.until + 15000, total: rest.total + 15 })}>+15s</Btn><Btn small onClick={() => setRest(null)}>Skip</Btn></div>
      </div></div>}
      <Sheet open={picking} onClose={() => setPicking(false)} title="Add exercise"><Library pick={(e) => { mod((x) => { x.entries.push({ exId: e.id, sets: [0, 1, 2].map(() => ({ w: 0, r: parseInt(e.reps) || 10, done: false })) }); }); setPicking(false); }} /></Sheet>
    </div>
  );
}

export function WorkoutSummary({ id }: { id: string }) {
  const s = useStore((x) => x); const w = s.workouts.find((x) => x.id === id);
  if (!w) return null;
  const mins = Math.round((w.end - w.start) / 60000);
  function post() {
    update((d) => { d.social.posts.unshift({ id: uid(), userId: d.profile!.userId, ts: Date.now(), kind: 'workout', text: `Finished ${w!.name} 💪`, media: [], workout: { name: w!.name, volume: w!.volume, minutes: mins, exercises: w!.entries.length }, likes: 0 }); });
    checkAchievements(); toast('Shared to your feed'); go('/community');
  }
  return (
    <div className="page">
      <Header left={<button className="icon-btn" onClick={() => go('/home')} aria-label="Close"><Icon n="x" /></button>} title="Workout complete" />
      <div className="summary-hero"><div className="confetti">🎉</div><h2>{w.name}</h2><p className="muted">{new Date(w.start).toLocaleString('en-IN', { weekday: 'long', hour: 'numeric', minute: '2-digit' })}</p></div>
      <div className="ex-stats"><div><small>Duration</small><b>{mins} min</b></div><div><small>Exercises</small><b>{w.entries.length}</b></div><div><small>Sets</small><b>{w.entries.reduce((n, e) => n + e.sets.length, 0)}</b></div><div><small>Volume</small><b>{fmt.n(w.volume)} kg</b></div></div>
      {w.prs.length > 0 && <Card className="pr-banner"><Icon n="trophy" /> {w.prs.length} new personal record{w.prs.length > 1 ? 's' : ''}: {w.prs.map((p) => exById(s, p)?.name).join(', ')}</Card>}
      {w.entries.map((e, i) => <Card key={i}><b>{exById(s, e.exId)?.name}</b><div className="muted small">{e.sets.map((x) => `${x.w ? x.w + ' kg × ' : ''}${x.r}`).join(' · ')}</div></Card>)}
      <Btn full icon="share" onClick={post}>Share to community</Btn><div style={{ height: 8 }} />
      <Btn full kind="ghost" onClick={() => share(`I just finished ${w.name} on FITVERSE — ${mins} min, ${fmt.n(w.volume)} kg volume 💪`)}>Share outside the app</Btn>
    </div>
  );
}

function History({ s }: { s: State }) {
  const [open, setOpen] = useState<string | null>(null);
  const w = s.workouts.find((x) => x.id === open);
  if (!s.workouts.length) return <Empty icon="calendar" title="No workouts yet" text="Finished workouts appear here with sets, weights and PRs." action={<Btn onClick={() => go('/train')}>Start training</Btn>} />;
  return <>
    {s.workouts.map((x) => (
      <Card key={x.id} className="list-row" onClick={() => setOpen(x.id)}>
        <div className="hist-date"><b>{new Date(x.start).getDate()}</b><small>{new Date(x.start).toLocaleDateString('en-IN', { month: 'short' })}</small></div>
        <div style={{ flex: 1 }}><b>{x.name}</b><small>{x.entries.length} exercises · {Math.round((x.end - x.start) / 60000)} min · {fmt.n(x.volume)} kg{x.prs.length ? ` · 🏆 ${x.prs.length} PR` : ''}</small></div><Icon n="chev" s={18} />
      </Card>
    ))}
    <Sheet open={!!w} onClose={() => setOpen(null)} title={w?.name}>
      {w && <>{w.entries.map((e, i) => <div key={i} className="hist-ex"><b>{exById(s, e.exId)?.name}</b><span>{e.sets.map((x) => `${x.w ? x.w + '×' : ''}${x.r}`).join(' · ')}</span></div>)}
        <Btn full kind="danger" onClick={() => { if (confirm('Delete this workout from history?')) { update((d) => { d.workouts = d.workouts.filter((q) => q.id !== w.id); }); setOpen(null); } }}>Delete workout</Btn></>}
    </Sheet>
  </>;
}
