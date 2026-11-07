// Admin dashboard: manage content without releasing a new app version.
import React, { useState } from 'react';
import { useStore, update, uid, State } from '../lib/store';
import { Header, BackBtn, Card, Btn, Chip, Seg, Icon, Pill, Sheet, Empty, go, Field, NumIn, fmt, Avatar } from '../ui';
import { MUSCLES, EQUIP, Exercise, Muscle, Equip } from '../data/exercises';
import { Food, FOOD_CATS } from '../data/foods';
import { allExercises, allFoods, exById } from './common';
import { toast, CHALLENGES } from '../lib/extras';

export function Admin() {
  const s = useStore((x) => x);
  const [tab, setTab] = useState<'overview' | 'exercises' | 'foods' | 'moderation' | 'users' | 'challenges'>('overview');
  if (!s.settings.admin) return <div className="page"><Header left={<BackBtn />} title="Admin" /><Empty icon="lock" title="Not authorised" text="Admin access is required." /></div>;
  return <div className="page"><Header left={<BackBtn />} title="Admin dashboard" />
    <div className="chips scroll">{(['overview', 'exercises', 'foods', 'moderation', 'users', 'challenges'] as const).map((t) => <Chip key={t} on={tab === t} onClick={() => setTab(t)}>{t[0].toUpperCase() + t.slice(1)}{t === 'moderation' && s.social.reports.filter((r) => r.status === 'open').length ? ` (${s.social.reports.filter((r) => r.status === 'open').length})` : ''}</Chip>)}</div>
    {tab === 'overview' && <Overview s={s} />}
    {tab === 'exercises' && <ExerciseAdmin s={s} />}
    {tab === 'foods' && <FoodAdmin s={s} />}
    {tab === 'moderation' && <Moderation s={s} />}
    {tab === 'users' && <UsersAdmin s={s} />}
    {tab === 'challenges' && <ChallengeAdmin s={s} />}
  </div>;
}

function Overview({ s }: { s: State }) {
  const week = Date.now() - 7 * 864e5;
  const rows: [string, number | string][] = [
    ['Exercises', allExercises(s).length], ['Exercises with video', allExercises(s).filter((e) => e.video).length], ['Foods', allFoods(s).length], ['Custom foods', s.customFoods.length],
    ['Community users', s.social.users.length + 1], ['Posts', s.social.posts.length], ['Comments', s.social.comments.length], ['Open reports', s.social.reports.filter((r) => r.status === 'open').length],
    ['Workouts logged (7 d)', s.workouts.filter((w) => w.start > week).length], ['Meals logged (7 d)', s.meals.filter((m) => new Date(m.date).getTime() > week).length], ['Active challenges', Object.keys(s.challenges).length],
  ];
  return <><Card><span className="lbl">Platform analytics {s.session?.mode === 'cloud' ? '(this device + synced data)' : '(this device)'}</span>{rows.map(([k, v]) => <div key={k} className="row-b an-kv"><span>{k}</span><b>{v}</b></div>)}</Card>
    <p className="muted small pad">In cloud mode, platform-wide analytics come from the <code>admin_platform_stats</code> view in Supabase (admin-only via RLS).</p></>;
}

const blank = (): Exercise => ({ id: '', name: '', muscle: 'chest', secondary: [], equip: 'none', gear: '', type: 'strength', mech: 'compound', level: 1, start: '', steps: [''], breath: '', posture: '', mistakes: [''], safety: [''], sets: '3', reps: '8–12', rest: '90 s', alts: {} });

