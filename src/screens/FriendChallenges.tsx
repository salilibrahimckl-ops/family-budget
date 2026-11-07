// Challenge friends: pick people, what counts (calories / active minutes / sessions) and how long. Live ranking.
import React, { useEffect, useState } from 'react';
import { useStore, getState, today, dayOffset } from '../lib/store';
import { Header, BackBtn, Card, Btn, Chip, Avatar, Sheet, Field, Empty, go, fmt } from '../ui';
import { isCloud, myFriendChallenges, createFriendChallenge, respondChallenge, pushChallengeProgress, deleteFriendChallenge, searchPeople, sendMessage, FChallenge, Metric } from '../lib/cloud';
import { metricBetween } from '../lib/activity';
import { userOf } from './Social';
import { JoinCard } from './Join';
import { toast } from '../lib/extras';
import { ask } from '../lib/dialog';

const METRICS: { v: Metric; l: string; unit: string; emoji: string }[] = [
  { v: 'kcal', l: 'Most calories burnt', unit: 'kcal', emoji: '🔥' },
  { v: 'minutes', l: 'Most active minutes', unit: 'min', emoji: '⏱️' },
  { v: 'sessions', l: 'Most workouts & sports', unit: 'sessions', emoji: '🏋️' },
];
const mInfo = (m: Metric) => METRICS.find((x) => x.v === m)!;
const daysLeft = (end: string) => Math.max(0, Math.round((new Date(end + 'T23:59:59').getTime() - Date.now()) / 864e5));
const ended = (c: FChallenge) => c.end < today();

// shared cache so Home and the Challenges page don't refetch constantly
let cache: FChallenge[] | null = null; const subs = new Set<() => void>();
export async function refreshFriendChallenges() {
  const s = getState(); if (!isCloud(s)) return [];
  const list = await myFriendChallenges();
  // send my latest progress for running challenges I joined
  const me = s.profile!.userId;
  for (const c of list) {
    const m = c.members.find((x) => x.userId === me);
    if (!m || m.status !== 'accepted' || today() < c.start) continue;
    const v = metricBetween(getState(), c.metric, c.start, c.end);
    if (v !== m.progress && !(ended(c) && Date.now() - m.updated > 2 * 864e5)) { try { await pushChallengeProgress(c.id, v); m.progress = v; m.updated = Date.now(); } catch { /* */ } }
  }
  cache = list; subs.forEach((f) => f());
  return list;
}
function useFC() {
  const [, force] = useState(0); const [err, setErr] = useState('');
  useEffect(() => { const f = () => force((x) => x + 1); subs.add(f); refreshFriendChallenges().catch((e) => setErr(/schema cache|does not exist/i.test(e.message) ? 'setup' : e.message)); const t = setInterval(() => refreshFriendChallenges().catch(() => undefined), 60e3); return () => { subs.delete(f); clearInterval(t); }; }, []);
  return { list: cache, err };
}

/** Section on the Challenges page + invites. */
export function FriendChallengesSection() {
  const s = useStore((x) => x); const signed = isCloud(s);
  const { list, err } = useFC();
  const [create, setCreate] = useState(false);
  if (!signed) return <JoinCard title="Challenge your friends" text="Sign in to challenge friends — most calories, active minutes or workouts in a few days." />;
  const me = s.profile!.userId;
  const invites = (list || []).filter((c) => c.members.find((m) => m.userId === me)?.status === 'invited' && !ended(c));
  const active = (list || []).filter((c) => c.members.find((m) => m.userId === me)?.status === 'accepted');
  return <>
    <div className="row-b sec-h"><h3>Friend challenges</h3><Btn small onClick={() => setCreate(true)}>+ Challenge friends</Btn></div>
    {err === 'setup' && <Card><p className="muted small" style={{ margin: 0 }}>Friend challenges are almost ready — the app owner needs to run one short setup step on the server.</p></Card>}
    {err && err !== 'setup' && <p className="muted small">{err}</p>}
    {invites.map((c) => <InviteCard key={c.id} c={c} />)}
    {active.map((c) => <FCCard key={c.id} c={c} />)}
    {list && !invites.length && !active.length && !err && <Card className="fc-empty" onClick={() => setCreate(true)}><span>🤜🤛</span><div><b>Challenge a friend</b><small>Who burns more calories this week? Pick friends and start.</small></div></Card>}
    <CreateChallenge open={create} onClose={() => setCreate(false)} />
  </>;
}

