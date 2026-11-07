// Quick 3-step setup. Everything else gets sensible defaults and can be changed later in Profile → Edit.
import React, { useState } from 'react';
import { update, useStore, Profile, today } from '../lib/store';
import { GOALS, Goal, targets, bmi, bmiClass, Activity } from '../lib/calc';
import { Equip } from '../data/exercises';
import { Btn, Field, Seg, Icon, NumIn } from '../ui';
import { recommendProgram, buildSchedule } from '../lib/coach';
import { toast } from '../lib/extras';

const PLACES: { k: Equip; e: string; l: string; d: string }[] = [
  { k: 'gym', e: '🏢', l: 'At a gym', d: 'Machines, cables, barbells' },
  { k: 'dumbbells', e: '🏠', l: 'At home with dumbbells', d: 'Or a few weights' },
  { k: 'none', e: '🤸', l: 'At home, no equipment', d: 'Bodyweight only' },
];
const QUICK_GOALS: Goal[] = ['fatloss', 'muscle', 'general', 'recomp', 'strength', 'maintain'];

export function Onboarding() {
  const session = useStore((s) => s.session)!;
  const [step, setStep] = useState(0);
  const [p, setP] = useState<Profile>({
    userId: session.userId, name: '', username: '', age: 25, sex: 'male', height: 170, weight: 70, targetWeight: 65,
    experience: 'beginner', activity: 'light', days: 3, minutes: 45, goal: 'fatloss', equipment: 'gym', diet: 'nonveg', allergies: [],
    photos: [], bio: '', private: false, showStats: false, leaderboard: true, createdAt: Date.now(),
  });
  const set = <K extends keyof Profile>(k: K, v: Profile[K]) => setP((x) => ({ ...x, [k]: v }));
  const activityFor = (d: number): Activity => (d <= 2 ? 'light' : d <= 4 ? 'moderate' : 'very');
  const titles = ['Hi! What should we call you?', 'Your body', 'What’s your goal?', 'Your plan is ready'];
  const ok = [p.name.trim().length > 0 && p.age >= 13 && p.age <= 100, p.height > 100 && p.weight > 25 && p.targetWeight > 25, true, true][step];
  const final = { ...p, activity: activityFor(p.days) };
  const t = targets({ sex: final.sex, weight: final.weight, height: final.height, age: final.age, activity: final.activity, goal: final.goal, trainingDays: final.days });
  const b = bmi(p.weight, p.height);
  const prog = recommendProgram({ profile: final } as any);

  function finish() {
    const username = (p.name).toLowerCase().replace(/[^a-z0-9_.]/g, '').slice(0, 16) + Math.floor(Math.random() * 90 + 10);
    update((d) => {
      d.profile = { ...final, username, name: p.name.trim() };
      d.weights = [{ date: today(), kg: p.weight }];
      d.plan = { programId: prog.id, schedule: buildSchedule(p.days, prog.days.length) };
    });
    toast(`Welcome, ${p.name.split(' ')[0]}! 💪`);
    location.hash = '#/home';
  }

  return (
    <div className="onb">
      <div className="onb-top">
        {step > 0 ? <button className="icon-btn" onClick={() => setStep(step - 1)} aria-label="Back"><Icon n="back" /></button> : <span style={{ width: 40 }} />}
        <div className="onb-prog"><i style={{ width: `${((step + 1) / titles.length) * 100}%` }} /></div>
        <span className="onb-count">{step + 1}/{titles.length}</span>
      </div>
      <h2 className="onb-title">{titles[step]}</h2>
      <div className="onb-body">
        {step === 0 && <>
          <Field label="Your first name"><input value={p.name} onChange={(e) => set('name', e.target.value)} placeholder="e.g. Salil" autoFocus onKeyDown={(e) => e.key === 'Enter' && ok && setStep(1)} /></Field>
          <Field label="Age"><NumIn value={p.age} onChange={(v) => set('age', Math.round(v))} suffix="yrs" /></Field>
          <Field label="Sex" hint="Only used to estimate your calorie needs."><Seg value={p.sex} onChange={(v) => set('sex', v)} options={[{ v: 'male', l: '♂ Male' }, { v: 'female', l: '♀ Female' }]} /></Field>
        </>}
        {step === 1 && <>
          <Field label={`Height: ${p.height} cm`}><input type="range" min={130} max={210} value={p.height} onChange={(e) => set('height', +e.target.value)} /></Field>
          <Field label="Current weight"><NumIn value={p.weight} step={0.5} onChange={(v) => set('weight', v)} suffix="kg" /></Field>
          <Field label="Goal weight"><NumIn value={p.targetWeight} step={0.5} onChange={(v) => set('targetWeight', v)} suffix="kg" /></Field>
          <div className="info-card">Your BMI is <b>&nbsp;{b.toFixed(1)}&nbsp;</b> <span style={{ color: bmiClass(b, true).color }}>({bmiClass(b, true).label})</span><small>BMI is only a rough screening number — it can’t tell muscle from fat.</small></div>
        </>}
        {step === 2 && <>
          <div className="opt-grid">
            {QUICK_GOALS.map((g) => <button key={g} className={'opt' + (p.goal === g ? ' on' : '')} onClick={() => set('goal', g)}><span>{GOALS[g].emoji}</span><b>{GOALS[g].label}</b></button>)}
          </div>
          <h4 className="sec-h">Where will you train?</h4>
          <div className="list-opts">{PLACES.map((x) => <button key={x.k} className={p.equipment === x.k ? 'on' : ''} onClick={() => set('equipment', x.k)}><b>{x.e} {x.l}</b><small>{x.d}</small></button>)}</div>
          <h4 className="sec-h">Days per week</h4>
          <div className="day-pick">{[2, 3, 4, 5, 6].map((n) => <button key={n} className={p.days === n ? 'on' : ''} onClick={() => set('days', n)}>{n}</button>)}</div>
        </>}
        {step === 3 && <div className="plan-sum">
          <div className="plan-kcal"><small>Eat about</small><b>{t.kcal}</b><span>calories a day</span></div>
          <div className="plan-macros">
            <div><b>{t.protein} g</b><small>Protein</small></div><div><b>{t.carbs} g</b><small>Carbs</small></div><div><b>{t.fat} g</b><small>Fat</small></div><div><b>{(t.water / 1000).toFixed(1)} L</b><small>Water</small></div>
          </div>
          <div className="plan-rows">
            <div><span>Your workout plan</span><b>{prog.name}</b></div>
            <div><span>Training days</span><b>{p.days} per week</b></div>
          </div>
          <p className="muted small">These are starting estimates — you can fine-tune everything later in Profile. If you have a medical condition or are pregnant, check with your doctor first.</p>
        </div>}
      </div>
      <div className="onb-cta">
        {step < 3 ? <Btn full disabled={!ok} onClick={() => setStep(step + 1)}>Continue</Btn> : <Btn full onClick={finish}>Let’s go 🚀</Btn>}
      </div>
    </div>
  );
}
