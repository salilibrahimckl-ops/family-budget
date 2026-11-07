import React, { useEffect, useRef, useState } from 'react';
import { useStore, update, uid, putMedia, processImage, exportData, resetAll, getState, State, Profile as P, hashPw } from '../lib/store';
import { Header, BackBtn, Card, Btn, Chip, Seg, Icon, Pill, Sheet, Empty, go, back, Avatar, Field, NumIn, Toggle, fmt, Logo, Wordmark } from '../ui';
import { GOALS, ACTIVITY, Goal, Activity, bmi } from '../lib/calc';
import { EQUIP, Equip } from '../data/exercises';
import { toast, ACHIEVEMENTS, share, t } from '../lib/extras';
import { ask, askText } from '../lib/dialog';
import { localCoach, cloudCoach, userTargets, dayTotals, weeklyPlanText, recommendProgram, buildSchedule } from '../lib/coach';
import { cloudReady, isCloud, syncUp, pullFeed, cloudDeleteAccount, signOutCloud, BAKED } from '../lib/cloud';
import { SignInButtons, inPreview, WEB_APP_URL } from './Join';
import { useUnits } from './common';
import { notifyCfg, scheduleAll, requestPermission, remindersSupported, testNotification, DEFAULT_NOTIFY } from '../lib/reminders';
import { checkForUpdate, applyUpdate, currentBuild, needsNewApk, APK_URL, isNativeApp, UpdateInfo } from '../lib/updater';

export function Me() {
  const s = useStore((x) => x); const p = s.profile!; const u = useUnits();
  const tg = userTargets(s);
  const posts = s.social.posts.filter((x) => x.userId === p.userId).length;
  const followers = s.social.follows.filter((f) => f.to === p.userId && f.status === 'accepted').length;
  const following = s.social.follows.filter((f) => f.from === p.userId && f.status === 'accepted').length;
  const items: [string, string, string, string?][] = [
    ['user', 'My public profile', '/user/' + p.userId], ['edit', 'Edit fitness profile', '/edit-profile'], ['scale', 'Body, BMI & measurements', '/body'],
    ['food', 'Nutrition targets', '/targets'], ['trophy', 'Challenges & badges', '/challenges'], ['bookmark', 'Saved posts', '/bookmarks'],
    ['share', 'Invite friends (Android & iPhone)', '/invite'], ['spark', 'AI Coach', '/coach'], ['star', s.settings.plan === 'premium' ? 'Premium (active)' : 'Go Premium', '/premium'], ['gear', 'Settings & privacy', '/settings'],
  ];
  if (s.settings.admin) items.push(['shield', 'Admin dashboard', '/admin']);
  return (
    <div className="page">
      <Header big title={t('profile')} right={<button className="icon-btn" onClick={() => go('/settings')} aria-label="Settings"><Icon n="gear" /></button>} />
      <Card className="me-card">
        <AvatarEdit />
        <div><b>{p.name}</b><small>@{p.username}{s.settings.plan === 'premium' && ' · ⭐ Premium'}</small>
          <div className="me-stats"><span><b>{posts}</b> posts</span><span><b>{followers}</b> followers</span><span><b>{following}</b> following</span></div></div>
      </Card>
      <div className="ex-stats">
        <div><small>Goal</small><b>{GOALS[p.goal].emoji} {GOALS[p.goal].label.split(' ')[0]}</b></div><div><small>Weight</small><b>{u.w(p.weight)}</b></div>
        <div><small>BMI</small><b>{bmi(p.weight, p.height).toFixed(1)}</b></div><div><small>Target</small><b>{tg.kcal} kcal</b></div>
      </div>
      <div className="row-b sec-h"><h3>Progress</h3></div>
      <div className="ex-stats"><div><small>Workouts</small><b>{s.workouts.length}</b></div><div><small>PRs</small><b>{Object.keys(s.prs).length}</b></div><div><small>Badges</small><b>{Object.keys(s.achievements).length}/{ACHIEVEMENTS.length}</b></div><div><small>Days logged</small><b>{new Set(s.meals.map((m) => m.date)).size}</b></div></div>
      {s.settings.plan === 'premium' ? <Analytics s={s} /> : <Card className="pro-teaser" onClick={() => go('/premium')}><Icon n="chart" /><div><b>Advanced analytics</b><small>Volume per muscle, 1RM trends, adherence — Premium</small></div><Icon n="chev" s={18} /></Card>}
      {items.map(([ic, l, to]) => <Card key={to} className="list-row" onClick={() => go(to)}><Icon n={ic} s={20} /><b style={{ flex: 1 }}>{l}</b><Icon n="chev" s={18} /></Card>)}
      <Btn full kind="ghost" onClick={async () => { if (s.session?.email === 'guest' && !(await ask('You haven’t added an email and password yet, so you won’t be able to sign back in. Sign out anyway?'))) { go('/settings'); return; } update((d) => { d.session = null; }); location.hash = '#/'; }}>Sign out</Btn>
      <p className="muted small center">Bro’s Fitness 1.0.0 · {isCloud(s) ? 'Cloud sync' : 'On-device mode'}</p>
    </div>
  );
}