function ExerciseAdmin({ s }: { s: State }) {
  const [q, setQ] = useState(''); const [edit, setEdit] = useState<Exercise | null>(null);
  const list = allExercises(s).filter((e) => e.name.toLowerCase().includes(q.toLowerCase()));
  return <>
    <div className="row"><div className="search" style={{ flex: 1 }}><Icon n="search" s={18} /><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search exercises" /></div><Btn icon="plus" onClick={() => setEdit(blank())}>Add</Btn></div>
    {list.map((e) => <Card key={e.id} className="list-row" onClick={() => setEdit(e)}><div style={{ flex: 1 }}><b>{e.name}</b><small>{e.muscle} · {e.equip} · {Object.keys(e.alts).length} alternatives{e.video ? ' · 🎬 video' : ''}{s.exOverrides[e.id] ? ' · edited' : ''}</small></div><Icon n="edit" s={18} /></Card>)}
    {edit && <ExerciseEditor ex={edit} onClose={() => setEdit(null)} />}
  </>;
}
function ExerciseEditor({ ex, onClose }: { ex: Exercise; onClose: () => void }) {
  const s = useStore((x) => x); const [e, setE] = useState<Exercise>(structuredClone(ex)); const isNew = !ex.id;
  const set = <K extends keyof Exercise>(k: K, v: Exercise[K]) => setE((x) => ({ ...x, [k]: v }));
  const lines = (k: 'steps' | 'mistakes' | 'safety' | 'secondary') => <textarea rows={3} value={(e[k] as string[]).join('\n')} onChange={(ev) => set(k, ev.target.value.split('\n'))} />;
  function save() {
    if (!e.name.trim()) return toast('Name required');
    const clean = { ...e, steps: e.steps.filter(Boolean), mistakes: e.mistakes.filter(Boolean), safety: e.safety.filter(Boolean), secondary: e.secondary.filter(Boolean) };
    if (clean.video && !/^https:\/\/.+\.(mp4|webm|m3u8)(\?.*)?$/i.test(clean.video)) return toast('Video must be an https URL to an .mp4/.webm/.m3u8 file you are licensed to use');
    update((d) => {
      if (isNew) { clean.id = clean.name.toLowerCase().replace(/[^a-z0-9]+/g, '-') + '-' + uid().slice(0, 4); d.extraExercises.push(clean); }
      else if (d.extraExercises.find((x) => x.id === clean.id)) d.extraExercises = d.extraExercises.map((x) => (x.id === clean.id ? clean : x));
      else d.exOverrides[clean.id] = clean;
    });
    toast('Exercise saved — live immediately'); onClose();
  }
  return <Sheet open onClose={onClose} title={isNew ? 'Add exercise' : 'Edit exercise'}>
    <Field label="Name"><input value={e.name} onChange={(v) => set('name', v.target.value)} /></Field>
    <div className="grid2">
      <Field label="Muscle"><select value={e.muscle} onChange={(v) => set('muscle', v.target.value as Muscle)}>{MUSCLES.map((m) => <option key={m.key} value={m.key}>{m.name}</option>)}</select></Field>
      <Field label="Equipment"><select value={e.equip} onChange={(v) => set('equip', v.target.value as Equip)}>{EQUIP.map((m) => <option key={m.key} value={m.key}>{m.name}</option>)}</select></Field>
      <Field label="Mechanic"><select value={e.mech} onChange={(v) => set('mech', v.target.value as any)}><option value="compound">Compound</option><option value="isolation">Isolation</option></select></Field>
      <Field label="Difficulty"><select value={e.level} onChange={(v) => set('level', +v.target.value as any)}><option value={1}>Beginner</option><option value={2}>Intermediate</option><option value={3}>Advanced</option></select></Field>
      <Field label="Sets"><input value={e.sets} onChange={(v) => set('sets', v.target.value)} /></Field><Field label="Reps"><input value={e.reps} onChange={(v) => set('reps', v.target.value)} /></Field>
      <Field label="Rest"><input value={e.rest} onChange={(v) => set('rest', v.target.value)} /></Field>
      <Field label="Type"><select value={e.type} onChange={(v) => set('type', v.target.value as any)}>{['strength', 'bodyweight', 'core', 'cardio', 'plyometric'].map((t) => <option key={t}>{t}</option>)}</select></Field>
    </div>
    <Field label="Demonstration video URL (licensed)" hint="https link to MP4/WebM, e.g. from Supabase Storage. Leave empty if none."><input value={e.video || ''} onChange={(v) => set('video', v.target.value.trim() || undefined)} placeholder="https://…/bench-press.mp4" /></Field>
    <label className="toggle-inline"><input type="checkbox" checked={!!e.premium} onChange={(v) => set('premium', v.target.checked)} /> Premium video</label>
    <Field label="Equipment needed"><input value={e.gear} onChange={(v) => set('gear', v.target.value)} /></Field>
    <Field label="Starting position"><textarea rows={2} value={e.start} onChange={(v) => set('start', v.target.value)} /></Field>
    <Field label="Execution steps (one per line)">{lines('steps')}</Field>
    <Field label="Breathing"><input value={e.breath} onChange={(v) => set('breath', v.target.value)} /></Field>
    <Field label="Posture"><input value={e.posture} onChange={(v) => set('posture', v.target.value)} /></Field>
    <Field label="Secondary muscles (one per line)">{lines('secondary')}</Field>
    <Field label="Common mistakes (one per line)">{lines('mistakes')}</Field>
    <Field label="Safety (one per line)">{lines('safety')}</Field>
    <span className="lbl">Home alternatives</span>
    {(['none', 'bands', 'dumbbells', 'homegym'] as Equip[]).map((k) => <Field key={k} label={EQUIP.find((x) => x.key === k)!.name}><select value={e.alts[k] || ''} onChange={(v) => set('alts', { ...e.alts, [k]: v.target.value || undefined })}><option value="">— none —</option>{allExercises(s).filter((x) => x.id !== e.id).map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}</select></Field>)}
    <div className="row">{!isNew && s.exOverrides[e.id] && <Btn kind="ghost" onClick={() => { update((d) => { delete d.exOverrides[e.id]; }); toast('Reverted to original'); onClose(); }}>Revert</Btn>}<Btn full onClick={save}>Save</Btn></div>
  </Sheet>;
}