function InviteCard({ c }: { c: FChallenge }) {
  const s = getState(); const by = userOf(s, c.creator); const mi = mInfo(c.metric);
  const [busy, setBusy] = useState(false);
  async function act(st: 'accepted' | 'declined') { setBusy(true); try { await respondChallenge(c.id, st); toast(st === 'accepted' ? 'Challenge accepted 💪' : 'Declined'); await refreshFriendChallenges(); } catch (e: any) { toast(e.message); } setBusy(false); }
  return <Card className="fc-invite">
    <div className="row" style={{ gap: 10 }}><Avatar name={by?.name || '?'} color={by?.avatarColor} src={by?.photo} size={40} /><div style={{ flex: 1 }}><b>{by?.name || 'A friend'} challenged you!</b><small className="muted" style={{ display: 'block' }}>{mi.emoji} {c.title} · {fmtRange(c)}</small></div></div>
    <div className="row" style={{ gap: 8, marginTop: 10 }}><Btn full disabled={busy} onClick={() => act('accepted')}>Accept</Btn><Btn full kind="soft" disabled={busy} onClick={() => act('declined')}>Decline</Btn></div>
  </Card>;
}

const fmtRange = (c: FChallenge) => { const f = (d: string) => new Date(d + 'T12:00:00').toLocaleDateString([], { day: 'numeric', month: 'short' }); return ended(c) ? 'ended ' + f(c.end) : today() < c.start ? 'starts ' + f(c.start) : daysLeft(c.end) === 0 ? 'last day!' : daysLeft(c.end) + ' days left'; };

function ranking(c: FChallenge) {
  const s = getState(); const me = s.profile!.userId;
  return c.members.filter((m) => m.status !== 'declined').map((m) => ({ ...m, progress: m.userId === me && today() >= c.start ? metricBetween(s, c.metric, c.start, c.end) : m.progress })).sort((a, b) => (b.status === 'accepted' ? 1 : 0) - (a.status === 'accepted' ? 1 : 0) || b.progress - a.progress);
}

function FCCard({ c }: { c: FChallenge }) {
  const s = useStore((x) => x); const me = s.profile!.userId; const mi = mInfo(c.metric);
  const rows = ranking(c); const top = Math.max(1, ...rows.map((r) => r.progress));
  const leader = rows[0]; const done = ended(c);
  return <Card className="fc-card" onClick={() => go('/fchallenge/' + c.id)}>
    <div className="row-b"><b>{mi.emoji} {c.title}</b><small className={done ? 'muted' : 'fc-left'}>{fmtRange(c)}</small></div>
    {done && leader && <p className="fc-win">🏆 {leader.userId === me ? 'You won!' : (userOf(s, leader.userId)?.name || 'Friend') + ' won'}</p>}
    {rows.slice(0, 4).map((r, i) => { const u = r.userId === me ? { name: 'You', avatarColor: '#C6FF3D', photo: undefined } : userOf(s, r.userId); return (
      <div key={r.userId} className={'board-row' + (r.userId === me ? ' me' : '')}>
        <span className="rank">{r.status === 'invited' ? '⏳' : i < 3 ? ['🥇', '🥈', '🥉'][i] : i + 1}</span>
        <Avatar name={u?.name || '?'} color={u?.avatarColor} src={(u as any)?.photo} media={r.userId === me ? s.profile!.avatar : undefined} size={30} />
        <div className="board-mid"><b>{u?.name || 'Member'}{r.status === 'invited' ? ' · invited' : ''}</b><i style={{ width: Math.max(4, (r.progress / top) * 100) + '%' }} /></div>
        <span className="board-val">{fmt.n(r.progress)}<small> {mi.unit}</small></span>
      </div>); })}
  </Card>;
}

export function FriendChallengeDetail({ id }: { id: string }) {
  const s = useStore((x) => x); const { list } = useFC();
  const c = (list || []).find((x) => x.id === id);
  if (!c) return <div className="page"><Header left={<BackBtn />} title="Challenge" />{list ? <Empty icon="trophy" title="Challenge not found" text="It may have been deleted." /> : <p className="muted center">Loading…</p>}</div>;
  const me = s.profile!.userId; const mine = c.creator === me; const mi = mInfo(c.metric);
  return <div className="page"><Header left={<BackBtn />} title="Challenge" />
    <FCCard c={c} />
    <Card><span className="lbl">Rules</span><p className="muted small" style={{ margin: 0 }}>{mi.l} from {c.start} to {c.end}. Counts gym workouts, logged sports, challenge check-ins and your smartwatch automatically. Everyone’s phone updates its score when the app is open.</p></Card>
    <div className="row" style={{ gap: 8 }}>
      <Btn full kind="soft" onClick={() => go('/activity')}>+ Log a sport</Btn>
      {mine ? <Btn full kind="soft" onClick={async () => { if (await ask('Delete this challenge for everyone?')) { try { await deleteFriendChallenge(c.id); await refreshFriendChallenges(); history.back(); } catch (e: any) { toast(e.message); } } }}>Delete</Btn>
        : <Btn full kind="soft" onClick={async () => { if (await ask('Leave this challenge?')) { try { await respondChallenge(c.id, 'declined'); await refreshFriendChallenges(); history.back(); } catch (e: any) { toast(e.message); } } }}>Leave</Btn>}
    </div>
  </div>;
}