function Analytics({ s }: { s: State }) {
  const vol: Record<string, number> = {};
  const since = Date.now() - 28 * 864e5;
  for (const w of s.workouts) if (w.start > since) for (const e of w.entries) { const m = (require_ex(s, e.exId)) || 'other'; vol[m] = (vol[m] || 0) + e.sets.length; }
  const max = Math.max(1, ...Object.values(vol));
  const days = new Set(s.workouts.filter((w) => w.start > since).map((w) => w.date)).size;
  const adherence = Math.round((days / ((s.profile!.days / 7) * 28)) * 100);
  return <Card><span className="lbl">Last 4 weeks · sets per muscle</span>
    {Object.entries(vol).sort((a, b) => b[1] - a[1]).map(([m, v]) => <div key={m} className="an-row"><span>{m}</span><div className="bar"><i style={{ width: `${(v / max) * 100}%` }} /></div><b>{v}</b></div>)}
    {!Object.keys(vol).length && <p className="muted small">Log workouts to see volume by muscle.</p>}
    <p className="small">Training adherence: <b>{Math.min(100, adherence)}%</b> of planned days</p>
  </Card>;
}
import { exById } from './common';
const require_ex = (s: State, id: string) => exById(s, id)?.muscle;

function AvatarEdit() {
  const p = useStore((s) => s.profile)!;
  return <label className="av-edit"><Avatar name={p.name} media={p.avatar} size={72} /><span><Icon n="camera" s={14} /></span>
    <input type="file" accept="image/*" hidden onChange={async (e) => { const f = e.target.files?.[0]; if (!f) return; try { const id = await putMedia(await processImage(f)); update((d) => { d.profile!.avatar = id; }); toast('Profile photo updated'); } catch (x: any) { toast(x.message); } }} /></label>;
}

