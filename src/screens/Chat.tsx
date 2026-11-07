// Direct messages between community members (uses the same sign-in as the rest of the app).
import React, { useEffect, useRef, useState } from 'react';
import { useStore, getState } from '../lib/store';
import { Header, BackBtn, Avatar, Icon, Empty, Btn, go, Chip } from '../ui';
import { inbox, thread, sendMessage, markRead, unreadMessages, searchPeople, Msg, isCloud, bg } from '../lib/cloud';
import { JoinCard, useCloud } from './Join';
import { toast } from '../lib/extras';

// Shared unread counter (polled while the app is open)
let unread = 0; const subs = new Set<() => void>(); let timer: any = 0;
function setUnread(n: number) { if (n !== unread) { unread = n; subs.forEach((f) => f()); } }
async function pollUnread() { try { if (isCloud(getState())) setUnread(await unreadMessages()); } catch { /* offline */ } }
export function useUnreadMessages() {
  const [, force] = useState(0);
  useEffect(() => {
    const f = () => force((x) => x + 1); subs.add(f);
    if (!timer) { pollUnread(); timer = setInterval(pollUnread, 30e3); }
    return () => { subs.delete(f); if (!subs.size) { clearInterval(timer); timer = 0; } };
  }, []);
  return unread;
}

const when = (ts: number) => {
  const d = new Date(ts), now = new Date();
  if (d.toDateString() === now.toDateString()) return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  const y = new Date(now.getTime() - 864e5); if (d.toDateString() === y.toDateString()) return 'Yesterday';
  return d.toLocaleDateString([], { day: 'numeric', month: 'short' });
};
const userName = (id: string) => getState().social.users.find((u) => u.id === id);

export function Messages() {
  const { signedIn } = useCloud();
  useStore((s) => s.social.users.length);
  const [rows, setRows] = useState<Awaited<ReturnType<typeof inbox>> | null>(null);
  const [err, setErr] = useState('');
  const [people, setPeople] = useState<ReturnType<typeof userName>[]>([]);
  useEffect(() => {
    if (!signedIn) return;
    let dead = false;
    const load = () => inbox().then((r) => { if (!dead) { setRows(r); setErr(''); } }).catch((e) => !dead && setErr(e.message));
    load(); const t = setInterval(load, 8000);
    searchPeople('').then((p) => !dead && setPeople(p as any)).catch(() => undefined);
    return () => { dead = true; clearInterval(t); };
  }, [signedIn]);
  return (
    <div className="page">
      <Header left={<BackBtn />} title="Messages" right={signedIn && <button className="icon-btn" onClick={() => go('/search-users')} aria-label="New message"><Icon n="edit" /></button>} />
      {!signedIn ? <JoinCard title="Chat with your gym buddies" text="Sign in once with Google or your email — the same account works on Android and iPhone." /> : <>
        {err && <p className="err">{err}</p>}
        {rows === null && !err && <p className="muted center">Loading chats…</p>}
        {rows?.map((r) => { const u = userName(r.other); return (
          <div key={r.other} className="inbox-row" onClick={() => go('/chat/' + r.other)}>
            <Avatar name={u?.name || '?'} color={u?.avatarColor} src={u?.photo} size={48} />
            <div><b>{u?.name || 'Member'}</b><small>{r.last.from === r.other ? '' : 'You: '}{r.last.text}</small></div>
            <span className="when">{when(r.last.ts)}{r.unread > 0 && <><br /><span className="dot">{r.unread}</span></>}</span>
          </div>); })}
        {rows && !rows.length && <Empty icon="send" title="No chats yet" text="Say hi to someone from the community — tap a person below or use search." />}
        {rows && people.length > 0 && <>
          <p className="lbl" style={{ marginTop: 18 }}>People on Bro’s Fitness</p>
          {people.filter((p) => p && !rows.find((r) => r.other === p.id)).slice(0, 12).map((p) => p && (
            <div key={p.id} className="inbox-row" onClick={() => go('/chat/' + p.id)}>
              <Avatar name={p.name} color={p.avatarColor} src={p.photo} size={44} /><div><b>{p.name}</b><small>@{p.username}</small></div><Icon n="send" s={18} />
            </div>))}
        </>}
      </>}
    </div>
  );
}