/** Home: show pending invites + the most urgent running challenge. */
export function FriendChallengesHome() {
  const s = useStore((x) => x); const signed = isCloud(s);
  const { list } = useFC();
  if (!signed || !list) return null;
  const me = s.profile!.userId;
  const invites = list.filter((c) => c.members.find((m) => m.userId === me)?.status === 'invited' && !ended(c));
  const running = list.filter((c) => c.members.find((m) => m.userId === me)?.status === 'accepted' && !ended(c)).sort((a, b) => a.end.localeCompare(b.end));
  if (!invites.length && !running.length) return null;
  return <>{invites.slice(0, 2).map((c) => <InviteCard key={c.id} c={c} />)}{running.slice(0, 1).map((c) => <FCCard key={c.id} c={c} />)}</>;
}

export function CreateChallenge({ open, onClose, preselect }: { open: boolean; onClose: () => void; preselect?: string }) {
  const s = useStore((x) => x); const me = s.profile?.userId;
  const [metric, setMetric] = useState<Metric>('kcal'); const [days, setDays] = useState(7);
  const [picked, setPicked] = useState<string[]>(preselect ? [preselect] : []);
  const [busy, setBusy] = useState(false); const [q, setQ] = useState('');
  useEffect(() => { if (open && isCloud(getState())) searchPeople('').catch(() => undefined); if (open && preselect) setPicked([preselect]); }, [open, preselect]);
  const people = s.social.users.filter((u) => !u.sample && u.id !== me && (u.name + u.username).toLowerCase().includes(q.toLowerCase()));
  const toggle = (id: string) => setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : [...p, id]));
  const title = `${mInfo(metric).l} in ${days} days`;
  async function start() {
    if (!picked.length) return toast('Pick at least one friend');
    setBusy(true);
    try {
      const startD = today(), endD = dayOffset(days - 1);
      const id = await createFriendChallenge({ title, metric, start: startD, end: endD, friends: picked });
      for (const f of picked) sendMessage(f, `🏆 I challenged you: ${title}! Open Bro’s Fitness → Challenges to accept. Let’s go 💪`).catch(() => undefined);
      toast('Challenge sent 🚀'); onClose(); setPicked([]);
      await refreshFriendChallenges(); go('/fchallenge/' + id);
    } catch (e: any) { toast(/schema cache|does not exist/i.test(e.message) ? 'Server setup needed — ask the app owner to run challenges.sql' : 'Could not start: ' + e.message); }
    setBusy(false);
  }
  return <Sheet open={open} onClose={onClose} title="Challenge friends">
    <span className="lbl">What counts</span>
    <div className="lvl-list">{METRICS.map((m) => <button key={m.v} className={metric === m.v ? 'on' : ''} onClick={() => setMetric(m.v)}><b>{m.emoji} {m.l}</b></button>)}</div>
    <span className="lbl" style={{ marginTop: 12, display: 'block' }}>How long</span>
    <div className="chips">{[3, 7, 14, 30].map((d) => <Chip key={d} on={days === d} onClick={() => setDays(d)}>{d} days</Chip>)}</div>
    <span className="lbl" style={{ marginTop: 12, display: 'block' }}>Who {picked.length > 0 && `· ${picked.length} picked`}</span>
    <Field label=""><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search friends" /></Field>
    <div className="fc-people">{people.length ? people.slice(0, 30).map((u) => <button key={u.id} className={picked.includes(u.id) ? 'on' : ''} onClick={() => toggle(u.id)}><Avatar name={u.name} color={u.avatarColor} src={u.photo} size={36} /><span><b>{u.name}</b><small>@{u.username}</small></span><i>{picked.includes(u.id) ? '✓' : '+'}</i></button>)
      : <p className="muted small">No members found yet — invite friends first (Profile → Invite friends).</p>}</div>
    <Btn full disabled={busy || !picked.length} onClick={start}>{busy ? 'Sending…' : `Start: ${title}`}</Btn>
  </Sheet>;
}