export function EditProfile() {
  const s = useStore((x) => x); const [p, setP] = useState<P>(s.profile!);
  const set = <K extends keyof P>(k: K, v: P[K]) => setP((x) => ({ ...x, [k]: v }));
  async function save() {
    if (p.name.trim().length < 2) return toast('Name is too short');
    const taken = s.social.users.some((u) => u.username === p.username && u.id !== p.userId);
    if (taken) return toast('That username is taken');
    const replan = p.days !== s.profile!.days || p.equipment !== s.profile!.equipment || p.goal !== s.profile!.goal || p.experience !== s.profile!.experience;
    const doReplan = replan && await ask('Your training settings changed. Update your weekly plan to match?');
    update((d) => { d.profile = p; if (doReplan) { const prog = recommendProgram({ ...d, profile: p }); d.plan = { programId: prog.id, schedule: buildSchedule(p.days, prog.days.length) }; } });
    toast('Profile saved'); back();
  }
  return <div className="page"><Header left={<BackBtn />} title="Edit profile" right={<Btn small onClick={save}>Save</Btn>} />
    <Card>
      <Field label="Name"><input value={p.name} onChange={(e) => set('name', e.target.value)} /></Field>
      <Field label="Username"><input value={p.username} onChange={(e) => set('username', e.target.value.toLowerCase().replace(/[^a-z0-9_.]/g, ''))} /></Field>
      <Field label="Bio"><textarea rows={2} value={p.bio} maxLength={160} onChange={(e) => set('bio', e.target.value)} /></Field>
    </Card>
    <Card>
      <div className="grid2"><Field label="Age"><NumIn value={p.age} onChange={(v) => set('age', Math.round(v))} w={44} /></Field><Field label="Sex"><Seg value={p.sex} onChange={(v) => set('sex', v)} options={[{ v: 'male', l: 'M' }, { v: 'female', l: 'F' }]} /></Field>
        <Field label="Height (cm)"><NumIn value={p.height} onChange={(v) => set('height', v)} w={52} /></Field><Field label="Weight (kg)"><NumIn value={p.weight} step={0.5} onChange={(v) => set('weight', v)} w={52} /></Field>
        <Field label="Target (kg)"><NumIn value={p.targetWeight} step={0.5} onChange={(v) => set('targetWeight', v)} w={52} /></Field><Field label="Days / week"><NumIn value={p.days} onChange={(v) => set('days', Math.min(7, Math.max(1, Math.round(v))))} w={36} /></Field></div>
      <Field label="Goal"><select value={p.goal} onChange={(e) => set('goal', e.target.value as Goal)}>{(Object.keys(GOALS) as Goal[]).map((g) => <option key={g} value={g}>{GOALS[g].label}</option>)}</select></Field>
      <Field label="Activity"><select value={p.activity} onChange={(e) => set('activity', e.target.value as Activity)}>{(Object.keys(ACTIVITY) as Activity[]).map((a) => <option key={a} value={a}>{ACTIVITY[a].label} — {ACTIVITY[a].desc}</option>)}</select></Field>
      <Field label="Experience"><Seg value={p.experience} onChange={(v) => set('experience', v)} options={[{ v: 'beginner', l: 'Beginner' }, { v: 'intermediate', l: 'Inter.' }, { v: 'advanced', l: 'Advanced' }]} /></Field>
      <Field label="Equipment"><select value={p.equipment} onChange={(e) => set('equipment', e.target.value as Equip)}>{EQUIP.map((q) => <option key={q.key} value={q.key}>{q.name}</option>)}</select></Field>
      <Field label="Diet"><select value={p.diet} onChange={(e) => set('diet', e.target.value as any)}>{[['nonveg', 'Non-vegetarian'], ['eggetarian', 'Eggetarian'], ['vegetarian', 'Vegetarian'], ['vegan', 'Vegan'], ['pescatarian', 'Pescatarian']].map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select></Field>
      <Field label="Allergies (comma separated)"><input value={p.allergies.join(', ')} onChange={(e) => set('allergies', e.target.value.split(',').map((x) => x.trim()).filter(Boolean))} /></Field>
    </Card>
  </div>;
}

function AccountCard() {
  const s = useStore((x) => x); const signed = isCloud(s);
  return <Card><span className="lbl">Account</span>
    {signed ? <>
      <div className="row-b"><span>Signed in as <b>{s.session!.email}</b></span></div>
      <p className="muted small">The same account works on all your phones — community, chat and backups.</p>
      <Btn small kind="soft" onClick={async () => { if (await ask('Sign out of the community on this phone? Your workouts and meals stay here.')) { signOutCloud(); toast('Signed out'); } }}>Sign out</Btn>
    </> : inPreview() ? <p className="muted small">Open the full app at {WEB_APP_URL} to sign in.</p> : <>
      <p className="muted small">Sign in once with Google or your email to back up your profile and join the community. No new password.</p>
      <SignInButtons />
    </>}
  </Card>;
}

export function Settings() {
  const s = useStore((x) => x); const st = s.settings; const p = s.profile!;
  const [url, setUrl] = useState(st.supabaseUrl); const [key, setKey] = useState(st.supabaseAnon); const [syncing, setSyncing] = useState(false);
  const setS = (fn: (d: State) => void) => update(fn);
  return <div className="page"><Header left={<BackBtn />} title="Settings" />
    {cloudReady() ? <AccountCard /> : s.session?.email === 'guest' && <SaveAccount />}
    <Card><span className="lbl">Appearance & units</span>
      <Field label="Theme"><Seg value={st.theme} onChange={(v) => setS((d) => { d.settings.theme = v; })} options={[{ v: 'dark', l: '🌙 Dark' }, { v: 'light', l: '☀️ Light' }]} /></Field>
      <Field label="Units"><Seg value={st.units} onChange={(v) => setS((d) => { d.settings.units = v; })} options={[{ v: 'metric', l: 'Metric (kg, cm, ml)' }, { v: 'imperial', l: 'Imperial (lb, in, oz)' }]} /></Field>
      <Field label="Language" hint="Malayalam is partially translated — more coming."><Seg value={st.lang} onChange={(v) => setS((d) => { d.settings.lang = v; })} options={[{ v: 'en', l: 'English' }, { v: 'ml', l: 'മലയാളം (beta)' }]} /></Field>
    </Card>
    <UpdatesCard />
    <RemindersCard />
    <Card><span className="lbl">Privacy</span>
      <Toggle on={p.private} onChange={(v) => setS((d) => { d.profile!.private = v; })} label="Private account" desc="Only followers you approve can see your posts" />
      <Toggle on={p.showStats} onChange={(v) => setS((d) => { d.profile!.showStats = v; })} label="Show body stats on profile" desc="Off by default. Weight, BMI and measurements stay private." />
      <Toggle on={p.leaderboard} onChange={(v) => setS((d) => { d.profile!.leaderboard = v; })} label="Appear on challenge leaderboards" />
      {s.social.blocks.length > 0 && <Field label="Blocked accounts">{s.social.blocks.map((b) => { const u = s.social.users.find((x) => x.id === b); return <div key={b} className="row-b"><span>@{u?.username || b}</span><button className="link" onClick={() => setS((d) => { d.social.blocks = d.social.blocks.filter((x) => x !== b); })}>Unblock</button></div>; })}</Field>}
    </Card>
    <Card><span className="lbl">Advanced: community server</span>
      <p className="muted small">{BAKED.url ? 'Built in — nothing to set up. Only change this if you run your own Supabase server.' : 'Paste your Supabase project URL and anon public key (never the service-role key) to turn on the shared community and chat.'}</p>
      <Field label="Project URL"><input value={url} onChange={(e) => setUrl(e.target.value.trim())} placeholder="https://xxxx.supabase.co" /></Field>
      <Field label="Anon public key"><input value={key} onChange={(e) => setKey(e.target.value.trim())} placeholder="eyJhbGciOi…" /></Field>
      <div className="row"><Btn kind="soft" onClick={() => { if (url && !/^https:\/\/.+/.test(url)) return toast('URL must start with https://'); setS((d) => { d.settings.supabaseUrl = url; d.settings.supabaseAnon = key; }); toast(url ? 'Saved. Sign out and sign in with a cloud account.' : 'Cloud disabled'); }}>Save</Btn>
        {isCloud(s) && <Btn disabled={syncing} onClick={async () => { setSyncing(true); try { await syncUp(); await pullFeed(); toast('Synced ✓'); } catch (e: any) { toast('Sync failed: ' + e.message); } setSyncing(false); }}>{syncing ? 'Syncing…' : 'Sync now'}</Btn>}</div>
      <small className="muted">Status: {isCloud(s) ? `signed in to cloud as ${s.session!.email}` : cloudReady() ? 'configured — sign in with a cloud account' : 'on-device only'}</small>
    </Card>
    <Card><span className="lbl">Your data</span>
      <Btn full kind="soft" icon="share" onClick={async () => { const json = exportData(); const blob = new Blob([json], { type: 'application/json' }); const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `fitverse-export-${new Date().toISOString().slice(0, 10)}.json`; a.click(); if ((window as any).Capacitor?.isNativePlatform?.()) share(json.slice(0, 20000), 'Bro’s Fitness data export'); toast('Export created'); }}>Export my data (JSON)</Btn>
      <div style={{ height: 8 }} />
      <Btn full kind="danger" icon="trash" onClick={async () => {
        if (!await ask('Delete your account and ALL data (profile, logs, photos, posts)? This cannot be undone.')) return;
        if (isCloud(s)) { try { await cloudDeleteAccount(); } catch (e: any) { if (!await ask('Cloud deletion failed (' + e.message + '). Delete local data anyway?')) return; } }
        const email = s.session?.email; update((d) => { d.accounts = d.accounts.filter((a) => a.email !== email); });
        const keepAccounts = getState().accounts; resetAll(); update((d) => { d.accounts = keepAccounts; d.settings.seenIntro = true; }); location.hash = '#/';
      }}>Delete account</Btn>
    </Card>
    <Card><span className="lbl">Health & safety</span><p className="muted small">Bro’s Fitness provides general fitness and nutrition information, not medical advice. Consult a doctor before starting a new programme if you are pregnant, have a heart, kidney, metabolic or musculoskeletal condition, or are recovering from injury or surgery. Stop exercising and seek care if you feel chest pain, faintness or severe breathlessness.</p></Card>
    <Card><span className="lbl">About</span><div className="row"><Logo s={40} /><div><Wordmark size={16} /><small className="muted"> v1.0.0</small></div></div>
      <p className="muted small">Food data: IFCT 2017 (NIN, Hyderabad) and USDA FoodData Central averages; barcode data from Open Food Facts (ODbL). Formulas: Mifflin-St Jeor (1990), Epley 1RM, WHO & Asian-Indian BMI cut-offs.</p>
      <Toggle on={st.admin} onChange={(v) => setS((d) => { d.settings.admin = v; })} label="Admin tools on this device" desc="In cloud mode admin rights come from the server (profiles.is_admin)." /></Card>
  </div>;
}

export function Premium() {
  const s = useStore((x) => x); const on = s.settings.plan === 'premium';
  const feats = [['spark', 'Cloud AI coach (LLM)', 'Open-ended answers with your full context'], ['calendar', 'Advanced personalised plans', 'Muscle-Building Programme & more'], ['chart', 'Advanced analytics', 'Volume per muscle, adherence, 1RM trends'], ['food', 'Detailed nutrition recommendations', 'Meal ideas from your remaining macros'], ['video', 'Premium exercise videos', 'When licensed videos are uploaded'], ['trophy', 'Exclusive programmes', 'New plans added from the admin dashboard']];
  return <div className="page"><Header left={<BackBtn />} title="Bro’s Fitness Premium" />
    <div className="pro-hero"><Logo s={64} /><h2>Train smarter with Premium</h2><p className="muted">Everything in Free — exercise library, workout tracker, BMI, nutrition & water tracking, and the community — stays free.</p></div>
    {feats.map(([i, t1, d]) => <Card key={t1} className="list-row"><Icon n={i} /><div><b>{t1}</b><small>{d}</small></div></Card>)}
    <Card><p className="small"><b>Billing is not connected in this version.</b> The app is built to plug in Google Play Billing and Apple In-App Purchases later (see docs/MONETISATION.md). For now you can preview Premium features for free.</p>
      <Btn full kind={on ? 'soft' : 'primary'} onClick={() => { update((d) => { d.settings.plan = on ? 'free' : 'premium'; }); toast(on ? 'Back to Free' : 'Premium preview on ⭐'); }}>{on ? 'Turn off Premium preview' : 'Start free Premium preview'}</Btn></Card>
  </div>;
}

export function Coach() {
  const s = useStore((x) => x);
  const [q, setQ] = useState(''); const [busy, setBusy] = useState(false);
  const [mode, setMode] = useState<'device' | 'cloud'>('device');
  const end = useRef<HTMLDivElement>(null);
  useEffect(() => { end.current?.scrollIntoView({ behavior: 'smooth' }); }, [s.coach.length, busy]);
  const chips = ['What should I train today?', 'How much protein do I need?', 'Am I eating enough calories?', 'Which exercise targets my upper chest?', 'What is the alternative to leg press?', 'How can I reduce body fat while maintaining muscle?', 'Suggest a healthy high-protein dinner', 'Make me a weekly plan'];
  async function ask(text: string) {
    const t1 = text.trim(); if (!t1) return; setQ('');
    update((d) => { d.coach.push({ role: 'user', text: t1, ts: Date.now() }); });
    setBusy(true);
    let a: string;
    try { a = mode === 'cloud' ? await cloudCoach(getState(), t1) : localCoach(getState(), t1); }
    catch (e: any) { a = `${e.message}\n\nOn-device answer instead:\n\n` + localCoach(getState(), t1); }
    await new Promise((r) => setTimeout(r, mode === 'device' ? 350 : 0));
    update((d) => { d.coach.push({ role: 'coach', text: a, ts: Date.now() }); d.coach = d.coach.slice(-60); });
    setBusy(false);
  }
  const canCloud = isCloud(s) && s.settings.plan === 'premium';
  return <div className="page coach-page">
    <Header left={<BackBtn />} title="AI Coach" sub={mode === 'device' ? 'On-device · uses your data' : 'Cloud LLM'} right={s.coach.length > 0 && <button className="icon-btn" onClick={() => update((d) => { d.coach = []; })} aria-label="Clear"><Icon n="trash" /></button>} />
    <Seg value={mode} onChange={(v) => { if (v === 'cloud' && !canCloud) { toast(isCloud(s) ? 'Cloud coach is a Premium feature' : 'Cloud coach needs Supabase + the coach Edge Function (see docs). Using on-device coach.'); return; } setMode(v); }} options={[{ v: 'device', l: 'On-device coach' }, { v: 'cloud', l: '☁️ Cloud AI (Premium)' }]} />
    <div className="chat">
      {!s.coach.length && <Card className="coach-intro"><Icon n="spark" s={28} /><b>Hi {s.profile!.name.split(' ')[0]}! I'm your coach.</b><p className="muted small">I know your goal, targets, today's food and your workout history. I don't diagnose medical conditions or recommend extreme diets.</p></Card>}
      {s.coach.map((m, i) => <div key={i} className={'msg ' + m.role}>{m.text.split('\n').map((l, k) => <p key={k} dangerouslySetInnerHTML={{ __html: esc(l).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>') }} />)}</div>)}
      {busy && <div className="msg coach typing"><i /><i /><i /></div>}
      <div ref={end} />
    </div>
    <div className="chips scroll">{chips.map((c) => <Chip key={c} onClick={() => ask(c)}>{c}</Chip>)}</div>
    {s.coach.length > 0 && /weekly plan/i.test(s.coach[s.coach.length - 1]?.text || '') && <Btn full kind="soft" onClick={() => { const prog = recommendProgram(s); update((d) => { d.plan = { programId: prog.id, schedule: buildSchedule(d.profile!.days, prog.days.length) }; }); toast(`${prog.name} applied to your calendar`); }}>Apply plan</Btn>}
    <div className="cmt-box"><div className="row"><input value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && ask(q)} placeholder="Ask your coach…" /><button className="send" onClick={() => ask(q)} aria-label="Send"><Icon n="send" s={18} /></button></div></div>
  </div>;
}
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function SaveAccount() {
  const [email, setEmail] = useState(''); const [pw, setPw] = useState('');
  async function save() {
    const em = email.trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(em)) return toast('Enter a valid email');
    if (pw.length < 8 || !/\d/.test(pw) || !/[a-z]/i.test(pw)) return toast('Password: 8+ characters with letters and numbers');
    if (getState().accounts.some((a) => a.email === em)) return toast('That email is already used on this device');
    const salt = uid() + uid(); const hash = await hashPw(pw, salt);
    update((d) => { const a = d.accounts.find((x) => x.userId === d.session!.userId); if (a) Object.assign(a, { email: em, salt, hash }); d.session!.email = em; });
    toast('Account saved — you can now sign in with this email');
  }
  return <Card className="checklist"><span className="lbl">Protect your progress</span>
    <p className="muted small">You started without signing up. Add an email and password so you can sign back in later.</p>
    <Field label="Email"><input type="email" value={email} onChange={(e) => setEmail(e.target.value)} /></Field>
    <Field label="Password"><input type="password" value={pw} onChange={(e) => setPw(e.target.value)} /></Field>
    <Btn full onClick={save}>Save my account</Btn></Card>;
}

function RemindersCard() {
  const s = useStore((x) => x); const cfg = notifyCfg(s); const r = s.settings.reminders;
  const supported = remindersSupported();
  async function set(patch: Partial<typeof cfg>, water?: Partial<typeof r>) {
    if (supported && !(await requestPermission())) { toast('Allow notifications in phone Settings → Apps → Bro’s Fitness → Notifications.'); return; }
    update((d) => { d.settings.notify = { ...notifyCfg(d), ...patch }; if (water) Object.assign(d.settings.reminders, water); });
    if (supported) scheduleAll();
  }
  const time = (v: string, on: (t: string) => void) => <input type="time" value={v} onChange={(e) => on(e.target.value)} style={{ width: 120 }} />;
  return <Card><span className="lbl">Reminders & nudges</span>
    {!supported && <p className="muted small">Notifications work in the Android app. (Web browsers on iPhone can’t schedule reminders.)</p>}
    <Toggle on={cfg.workout} onChange={(v) => set({ workout: v })} label="Workout reminders" desc={`On training days at ${cfg.workoutTime}, plus a 9 pm push if it’s not done`} />
    {cfg.workout && <div className="row">Remind me at {time(cfg.workoutTime, (t) => set({ workoutTime: t }))}</div>}
    <Toggle on={cfg.meals} onChange={(v) => set({ meals: v })} label="Meal logging reminders" desc="Only if that meal isn’t logged yet" />
    {cfg.meals && <div className="times-grid"><label><small>🍳 Breakfast</small>{time(cfg.times[0], (t) => set({ times: [t, cfg.times[1], cfg.times[2]] }))}</label><label><small>🍛 Lunch</small>{time(cfg.times[1], (t) => set({ times: [cfg.times[0], t, cfg.times[2]] }))}</label><label><small>🌙 Dinner</small>{time(cfg.times[2], (t) => set({ times: [cfg.times[0], cfg.times[1], t] }))}</label></div>}
    <Toggle on={r.water} onChange={(v) => set({}, { water: v })} label="Water reminders" desc={`Every ${r.every} min between ${r.from}:00 and ${r.to}:00`} />
    {r.water && <div className="chips">{[60, 90, 120, 180].map((m) => <Chip key={m} on={r.every === m} onClick={() => set({}, { every: m })}>Every {m >= 120 ? m / 60 + ' h' : m + ' min'}</Chip>)}</div>}
    <Toggle on={cfg.nudges} onChange={(v) => set({ nudges: v })} label="Progress nudges" desc="Protein gap, falling behind on water, nothing logged yet" />
    {supported && <Btn full kind="soft" icon="bell" onClick={async () => toast((await testNotification()) ? 'Test notification in 3 seconds…' : 'Notifications are blocked in phone settings')}>Send a test notification</Btn>}
  </Card>;
}

export function UpdatesCard({ compact }: { compact?: boolean }) {
  const [info, setInfo] = useState<UpdateInfo | null | undefined>(undefined);
  const [busy, setBusy] = useState(''); const native = isNativeApp();
  async function check() { setBusy('Checking…'); try { const u = await checkForUpdate(); setInfo(u); if (!u) toast('You’re on the latest version ✓'); } catch (e: any) { toast(e.message); } setBusy(''); }
  async function install() { if (!info) return; try { await applyUpdate(setBusy); } catch (e: any) { toast(e.message); setBusy(''); } }
  if (!native) return compact ? null : <Card><span className="lbl">App updates</span><p className="muted small">This web version updates automatically — just reopen the link.</p></Card>;
  return <Card className={info ? 'checklist' : ''}><span className="lbl">App updates</span>
    <p className="small">Version 1.0.{currentBuild()}</p>
    {info && <><p><b>New version 1.0.{info.build} is ready</b></p><ul className="cue small">{info.notes.map((n, i) => <li key={i}>{n}</li>)}</ul></>}
    {info && needsNewApk(info) ? <><p className="muted small">This update adds new phone features, so it needs a one-time reinstall.</p><a className="btn primary full" href={APK_URL}>Download update</a></>
      : info ? <Btn full disabled={!!busy} onClick={install}>{busy || 'Update now'}</Btn>
        : <Btn full kind="soft" disabled={!!busy} onClick={check}>{busy || 'Check for updates'}</Btn>}
  </Card>;
}