function FoodAdmin({ s }: { s: State }) {
  const [q, setQ] = useState(''); const [edit, setEdit] = useState<Food | null>(null);
  const list = allFoods(s).filter((f) => f.name.toLowerCase().includes(q.toLowerCase())).slice(0, 60);
  return <>
    <div className="row"><div className="search" style={{ flex: 1 }}><Icon n="search" s={18} /><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search foods" /></div>
      <Btn icon="plus" onClick={() => setEdit({ id: '', name: '', cat: 'Kerala & South Indian', kcal: 0, p: 0, c: 0, f: 0, fib: 0, servings: [{ label: '1 serving', g: 100 }], aliases: [] })}>Add</Btn></div>
    {list.map((f) => <Card key={f.id} className="list-row" onClick={() => setEdit(f)}><div style={{ flex: 1 }}><b>{f.name}</b><small>{f.kcal} kcal · P {f.p} · C {f.c} · F {f.f} per 100 {f.unit || 'g'}</small></div><Icon n="edit" s={18} /></Card>)}
    {edit && <FoodEditor f={edit} onClose={() => setEdit(null)} />}
  </>;
}
function FoodEditor({ f: f0, onClose }: { f: Food; onClose: () => void }) {
  const [f, setF] = useState<Food>(structuredClone(f0)); const isNew = !f0.id;
  return <Sheet open onClose={onClose} title={isNew ? 'Add food' : 'Edit food'}>
    <Field label="Name"><input value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} /></Field>
    <Field label="Category"><select value={f.cat} onChange={(e) => setF({ ...f, cat: e.target.value as any })}>{FOOD_CATS.map((c) => <option key={c}>{c}</option>)}</select></Field>
    <p className="muted small">Values per 100 {f.unit || 'g'}</p>
    <div className="grid2">{(['kcal', 'p', 'c', 'f', 'fib'] as const).map((k) => <Field key={k} label={{ kcal: 'kcal', p: 'Protein g', c: 'Carbs g', f: 'Fat g', fib: 'Fibre g' }[k]}><NumIn value={f[k]} onChange={(v) => setF({ ...f, [k]: v })} w={56} /></Field>)}</div>
    <Field label="Serving (label, grams)"><div className="row"><input value={f.servings[0].label} onChange={(e) => setF({ ...f, servings: [{ ...f.servings[0], label: e.target.value }, ...f.servings.slice(1)] })} /><NumIn value={f.servings[0].g} onChange={(v) => setF({ ...f, servings: [{ ...f.servings[0], g: v }, ...f.servings.slice(1)] })} w={48} /></div></Field>
    <Field label="Search aliases (comma separated)"><input value={(f.aliases || []).join(', ')} onChange={(e) => setF({ ...f, aliases: e.target.value.split(',').map((x) => x.trim().toLowerCase()).filter(Boolean) })} /></Field>
    <label className="toggle-inline"><input type="checkbox" checked={!!f.estimate} onChange={(e) => setF({ ...f, estimate: e.target.checked })} /> Recipe-dependent (show "est." label)</label>
    <Btn full onClick={() => { if (!f.name.trim()) return toast('Name required'); update((d) => {
      if (isNew) d.customFoods.push({ ...f, id: 'af-' + uid(), custom: false });
      else if (d.customFoods.find((x) => x.id === f.id)) d.customFoods = d.customFoods.map((x) => (x.id === f.id ? f : x));
      else d.foodOverrides[f.id] = f;
    }); toast('Food saved'); onClose(); }}>Save</Btn>
  </Sheet>;
}

