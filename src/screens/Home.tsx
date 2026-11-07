import React from 'react';
import { useStore, update, uid, today, dayOffset } from '../lib/store';
import { dayTotals, userTargets, todaysPlan } from '../lib/coach';
import { Card, Ring, Bar, Icon, Header, Logo, go, Bars, Avatar, Pill, fmt } from '../ui';
import { useUnits, exById } from './common';
import { bmi, bmiClass } from '../lib/calc';
import { haptic, checkAchievements, t, toast } from '../lib/extras';
import { checkForUpdate, smartUpdate, isNativeApp, UpdateInfo } from '../lib/updater';
import { Btn } from '../ui';

import { StatusRow, FriendsBoard } from './Friends';
import { FriendChallengesHome } from './FriendChallenges';
import { BurnCard } from './Activity';
import { burnFor } from '../lib/activity';

export function Home() {
  const s = useStore((x) => x);
  const p = s.profile!; const tg = userTargets(s); const tot = dayTotals(s); const u = useUnits();
  const tp = todaysPlan(s);
  const unread = s.notifications.filter((n) => !n.read).length;
  const hr = new Date().getHours();
  const greet = hr < 12 ? 'Good morning' : hr < 17 ? 'Good afternoon' : 'Good evening';
  const week = Array.from({ length: 7 }, (_, i) => { const d = dayOffset(i - 6); return { x: new Date(d + 'T00:00').toLocaleDateString('en-IN', { weekday: 'narrow' }), y: s.workouts.filter((w) => w.date === d).length, d }; });
  const weekCount = week.reduce((a, w) => a + w.y, 0);
  const curW = s.weights.length ? s.weights[s.weights.length - 1].kg : p.weight;
  const startW = s.weights[0]?.kg ?? p.weight;
  const toGo = curW - p.targetWeight;
  const progress = startW === p.targetWeight ? 1 : Math.max(0, Math.min(1, (startW - curW) / (startW - p.targetWeight)));
  const b = bmi(curW, p.height); const bc = bmiClass(b, s.settings.asianBmi);
  const feed = s.social.posts.filter((x) => !x.removed && !s.social.blocks.includes(x.userId)).slice(0, 2);

  function addWater(ml: number) { haptic(); update((d) => { d.water.push({ id: uid(), date: today(), ts: Date.now(), ml }); }); checkAchievements(); }

  return (
    <div className="page">
      <Header big left={<Logo s={34} />} title={<>{greet}, {p.name.split(' ')[0]}</>} sub={new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long' })}
        right={<button className="icon-btn" onClick={() => go('/notifications')} aria-label="Notifications"><Icon n="bell" />{unread > 0 && <i className="badge">{unread > 9 ? '9+' : unread}</i>}</button>} />

      <div className="quick">
        <button onClick={() => go(s.active ? '/workout' : tp?.day ? '/workout/start/today' : '/train')}><span><Icon n="play" s={20} fill /></span>{s.active ? 'Resume' : 'Workout'}</button>
        <button onClick={() => go('/food/add?mode=text')}><span><Icon n="food" s={20} /></span>Log food</button>
        <button onClick={() => addWater(250)}><span><Icon n="drop" s={20} /></span>+ Water</button>
        <button onClick={() => go('/activity')}><span>🏸</span>Log sport</button>
      </div>

      <StatusRow showAdd={false} />
      <UpdateBanner />
      <FriendChallengesHome />
      <FriendsBoard />
      <Checklist />

      <Card className="hero-card" onClick={() => go('/nutrition')}>
        <div className="hero-rings">
          <Ring value={tot.kcal} max={tg.kcal} size={148} stroke={14}>
            <b className="ring-big">{fmt.n(Math.max(0, tg.kcal - tot.kcal))}</b><small>{tot.kcal > tg.kcal ? 'kcal over' : 'kcal left'}</small>
          </Ring>
          <div className="hero-macros">
            {[['Protein', tot.p, tg.protein, 'var(--lime)'], ['Carbs', tot.c, tg.carbs, 'var(--sky)'], ['Fat', tot.f, tg.fat, 'var(--amber)']].map(([l, v, m, c]) => (
              <div key={l as string} className="macro-line"><div><span>{t((l as string).toLowerCase())}</span><b>{Math.round(v as number)}<em>/{m as number} g</em></b></div><Bar value={v as number} max={m as number} color={c as string} /></div>
            ))}
          </div>
        </div>
        <div className="hero-foot"><span><Icon n="flame" s={14} /> {fmt.n(tot.kcal)} eaten · {fmt.n(burnFor(s).kcal)} burnt</span><span className="link">Log food →</span></div>
      </Card>

      <BurnCard />

      <div className="grid2">
        <Card className="water-card">
          <div className="row-b"><span className="lbl"><Icon n="drop" s={16} /> {t('water')}</span><button className="link" onClick={() => go('/water')}>Details</button></div>
          <div className="water-mini">
            <Ring value={tot.water} max={tg.water} size={84} stroke={9} color="var(--sky)"><b>{Math.round((tot.water / tg.water) * 100)}%</b></Ring>
            <div><b>{u.ml(tot.water)}</b><small>of {u.ml(tg.water)}</small></div>
          </div>
          <div className="water-btns"><button onClick={() => addWater(250)}>+250</button><button onClick={() => addWater(500)}>+500</button></div>
        </Card>
        <Card className="weight-card" onClick={() => go('/body')}>
          <span className="lbl"><Icon n="scale" s={16} /> Weight</span>
          <b className="big-num">{u.w(curW)}</b>
          <small>Goal {u.w(p.targetWeight)} · {Math.abs(toGo) < 0.1 ? 'reached 🎉' : `${u.w(Math.abs(toGo))} to ${toGo > 0 ? 'lose' : 'gain'}`}</small>
          <Bar value={progress} max={1} />
          <small className="bmi-mini">BMI {b.toFixed(1)} · <span style={{ color: bc.color }}>{bc.label}</span></small>
        </Card>
      </div>

      <Card className="today-wo" onClick={() => go(tp?.day ? '/workout/start/today' : '/train')}>
        <div className="row-b"><span className="lbl"><Icon n="train" s={16} /> Today's workout</span>{tp?.prog && <Pill tone="lime">{tp.prog.name}</Pill>}</div>
        {s.active ? <div className="wo-live"><b>Workout in progress</b><span>{s.active.name} · tap to resume</span></div>
          : tp?.day ? <>
            <h3>{tp.day.name}<span> · {tp.day.focus}</span></h3>
            <div className="wo-ex">{tp.day.items.slice(0, 4).map((i) => <span key={i.id}>{exById(s, i.id)?.name}</span>)}{tp.day.items.length > 4 && <span>+{tp.day.items.length - 4} more</span>}</div>
            <div className="wo-start"><Icon n="play" s={16} fill /> Start workout</div>
          </> : <><h3>{tp ? 'Rest & recover' : 'No plan yet'}</h3><p className="muted small">{tp ? 'Rest days build muscle. A 20–30 min walk or mobility session is ideal.' : 'Choose a programme to get a weekly schedule.'}</p></>}
      </Card>

      <Card>
        <div className="row-b"><span className="lbl"><Icon n="chart" s={16} /> This week</span><span className="muted small">{weekCount} workout{weekCount === 1 ? '' : 's'} · target {p.days}</span></div>
        <Bars data={week} height={110} goal={1} fmt={(v) => String(v)} />
      </Card>

      <div className="grid2">
        <Card onClick={() => go('/coach')} className="coach-card"><Icon n="spark" s={22} /><b>AI Coach</b><small>Ask about training, food & progress</small></Card>
        <Card onClick={() => go('/challenges')} className="chal-card"><Icon n="trophy" s={22} /><b>Challenges</b><small>{Object.keys(s.challenges).length ? `${Object.keys(s.challenges).length} active` : 'Join one today'}</small></Card>
      </div>

      <div className="row-b sec-h"><h3>Community</h3><button className="link" onClick={() => go('/community')}>See all</button></div>
      {feed.map((x) => {
        const usr = s.social.users.find((uu) => uu.id === x.userId) || (x.userId === p.userId ? { name: p.name, avatarColor: '#C6FF3D' } as any : null);
        return (
          <Card key={x.id} className="mini-post" onClick={() => go('/post/' + x.id)}>
            <Avatar name={usr?.name || '?'} color={usr?.avatarColor} size={34} />
            <div><b>{usr?.name}</b><p>{x.text.slice(0, 110)}{x.text.length > 110 ? '…' : ''}</p><small>{fmt.ago(x.ts)} · ♥ {x.likes + s.social.likes.filter((l) => l.postId === x.id).length}</small></div>
          </Card>
        );
      })}
      <div style={{ height: 12 }} />
    </div>
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