export function ChatThread({ other }: { other: string }) {
  const { signedIn } = useCloud();
  const u = useStore((s) => s.social.users.find((x) => x.id === other));
  const meCloud = useStore((s) => s.session?.userId);
  const [msgs, setMsgs] = useState<Msg[] | null>(null);
  const [pending, setPending] = useState<Msg[]>([]);
  const [text, setText] = useState('');
  const [err, setErr] = useState('');
  const box = useRef<HTMLDivElement>(null);
  const atBottom = useRef(true);
  useEffect(() => {
    if (!signedIn) return;
    let dead = false;
    const load = async () => {
      try {
        const m = await thread(other); if (dead) return;
        setMsgs(m); setErr('');
        if (m.some((x) => x.to === meCloud && !x.read)) { bg(markRead(other)); setTimeout(pollUnread, 800); }
      } catch (e: any) { if (!dead) setErr(e.message); }
    };
    load(); const t = setInterval(() => { if (document.visibilityState === 'visible') load(); }, 4000);
    return () => { dead = true; clearInterval(t); };
  }, [other, signedIn, meCloud]);
  useEffect(() => { const el = box.current; if (el && atBottom.current) el.scrollTop = el.scrollHeight; }, [msgs, pending]);
  async function send(t = text) {
    const body = t.trim(); if (!body) return;
    const temp: Msg = { id: 'tmp' + Date.now(), from: meCloud!, to: other, text: body, ts: Date.now(), read: false };
    setPending((p) => [...p, temp]); setText(''); atBottom.current = true;
    try { const m = await sendMessage(other, body); setMsgs((x) => [...(x || []), m]); }
    catch (e: any) { toast('Not sent: ' + e.message); setText(body); }
    finally { setPending((p) => p.filter((x) => x.id !== temp.id)); }
  }
  if (!signedIn) return <div className="page"><Header left={<BackBtn />} title="Chat" /><JoinCard title="Sign in to chat" /></div>;
  if (u?.sample) return <div className="page"><Header left={<BackBtn />} title={u.name} /><Empty icon="user" title="Sample account" text="This is a demo profile, so it can’t reply. Chat with real members — find them in search." action={<Btn onClick={() => go('/search-users')}>Find people</Btn>} /></div>;
  const all = [...(msgs || []), ...pending];
  let lastDay = '';
  return (
    <div className="page chat">
      <Header left={<BackBtn />} title={<span className="row" style={{ gap: 10 }} onClick={() => go('/user/' + other)}><Avatar name={u?.name || '?'} color={u?.avatarColor} src={u?.photo} size={32} /><span>{u?.name || 'Chat'}</span></span>} />
      <div className="chat-msgs" ref={box} onScroll={(e) => { const el = e.currentTarget; atBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80; }}>
        {err && <p className="err">{err}</p>}
        {msgs === null && !err && <p className="muted center">Loading…</p>}
        {msgs && !all.length && <div className="center muted" style={{ marginTop: 30 }}><p>Start the conversation with {u?.name?.split(' ')[0] || 'them'} 💪</p></div>}
        {all.map((m) => {
          const day = new Date(m.ts).toDateString(); const sep = day !== lastDay; lastDay = day;
          return <React.Fragment key={m.id}>
            {sep && <div className="chat-day">{when(m.ts).includes(':') ? 'Today' : when(m.ts)}</div>}
            <div className={'bubble ' + (m.from === meCloud ? 'me' : 'them') + (m.id.startsWith('tmp') ? ' pending' : '')}>{m.text}<small>{new Date(m.ts).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}{m.from === meCloud && m.read ? ' · Seen' : ''}</small></div>
          </React.Fragment>;
        })}
      </div>
      <div className="chat-box">
        {msgs && !all.length && <div className="quick-replies" style={{ position: 'absolute', bottom: '100%', left: 12, right: 12 }}>{['Hey! 👋', 'Gym today? 🏋️', 'Nice workout! 🔥'].map((q) => <Chip key={q} onClick={() => send(q)}>{q}</Chip>)}</div>}
        <textarea rows={1} value={text} onChange={(e) => setText(e.target.value)} placeholder="Message…" onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); } }} />
        <button disabled={!text.trim()} onClick={() => send()} aria-label="Send"><Icon n="send" s={20} /></button>
      </div>
    </div>
  );
}
