import React, { useState } from 'react';
import { update, useStore, Profile, today, putMedia, processImage } from '../lib/store';
import { ACTIVITY, GOALS, Goal, Activity, targets, bmi, bmiClass } from '../lib/calc';
import { EQUIP, Equip } from '../data/exercises';
import { Btn, Field, Chip, Seg, Icon, NumIn, useMediaUrl } from '../ui';
import { recommendProgram, buildSchedule } from '../lib/coach';
import { toast } from '../lib/extras';

const ALLERGENS = ['Peanuts', 'Tree nuts', 'Milk / lactose', 'Eggs', 'Fish', 'Shellfish', 'Soy', 'Wheat / gluten', 'Sesame'];

export function Onboarding() {
  const session = useStore((s) => s.session)!;
  const imp = useStore((s) => s.settings.units === 'imperial');
  const [step, setStep] = useState(0);
  const [p, setP] = useState<Profile>({
    userId: session.userId, name: '', username: '', age: 25, sex: 'male', height: 170, weight: 70, targetWeight: 65,
    experience: 'beginner', activity: 'light', days: 3, minutes: 45, goal: 'general', equipment: 'gym', diet: 'nonveg', allergies: [],
    photos: [], bio: '', private: false, showStats: false, leaderboard: true, createdAt: Date.now(),
  });
  const set = <K extends keyof Profile>(k: K, v: Profile[K]) => setP((x) => ({ ...x, [k]: v }));
  const steps = ['About you', 'Body', 'Goal', 'Training', 'Food', 'Photos', 'Your plan'];
  const ok = [p.name.trim().length > 1 && p.age >= 13 && p.age <= 100, p.height > 100 && p.weight > 25 && p.targetWeight > 25, true, true, true, true, true][step];

  function finish() {
    const username = (p.username || p.name).toLowerCase().replace(/[^a-z0-9_.]/g, '').slice(0, 20) || 'athlete';
    const prog = recommendProgram({ profile: p } as any);
    update((d) => {
      d.profile = { ...p, username, name: p.name.trim() };
      d.weights = [{ date: today(), kg: p.weight }];
      d.plan = { programId: prog.id, schedule: buildSchedule(p.days, prog.days.length) };
      d.social.users = d.social.users.filter((u) => u.id !== p.userId);
    });
    toast(`Welcome to FITVERSE, ${p.name.split(' ')[0]}! 🎉`);
    location.hash = '#/home';
  }

  const t = targets({ sex: p.sex, weight: p.weight, height: p.height, age: p.age, activity: p.activity, goal: p.goal, trainingDays: p.days });
  const b = bmi(p.weight, p.height);

  return (
    <div className="onb">
      <div className="onb-top">
        {step > 0 ? <button className="icon-btn" onClick={() => setStep(step - 1)} aria-label="Back"><Icon n="back" /></button> : <span style={{ width: 40 }} />}
        <div className="onb-prog"><i style={{ width: `${((step + 1) / steps.length) * 100}%` }} /></div>
        <span className="onb-count">{step + 1}/{steps.length}</span>
      </div>
      <h2 className="onb-title">{steps[step]}</h2>
      <div className="onb-body">
        {step === 0 && <>
          <Field label="Your name"><input value={p.name} onChange={(e) => set('name', e.target.value)} placeholder="e.g. Salil" autoFocus /></Field>
          <Field label="Username" hint="Shown in the community"><input value={p.username} onChange={(e) => set('username', e.target.value.toLowerCase().replace(/[^a-z0-9_.]/g, ''))} placeholder={p.name ? p.name.toLowerCase().replace(/[^a-z0-9]/g, '') : 'username'} /></Field>
          <Field label="Age"><NumIn value={p.age} onChange={(v) => set('age', Math.round(v))} suffix="yrs" /></Field>
          <Field label="Sex" hint="Used only for metabolic calculations (Mifflin-St Jeor)."><Seg value={p.sex} onChange={(v) => set('sex', v)} options={[{ v: 'male', l: 'Male' }, { v: 'female', l: 'Female' }]} /></Field>
        </>}
        {step === 1 && <>
          <Field label={`Height (${imp ? 'cm — switch units later in Settings' : 'cm'})`}><NumIn value={p.height} onChange={(v) => set('height', v)} suffix="cm" /></Field>
          <Field label="Current weight"><NumIn value={p.weight} step={0.5} onChange={(v) => set('weight', v)} suffix="kg" /></Field>
          <Field label="Target weight"><NumIn value={p.targetWeight} step={0.5} onChange={(v) => set('targetWeight', v)} suffix="kg" /></Field>
          <div className="info-card">BMI <b>{b.toFixed(1)}</b> · <span style={{ color: bmiClass(b, true).color }}>{bmiClass(b, true).label}</span><small>BMI is a screening measure only — it doesn't measure body fat or muscle.</small></div>
        </>}
        {step === 2 && <div className="opt-grid">
          {(Object.keys(GOALS) as Goal[]).map((g) => (
            <button key={g} className={'opt' + (p.goal === g ? ' on' : '')} onClick={() => set('goal', g)}><span>{GOALS[g].emoji}</span><b>{GOALS[g].label}</b></button>
          ))}
          <p className="muted small" style={{ gridColumn: '1/-1' }}>{GOALS[p.goal].note}</p>
        </div>}
        {step === 3 && <>
          <Field label="Experience"><Seg value={p.experience} onChange={(v) => set('experience', v)} options={[{ v: 'beginner', l: 'Beginner' }, { v: 'intermediate', l: 'Intermediate' }, { v: 'advanced', l: 'Advanced' }]} /></Field>
          <Field label="Daily activity">
            <div className="list-opts">{(Object.keys(ACTIVITY) as Activity[]).map((a) => <button key={a} className={p.activity === a ? 'on' : ''} onClick={() => set('activity', a)}><b>{ACTIVITY[a].label}</b><small>{ACTIVITY[a].desc}</small></button>)}</div>
          </Field>
          <Field label={`Training days per week: ${p.days}`}><input type="range" min={1} max={7} value={p.days} onChange={(e) => set('days', +e.target.value)} /></Field>
          <Field label={`Session length: ${p.minutes} min`}><input type="range" min={15} max={120} step={5} value={p.minutes} onChange={(e) => set('minutes', +e.target.value)} /></Field>
          <Field label="Equipment you can use">
            <div className="list-opts">{EQUIP.map((e) => <button key={e.key} className={p.equipment === e.key ? 'on' : ''} onClick={() => set('equipment', e.key as Equip)}><b>{e.name}</b><small>{e.desc}</small></button>)}</div>
          </Field>
        </>}
        {step === 4 && <>
          <Field label="Dietary preference"><div className="chips">{([['nonveg', 'Non-vegetarian'], ['eggetarian', 'Eggetarian'], ['vegetarian', 'Vegetarian'], ['vegan', 'Vegan'], ['pescatarian', 'Pescatarian']] as const).map(([v, l]) => <Chip key={v} on={p.diet === v} onClick={() => set('diet', v)}>{l}</Chip>)}</div></Field>
          <Field label="Food allergies or intolerances" hint="The coach avoids these in suggestions."><div className="chips">{ALLERGENS.map((a) => <Chip key={a} on={p.allergies.includes(a)} onClick={() => set('allergies', p.allergies.includes(a) ? p.allergies.filter((x) => x !== a) : [...p.allergies, a])}>{a}</Chip>)}</div></Field>
        </>}
        {step === 5 && <>
          <p className="muted">Optional. Progress photos are stored privately on this device and are never shared unless you post them yourself.</p>
          <div className="photo-row">
            {p.photos.map((id) => <PhotoThumb key={id} id={id} />)}
            <label className="photo-add"><Icon n="camera" /><span>Add photo</span>
              <input type="file" accept="image/*" hidden onChange={async (e) => { const f = e.target.files?.[0]; if (!f) return; try { const id = await putMedia(await processImage(f)); set('photos', [...p.photos, id]); } catch (x: any) { toast(x.message); } }} />
            </label>
          </div>
        </>}
        {step === 6 && <div className="plan-sum">
          <div className="plan-kcal"><small>Daily target</small><b>{t.kcal}</b><span>kcal</span></div>
          <div className="plan-macros">
            <div><b>{t.protein} g</b><small>Protein</small></div><div><b>{t.carbs} g</b><small>Carbs</small></div><div><b>{t.fat} g</b><small>Fat</small></div><div><b>{(t.water / 1000).toFixed(1)} L</b><small>Water</small></div>
          </div>
          <div className="plan-rows">
            <div><span>BMR (Mifflin-St Jeor)</span><b>{Math.round(t.bmr)} kcal</b></div>
            <div><span>Maintenance (TDEE)</span><b>{Math.round(t.tdee)} kcal</b></div>
            <div><span>Fibre</span><b>{t.fibre} g</b></div>
            <div><span>Recommended programme</span><b>{recommendProgram({ profile: p } as any).name}</b></div>
          </div>
          {t.notes.map((n, i) => <p key={i} className="muted small">• {n}</p>)}
          <p className="muted small">These are estimates. Adjust any target later in Nutrition → Targets. If you have a medical condition, are pregnant, or are under 18, check with a doctor before changing your diet.</p>
        </div>}
      </div>
      <div className="onb-cta">
        {step < steps.length - 1 ? <Btn full disabled={!ok} onClick={() => setStep(step + 1)}>{step === 5 && !p.photos.length ? 'Skip for now' : 'Continue'}</Btn> : <Btn full onClick={finish}>Start training</Btn>}
      </div>
    </div>
  );
}

function PhotoThumb({ id }: { id: string }) {
  const u = useMediaUrl(id);
  return <div className="photo-thumb" style={{ backgroundImage: u ? `url(${u})` : undefined }} />;
}