function Moderation({ s }: { s: State }) {
  const reps = s.social.reports.slice().sort((a, b) => (a.status === 'open' ? -1 : 1) - (b.status === 'open' ? -1 : 1) || b.ts - a.ts);
  if (!reps.length) return <Empty icon="shield" title="No reports" text="Reported posts appear here for review." />;
  return <>{reps.map((r) => { const p = s.social.posts.find((x) => x.id === r.postId); const u = s.social.users.find((x) => x.id === p?.userId);
    return <Card key={r.id}><div className="row-b"><Pill tone={r.status === 'open' ? 'warn' : r.status === 'removed' ? 'bad' : 'n'}>{r.status}</Pill><small className="muted">{fmt.ago(r.ts)}</small></div>
      <p><b>Reason:</b> {r.reason}</p><p className="muted small">@{u?.username}: {p?.text.slice(0, 140)}</p>
      {r.status === 'open' && <div className="row"><Btn small kind="danger" onClick={() => update((d) => { d.social.reports.find((x) => x.id === r.id)!.status = 'removed'; const pp = d.social.posts.find((x) => x.id === r.postId); if (pp) pp.removed = true; })}>Remove post</Btn>
        <Btn small kind="soft" onClick={() => update((d) => { d.social.reports.find((x) => x.id === r.id)!.status = 'dismissed'; })}>Dismiss</Btn>
        {p && <Btn small kind="ghost" onClick={() => go('/post/' + p.id)}>View</Btn>}</div>}
    </Card>; })}</>;
}

function UsersAdmin({ s }: { s: State }) {
  return <>{s.social.users.map((u) => <Card key={u.id} className="list-row"><Avatar name={u.name} color={u.avatarColor} size={36} /><div style={{ flex: 1 }}><b>{u.name}</b><small>@{u.username}{u.sample ? ' · sample' : ''}{u.suspended ? ' · suspended' : ''}</small></div>
    <Btn small kind={u.suspended ? 'soft' : 'danger'} onClick={() => update((d) => { const x = d.social.users.find((q) => q.id === u.id)!; x.suspended = !x.suspended; })}>{u.suspended ? 'Restore' : 'Suspend'}</Btn>
    <Btn small kind="ghost" onClick={() => update((d) => { const x = d.social.users.find((q) => q.id === u.id)!; x.creator = !x.creator; })}>{u.creator ? 'Unverify' : 'Verify'}</Btn></Card>)}</>;
}

function ChallengeAdmin({ s }: { s: State }) {
  const [c, setC] = useState({ name: '', desc: '', days: 30, unit: 'reps', target: 20, emoji: '🔥' });
  return <>
    <Card><span className="lbl">Create challenge</span>
      <Field label="Name"><input value={c.name} onChange={(e) => setC({ ...c, name: e.target.value })} placeholder="30-Day Squat Challenge" /></Field>
      <Field label="Description"><textarea rows={2} value={c.desc} onChange={(e) => setC({ ...c, desc: e.target.value })} /></Field>
      <div className="grid2"><Field label="Days"><NumIn value={c.days} onChange={(v) => setC({ ...c, days: Math.round(v) })} w={44} /></Field><Field label="Daily target"><NumIn value={c.target} onChange={(v) => setC({ ...c, target: v })} w={52} /></Field>
        <Field label="Unit"><input value={c.unit} onChange={(e) => setC({ ...c, unit: e.target.value })} /></Field><Field label="Emoji"><input value={c.emoji} onChange={(e) => setC({ ...c, emoji: e.target.value })} /></Field></div>
      <Btn full onClick={() => { if (!c.name) return toast('Name required'); const nc = { ...c, id: 'cc-' + uid() }; update((d) => { d.customChallenges.push(nc); }); CHALLENGES.push({ ...nc, targetFor: () => nc.target }); toast('Challenge published'); setC({ ...c, name: '', desc: '' }); }}>Publish challenge</Btn></Card>
    {s.customChallenges.map((x) => <Card key={x.id} className="list-row"><span>{x.emoji}</span><div style={{ flex: 1 }}><b>{x.name}</b><small>{x.days} days · {x.target} {x.unit}/day</small></div>
      <button className="icon-btn" onClick={() => { update((d) => { d.customChallenges = d.customChallenges.filter((q) => q.id !== x.id); }); const i = CHALLENGES.findIndex((q) => q.id === x.id); if (i >= 0) CHALLENGES.splice(i, 1); }} aria-label="Delete"><Icon n="trash" s={18} /></button></Card>)}
  </>;
}
