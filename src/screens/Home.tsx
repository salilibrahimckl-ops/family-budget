import React from 'react';
import { useStore, update, uid, today, dayOffset } from '../lib/store';
import { dayTotals, userTargets, todaysPlan } from '../lib/coach';
import { Card, Ring, Bar, Icon, Header, Logo, go, Bars, Avatar, Pill, fmt } from '../ui';
import { useUnits, exById, isGymMode } from './common';
import { homeWorkoutFor } from '../data/homeWorkouts';
import { startWorkout } from './Train';
import { bmi, bmiClass } from '../lib/calc';
import { haptic, checkAchievements, t, toast } from '../lib/extras';
import { checkForUpdate, smartUpdate, isNativeApp, UpdateInfo } from '../lib/updater';
import { Btn } from '../ui';

import { StatusRow, FriendsBoard } from './Friends';
import { FriendChallengesHome } from './FriendChallenges';
import { burnFor } from '../lib/activity';

export function Home() {
  const s = useStore((x) => x);
  const p = s.profile!; const tg = userTargets(s); const tot = dayTotals(s); const u = useUnits();
  const unread = s.notifications.filter((n) => !n.read).length;
  const hr = new Date().getHours();
  const greet = hr < 12 ? 'Good morning' : hr < 17 ? 'Good afternoon' : 'Good evening';
  const burnt = burnFor(s).kcal;
  function addWater(ml: number) { haptic(); update((d) => { d.water.push({ id: uid(), date: today(), ts: Date.now(), ml }); }); checkAchievements(); toast(`+${ml} ml 💧`); }

  return (
    <div className="page home-simple">
      <Header big left={<Logo s={34} />} title={<>{greet}, {p.name.split(' ')[0]}</>} sub={new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long' })}
        right={<button className="icon-btn" onClick={() => go('/notifications')} aria-label="Notifications"><Icon n="bell" />{unread > 0 && <i className="badge">{unread > 9 ? '9+' : unread}</i>}</button>} />

      <TodayWorkout />

      <div className="today-tiles">
        <button onClick={() => go('/nutrition')}><Ring value={tot.kcal} max={tg.kcal} size={62} stroke={7}><span>🍽️</span></Ring><b>{fmt.n(tot.kcal)}</b><small>of {fmt.n(tg.kcal)} kcal eaten</small></button>
        <button onClick={() => go('/activity')}><Ring value={burnt} max={Math.max(300, Math.round(tg.kcal * 0.2))} size={62} stroke={7} color="var(--amber)"><span>🔥</span></Ring><b>{fmt.n(burnt)}</b><small>kcal burnt</small></button>
        <button onClick={() => addWater(250)}><Ring value={tot.water} max={tg.water} size={62} stroke={7} color="var(--sky)"><span>💧</span></Ring><b>{u.ml(tot.water)}</b><small>tap for +250 ml</small></button>
      </div>

      <div className="quick quick3">
        <button onClick={() => go('/food/add?mode=text')}><span><Icon n="food" s={20} /></span>Log food</button>
        <button onClick={() => go('/activity')}><span>🏸</span>Log sport</button>
        <button onClick={() => go('/body')}><span><Icon n="scale" s={20} /></span>Weight</button>
      </div>

      <UpdateBanner />
      <FriendChallengesHome />
      <StatusRow showAdd={false} />
      <FriendsBoard />
      <div style={{ height: 12 }} />
    </div>
  );
}

/** The one big thing on Home: today's workout (home workout unless the user trains at a gym). */
function TodayWorkout() {
  const s = useStore((x) => x);
  const gym = isGymMode(s);
  const tp = todaysPlan(s);
  const doneToday = s.workouts.some((w) => w.date === today());
  if (s.active) return <Card className="today-hero" onClick={() => go('/workout')}><span className="th-emoji">⏱️</span><div><small>Workout in progress</small><h2>{s.active.name}</h2></div><Btn full icon="play">Resume</Btn></Card>;
  const useGymPlan = gym && tp?.day;
  const hw = homeWorkoutFor();
  const name = useGymPlan ? tp!.day!.name : hw.name;
  const meta = useGymPlan ? `${tp!.day!.items.length} exercises · ${tp!.prog!.name}` : `${hw.minutes} min · no equipment · ${hw.items.length} exercises`;
  const start = () => (useGymPlan ? go('/workout/start/today') : startWorkout(hw.name, hw.items));
  return (
    <Card className="today-hero">
      <div className="row-b"><small className="lbl">{doneToday ? '✅ Done today — nice work!' : 'Today’s workout'}</small><button className="link" onClick={() => go('/train')}>More workouts</button></div>
      <div className="th-main"><span className="th-emoji">{useGymPlan ? '🏋️' : hw.emoji}</span><div><h2>{name}</h2><small className="muted">{meta}</small></div></div>
      {!useGymPlan && <div className="wo-ex">{hw.items.slice(0, 5).map((i) => <span key={i.id}>{exById(s, i.id)?.name}</span>)}</div>}
      <Btn full icon="play" onClick={start}>{doneToday ? 'Do another round' : 'Start workout'}</Btn>
    </Card>
  );
}

function Checklist() {
  const s = useStore((x) => x);
  if (s.settings.hideChecklist) return null;
  const items: [string, boolean, string, string][] = [
    ['Set up your profile', !!s.profile, '/edit-profile', ''],
    ['Watch an exercise demo', !!s.settings.watchedDemo, '/exercise/push-up', '1 min'],
    ['Log your first meal', s.meals.length > 0, '/food/add?mode=text', '30 sec'],
    ['Drink a glass of water', s.water.length > 0, '/water', '1 tap'],
    ['Finish your first workout', s.workouts.length > 0, '/train', ''],
    ['Ask the AI coach a question', s.coach.length > 0, '/coach', ''],
  ];
  const done = items.filter((i) => i[1]).length;
  if (done === items.length) return null;
  return (
    <Card className="checklist">
      <div className="row-b"><h3>Getting started · {done}/{items.length}</h3><button className="link muted" onClick={() => update((d) => { d.settings.hideChecklist = true; })}>Hide</button></div>
      <Bar value={done} max={items.length} />
      {items.map(([l, ok, to, hint]) => <button key={l} className={'check-item' + (ok ? ' done' : '')} onClick={() => !ok && go(to)}><i>{ok ? '✓' : ''}</i>{l}{!ok && <em>{hint || 'Go'} →</em>}</button>)}
    </Card>
  );
}

function UpdateBanner() {
  const [u, setU] = React.useState<UpdateInfo | null>(null); const [busy, setBusy] = React.useState('');
  React.useEffect(() => { if (isNativeApp()) checkForUpdate().then(setU).catch(() => {}); }, []);
  if (!u) return null;
  return <Card className="checklist"><div className="row-b"><div><b>Update available ✨</b><small className="muted" style={{ display: 'block' }}>{u.notes[0] || `Version 1.0.${u.build}`}</small></div>
    <Btn small disabled={!!busy} onClick={() => smartUpdate(u, setBusy).catch((e) => { toast(e.message); setBusy(''); })}>{busy || 'Update'}</Btn></div></Card>;
}
