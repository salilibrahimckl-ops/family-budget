// Home-screen social: friends' weekly progress leaderboard + WhatsApp-style status row for recent posts.
import React, { useEffect, useRef, useState } from 'react';
import { useStore, getState, Post } from '../lib/store';
import { Card, Avatar, Icon, Media, go, fmt, Seg } from '../ui';
import { isCloud, bg, leaderboard, pushStats, Board, statsSync } from '../lib/cloud';
import { weekStats } from '../lib/activity';
import { userOf } from './Social';

// ─── Leaderboard ───
let cache: { at: number; rows: Board[]; err?: string } | null = null;
export function FriendsBoard() {
  const s = useStore((x) => x);
  const signed = isCloud(s);
  const me = s.profile!.userId;
  const mine = weekStats(s);
  const [rows, setRows] = useState<Board[] | null>(cache?.rows || null);
  const [err, setErr] = useState(cache?.err || '');
  const [by, setBy] = useState<'kcal' | 'minutes' | 'workouts'>('kcal');
  useEffect(() => {
    if (!signed) return;
    let dead = false;
    const load = async () => {
      try { await pushStats(weekStats(getState())); } catch { /* ignore */ }
      try { const r = await leaderboard(mine.week); cache = { at: Date.now(), rows: r }; if (!dead) { setRows(r); setErr(''); } }
      catch (e: any) { const m = /weekly_stats|schema cache|does not exist/i.test(e.message) ? 'setup' : e.message; cache = { at: Date.now(), rows: [], err: m }; if (!dead) setErr(m); }
    };
    load(); const t = setInterval(() => { if (document.visibilityState === 'visible') load(); }, 45e3);
    return () => { dead = true; clearInterval(t); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [signed, mine.kcal, mine.workouts]);
  const list = (rows || []).map((r) => (r.userId === me ? { ...r, kcal: mine.kcal, minutes: mine.minutes, workouts: mine.workouts, streak: mine.streak } : r));
  if (signed && !list.find((r) => r.userId === me) && s.profile!.leaderboard !== false) list.push({ userId: me, kcal: mine.kcal, minutes: mine.minutes, workouts: mine.workouts, streak: mine.streak, updated: Date.now() });
  list.sort((a, b) => b[by] - a[by]);
  const unit = by === 'kcal' ? 'kcal' : by === 'minutes' ? 'min' : '';
  const top = list[0]?.[by] || 1;
  return (
    <Card className="board">
      <div className="row-b"><span className="lbl"><Icon n="trophy" s={16} /> Friends this week</span><button className="link" onClick={() => go('/community')}>Community</button></div>
      {!signed ? <p className="muted small" style={{ margin: 0 }}>Sign in (Community tab) to compare your week with friends. You: <b>{fmt.n(mine.kcal)} kcal</b> burnt · {mine.workouts} sessions · 🔥 {mine.streak}-day streak.</p>
        : err === 'setup' ? <p className="muted small" style={{ margin: 0 }}>Leaderboard is almost ready — the app owner needs to run one short setup step on the server.</p>
        : <>
          <Seg value={by} onChange={setBy} options={[{ v: 'kcal', l: 'Calories' }, { v: 'minutes', l: 'Active min' }, { v: 'workouts', l: 'Sessions' }]} />
          {rows === null && <p className="muted small">Loading…</p>}
          {list.slice(0, 12).map((r, i) => {
            const u = r.userId === me ? { name: 'You', avatarColor: '#C6FF3D', photo: undefined } : userOf(s, r.userId);
            return (
              <div key={r.userId} className={'board-row' + (r.userId === me ? ' me' : '')} onClick={() => r.userId !== me && go('/user/' + r.userId)}>
                <span className="rank">{i < 3 ? ['🥇', '🥈', '🥉'][i] : i + 1}</span>
                <Avatar name={u?.name || '?'} color={u?.avatarColor} src={(u as any)?.photo} media={r.userId === me ? s.profile!.avatar : undefined} size={34} />
                <div className="board-mid"><b>{u?.name || 'Member'}</b><i style={{ width: Math.max(4, (r[by] / top) * 100) + '%' }} />
                  <small className="sync">{r.userId === me ? (statsSync.err ? '⚠ not sent: ' + statsSync.err.slice(0, 60) : statsSync.at ? 'synced ' + fmt.ago(statsSync.at) : 'syncing…') : r.updated > 0 ? 'updated ' + fmt.ago(r.updated) : 'not synced yet — needs app update'}</small></div>
                <span className="board-val">{fmt.n(r[by])}{unit && <small> {unit}</small>}{r.streak > 1 && <small className="streak"> 🔥{r.streak}</small>}</span>
              </div>
            );
          })}
          {list.length <= 1 && rows !== null && <p className="muted small" style={{ margin: '6px 0 0' }}>Invite friends to see who trains the most this week. <button className="link" onClick={() => go('/invite')}>Invite</button></p>}
          {err && err !== 'setup' && <p className="muted small">{err}</p>}
        </>}
    </Card>
  );
}

// ─── Status row (posts from the last 24 h, grouped by person) ───
const SEEN_KEY = 'fv.seen.status';
const seenSet = (): Set<string> => { try { return new Set(JSON.parse(localStorage.getItem(SEEN_KEY) || '[]')); } catch { return new Set(); } };
const markSeen = (ids: string[]) => { const s = seenSet(); ids.forEach((i) => s.add(i)); try { localStorage.setItem(SEEN_KEY, JSON.stringify([...s].slice(-500))); } catch { /* */ } };

function statusGroups(posts: Post[], me: string, blocks: string[]) {
  const since = Date.now() - 24 * 3600e3;
  const map = new Map<string, Post[]>();
  posts.filter((p) => !p.removed && p.ts >= since && !blocks.includes(p.userId)).forEach((p) => { const a = map.get(p.userId) || []; a.push(p); map.set(p.userId, a); });
  const groups = [...map.entries()].map(([userId, ps]) => ({ userId, posts: ps.sort((a, b) => a.ts - b.ts) }));
  return groups.sort((a, b) => (a.userId === me ? -1 : b.userId === me ? 1 : b.posts[b.posts.length - 1].ts - a.posts[a.posts.length - 1].ts));
}

export function StatusRow({ showAdd = true }: { showAdd?: boolean }) {
  const s = useStore((x) => x); const me = s.profile!.userId;
  // Once signed in, show real people only (hide the built-in sample accounts).
  const sample = new Set(isCloud(s) ? s.social.users.filter((u) => u.sample).map((u) => u.id) : []);
  const groups = statusGroups(s.social.posts.filter((p) => !sample.has(p.userId)), me, s.social.blocks);
  const [open, setOpen] = useState<number | null>(null);
  const [, force] = useState(0);
  const seen = seenSet();
  if (!groups.length && !showAdd) return null;
  return (
    <>
      <div className="hscroll status-row">
        {showAdd && !groups.find((g) => g.userId === me) && <button className="status" onClick={() => go('/new-post')}><span className="ring add"><Avatar name={s.profile!.name} color="#C6FF3D" media={s.profile!.avatar} size={56} /><i>+</i></span><small>My status</small></button>}
        {groups.map((g, i) => {
          const u = g.userId === me ? { name: s.profile!.name, avatarColor: '#C6FF3D' } : userOf(s, g.userId);
          const unseen = g.posts.some((p) => !seen.has(p.id));
          return <button key={g.userId} className="status" onClick={() => setOpen(i)}>
            <span className={'ring' + (unseen ? ' new' : '')}><Avatar name={u?.name || '?'} color={u?.avatarColor} src={(u as any)?.photo} media={g.userId === me ? s.profile!.avatar : undefined} size={56} /></span>
            <small>{g.userId === me ? 'My status' : (u?.name || 'Member').split(' ')[0]}</small>
          </button>;
        })}
        {!groups.length && <div className="status-empty muted small">Posts from the last 24 hours show up here like a status.</div>}
      </div>
      {open !== null && <StoryViewer groups={groups} start={open} onClose={() => { setOpen(null); force((x) => x + 1); }} />}
    </>
  );
}

function StoryViewer({ groups, start, onClose }: { groups: ReturnType<typeof statusGroups>; start: number; onClose: () => void }) {
  const s = getState();
  const [gi, setGi] = useState(start);
  const [pi, setPi] = useState(() => { const seen = seenSet(); const k = groups[start].posts.findIndex((p) => !seen.has(p.id)); return k < 0 ? 0 : k; });
  const [paused, setPaused] = useState(false);
  const [t, setT] = useState(0);
  const g = groups[gi]; const p = g?.posts[pi];
  const DUR = 5000;
  const next = () => { if (pi < g.posts.length - 1) { setPi(pi + 1); setT(0); } else if (gi < groups.length - 1) { setGi(gi + 1); setPi(0); setT(0); } else onClose(); };
  const prev = () => { if (pi > 0) { setPi(pi - 1); setT(0); } else if (gi > 0) { setGi(gi - 1); setPi(0); setT(0); } else setT(0); };
  const nextRef = useRef(next); nextRef.current = next;
  useEffect(() => { if (p) markSeen([p.id]); }, [p?.id]);
  useEffect(() => {
    if (paused || p?.media[0]?.type === 'video') return;
    const id = setInterval(() => setT((x) => { const n = x + 100; if (n >= DUR) { setTimeout(() => nextRef.current(), 0); return 0; } return n; }), 100);
    return () => clearInterval(id);
  }, [paused, gi, pi]);
  if (!p) return null;
  const u = g.userId === s.profile!.userId ? { name: s.profile!.name, avatarColor: '#C6FF3D' } : userOf(s, g.userId);
  const bgCol = ['#1b5e20', '#4a148c', '#0d47a1', '#b71c1c', '#e65100', '#006064'][(p.id.charCodeAt(p.id.length - 1) || 0) % 6];
  return (
    <div className="sv" onPointerDown={() => setPaused(true)} onPointerUp={() => setPaused(false)} onPointerCancel={() => setPaused(false)}>
      <div className="sv-bars">{g.posts.map((x, k) => <i key={x.id}><b style={{ width: k < pi ? '100%' : k === pi ? (t / DUR) * 100 + '%' : '0%' }} /></i>)}</div>
      <div className="sv-top">
        <Avatar name={u?.name || '?'} color={u?.avatarColor} src={(u as any)?.photo} size={36} />
        <div><b>{u?.name}</b><small>{fmt.ago(p.ts)}</small></div>
        <button onClick={onClose} aria-label="Close"><Icon n="x" /></button>
      </div>
      <div className="sv-body" style={{ background: p.media.length ? '#000' : bgCol }}>
        {p.media[0] ? <Media m={p.media[0]} className="sv-media" /> : null}
        {p.workout && <div className="sv-wo">🏋️ <b>{p.workout.name}</b><br />{p.workout.exercises} exercises · {p.workout.minutes} min · {fmt.n(p.workout.volume)} kg</div>}
        {p.text && <div className={p.media.length ? 'sv-cap' : 'sv-text'}>{p.text}</div>}
      </div>
      <button className="sv-nav l" onClick={(e) => { e.stopPropagation(); prev(); }} aria-label="Previous" />
      <button className="sv-nav r" onClick={(e) => { e.stopPropagation(); next(); }} aria-label="Next" />
      <button className="sv-open" onClick={() => { onClose(); go('/post/' + p.id); }}>Open post · like & comment</button>
    </div>
  );
}

/** Keep weekly stats on the server fresh after workouts/sports (fire-and-forget). */
export function syncWeekly() { const s = getState(); if (isCloud(s)) bg(pushStats(weekStats(s))); }
