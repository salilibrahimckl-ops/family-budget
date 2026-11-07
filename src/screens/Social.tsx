import React, { useState } from 'react';
import { useStore, update, uid, today, putMedia, processImage, validateVideo, notify, State, Post, getState, SocialUser } from '../lib/store';
import { Header, BackBtn, Card, Btn, Chip, Seg, Icon, Pill, Sheet, Empty, go, back, Avatar, Media, fmt, Field, NumIn } from '../ui';
import { toast, share, checkAchievements, CHALLENGES, challengeProgress, ACHIEVEMENTS } from '../lib/extras';
import { ask, askText } from '../lib/dialog';
import { isCloud, bg, cloudCreatePost, cloudLike, cloudComment, cloudFollow, cloudReport, pullFeed } from '../lib/cloud';
import { useUnits } from './common';

export function meUser(s: State): SocialUser { const p = s.profile!; return { id: p.userId, name: p.name, username: p.username, bio: p.bio, avatarColor: '#C6FF3D', private: p.private, sample: false }; }
export function userOf(s: State, id: string): SocialUser | undefined { return id === s.profile?.userId ? meUser(s) : s.social.users.find((u) => u.id === id); }
const followState = (s: State, to: string) => s.social.follows.find((f) => f.from === s.profile!.userId && f.to === to)?.status;
const MENTION = /(@[a-z0-9_.]+)/gi;
const RichText = ({ text }: { text: string }) => <>{text.split(MENTION).map((p, i) => (p.startsWith('@') ? <b key={i} className="mention" onClick={(e) => { e.stopPropagation(); const s = getState(); const u = s.social.users.find((x) => '@' + x.username === p.toLowerCase()); if (u) go('/user/' + u.id); }}>{p}</b> : p.split(/(#[a-z0-9_]+)/gi).map((q, k) => q.startsWith('#') ? <b key={k} className="hashtag">{q}</b> : q)))}</>;

export function Feed() {
  const s = useStore((x) => x);
  const [tab, setTab] = useState<'for' | 'following'>('for');
  const [refreshing, setRefreshing] = useState(false);
  const [limit, setLimit] = useState(10);
  const me = s.profile!.userId;
  const visible = s.social.posts.filter((p) => {
    if (p.removed || s.social.blocks.includes(p.userId)) return false;
    const u = userOf(s, p.userId); if (!u || u.suspended) return false;
    if (u.private && p.userId !== me && followState(s, p.userId) !== 'accepted') return false;
    if (tab === 'following') return p.userId === me || followState(s, p.userId) === 'accepted';
    return true;
  });
  const unread = s.notifications.filter((n) => !n.read).length;
  return (
    <div className="page">
      <Header big title="Community" right={<div className="row">
        <button className="icon-btn" onClick={() => go('/search-users')} aria-label="Find people"><Icon n="search" /></button>
        <button className="icon-btn" onClick={() => go('/notifications')} aria-label="Notifications"><Icon n="bell" />{unread > 0 && <i className="badge">{unread}</i>}</button></div>} />
      <Seg value={tab} onChange={setTab} options={[{ v: 'for', l: 'For you' }, { v: 'following', l: 'Following' }]} />
      <div className="hscroll stories">
        <button className="story me" onClick={() => go('/new-post')}><span><Icon n="plus" /></span><small>New post</small></button>
        <button className="story" onClick={() => go('/challenges')}><span>🏆</span><small>Challenges</small></button>
        {s.social.users.filter((u) => u.creator).map((u) => <button key={u.id} className="story" onClick={() => go('/user/' + u.id)}><Avatar name={u.name} color={u.avatarColor} size={54} /><small>{u.username}</small></button>)}
      </div>
      {isCloud(s) && <Btn small kind="ghost" onClick={async () => { setRefreshing(true); try { await pullFeed(); } catch (e: any) { toast(e.message); } setRefreshing(false); }}>{refreshing ? 'Refreshing…' : '↻ Refresh feed'}</Btn>}
      {visible.slice(0, limit).map((p) => <PostCard key={p.id} p={p} />)}
      {visible.length > limit && <Btn full kind="ghost" onClick={() => setLimit(limit + 10)}>Load more</Btn>}
      {!visible.length && <Empty icon="users" title={tab === 'following' ? 'No posts from people you follow' : 'No posts yet'} text="Follow athletes or share your first workout." action={<Btn onClick={() => go('/new-post')}>Create post</Btn>} />}
      <button className="fab" onClick={() => go('/new-post')} aria-label="New post"><Icon n="plus" s={26} /></button>
    </div>
  );
}

export function PostCard({ p, full }: { p: Post; full?: boolean }) {
  const s = useStore((x) => x); const me = s.profile!.userId;
  const u = userOf(s, p.userId)!; const liked = s.social.likes.some((l) => l.postId === p.id && l.userId === me);
  const likes = p.likes + s.social.likes.filter((l) => l.postId === p.id).length;
  const comments = s.social.comments.filter((c) => c.postId === p.id).length;
  const saved = s.social.bookmarks.includes(p.id);
  const [menu, setMenu] = useState(false);
  const [burst, setBurst] = useState(false);
  function like() {
    update((d) => {
      if (liked) d.social.likes = d.social.likes.filter((l) => !(l.postId === p.id && l.userId === me));
      else { d.social.likes.push({ postId: p.id, userId: me }); if (p.userId === me) { /* own post */ } }
    });
    if (!liked) { setBurst(true); setTimeout(() => setBurst(false), 600); }
    if (isCloud(s)) bg(cloudLike(p.id, !liked));
  }
  return (
    <Card className={'post' + (full ? ' full' : '')}>
      <div className="post-h">
        <div className="row" onClick={() => go('/user/' + u.id)}><Avatar name={u.name} color={u.avatarColor} media={u.id === me ? s.profile!.avatar : undefined} size={38} />
          <div><b>{u.name}{u.creator && <span className="verified">✓</span>}</b><small>@{u.username} · {fmt.ago(p.ts)}{u.sample && ' · Sample'}</small></div></div>
        <div className="row">{p.kind !== 'text' && p.kind !== 'photo' && <Pill tone={p.kind === 'transformation' ? 'pro' : p.kind === 'tip' ? 'info' : 'lime'}>{({ workout: 'Workout', transformation: 'Transformation', achievement: 'Achievement', tip: 'Fitness tip', challenge: 'Challenge', video: 'Video' } as any)[p.kind]}</Pill>}
          <button className="icon-btn" onClick={() => setMenu(true)} aria-label="More"><Icon n="more" /></button></div>
      </div>
      {p.text && <p className="post-t" onClick={() => !full && go('/post/' + p.id)}><RichText text={p.text} /></p>}
      {p.workout && <div className="post-wo" onClick={() => !full && go('/post/' + p.id)}><Icon n="train" /><div><b>{p.workout.name}</b><small>{p.workout.minutes} min · {p.workout.exercises} exercises · {fmt.n(p.workout.volume)} kg volume</small></div></div>}
      {p.media.length > 0 && <div className={'post-media n' + Math.min(p.media.length, 2)} onDoubleClick={() => !liked && like()}>{p.media.slice(0, 4).map((m, i) => <Media key={i} m={m} />)}{burst && <span className="burst">♥</span>}</div>}
      <div className="post-a">
        <button className={liked ? 'liked' : ''} onClick={like}><Icon n="heart" fill={liked} /> {likes}</button>
        <button onClick={() => go('/post/' + p.id)}><Icon n="comment" /> {comments}</button>
        <button onClick={() => share(`${u.name} on FITVERSE: ${p.text.slice(0, 140)}`)}><Icon n="share" /></button>
        <span style={{ flex: 1 }} />
        <button className={saved ? 'liked' : ''} onClick={() => update((d) => { d.social.bookmarks = saved ? d.social.bookmarks.filter((b) => b !== p.id) : [...d.social.bookmarks, p.id]; })}><Icon n="bookmark" fill={saved} /></button>
      </div>
      <Sheet open={menu} onClose={() => setMenu(false)}>
        {p.userId === me ? <Btn full kind="danger" icon="trash" onClick={() => { update((d) => { d.social.posts = d.social.posts.filter((x) => x.id !== p.id); }); setMenu(false); toast('Post deleted'); }}>Delete post</Btn> : <>
          <Btn full kind="soft" icon="shield" onClick={async () => { const reason = await askText('Why are you reporting this post? (spam, harassment, unsafe advice, nudity, other)'); if (!reason) return; update((d) => { d.social.reports.push({ id: uid(), postId: p.id, reason, ts: Date.now(), status: 'open' }); }); if (isCloud(s)) bg(cloudReport(p.id, reason)); setMenu(false); toast('Reported. Our moderators will review it.'); }}>Report post</Btn>
          <div style={{ height: 8 }} />
          <Btn full kind="danger" icon="x" onClick={() => { update((d) => { d.social.blocks.push(p.userId); d.social.follows = d.social.follows.filter((f) => !(f.from === me && f.to === p.userId)); }); setMenu(false); toast(`Blocked @${u.username}`); }}>Block @{u.username}</Btn></>}
      </Sheet>
    </Card>
  );
}

export function PostDetail({ id }: { id: string }) {
  const s = useStore((x) => x); const p = s.social.posts.find((x) => x.id === id);
  const [text, setText] = useState(''); const [reply, setReply] = useState<string | null>(null);
  if (!p) return <div className="page"><Header left={<BackBtn />} title="Post" /><Empty icon="x" title="Post not available" /></div>;
  const me = s.profile!.userId;
  const top = s.social.comments.filter((c) => c.postId === id && !c.parentId).sort((a, b) => a.ts - b.ts);
  const replies = (cid: string) => s.social.comments.filter((c) => c.parentId === cid).sort((a, b) => a.ts - b.ts);
  function send() {
    const t = text.trim(); if (!t) return; if (t.length > 1000) return toast('Comment is too long');
    const recent = s.social.comments.filter((c) => c.userId === me && Date.now() - c.ts < 60000).length;
    if (recent >= 5) return toast('Slow down — you are commenting too quickly.');
    const cid = uid();
    update((d) => {
      d.social.comments.push({ id: cid, postId: id, userId: me, text: t, ts: Date.now(), parentId: reply || undefined });
    });
    if (isCloud(s)) bg(cloudComment(cid, id, t, reply || undefined));
    setText(''); setReply(null);
  }
  const C = ({ c, indent }: { c: typeof top[0]; indent?: boolean }) => { const u = userOf(s, c.userId); return (
    <div className={'cmt' + (indent ? ' reply' : '')}>
      <Avatar name={u?.name || '?'} color={u?.avatarColor} size={30} />
      <div><b>{u?.username}</b> <span><RichText text={c.text} /></span><div className="cmt-a"><small>{fmt.ago(c.ts)}</small><button onClick={() => { setReply(c.parentId || c.id); setText(`@${u?.username} `); }}>Reply</button>
        {c.userId === me && <button onClick={() => update((d) => { d.social.comments = d.social.comments.filter((x) => x.id !== c.id && x.parentId !== c.id); })}>Delete</button>}</div></div>
    </div>); };
  return (
    <div className="page post-page">
      <Header left={<BackBtn />} title="Post" />
      <PostCard p={p} full />
      <div className="cmts">{top.map((c) => <div key={c.id}><C c={c} />{replies(c.id).map((r) => <C key={r.id} c={r} indent />)}</div>)}
        {!top.length && <p className="muted small pad">No comments yet. Be the first!</p>}</div>
      <div className="cmt-box">{reply && <small className="muted">Replying · <button className="link" onClick={() => { setReply(null); setText(''); }}>cancel</button></small>}
        <div className="row"><input value={text} onChange={(e) => setText(e.target.value)} placeholder="Add a comment… use @ to mention" onKeyDown={(e) => e.key === 'Enter' && send()} /><button className="send" onClick={send} aria-label="Send"><Icon n="send" s={18} /></button></div></div>
    </div>
  );
}

export function NewPost() {
  const s = useStore((x) => x); const u = useUnits();
  const [kind, setKind] = useState<Post['kind']>('photo');
  const [text, setText] = useState('');
  const [files, setFiles] = useState<{ blob: Blob; type: 'image' | 'video'; url: string }[]>([]);
  const [wo, setWo] = useState<string>(s.workouts[0]?.id || '');
  const [busy, setBusy] = useState(false);
  const [stats, setStats] = useState(false);
  const me = s.profile!;
  async function addFiles(list: FileList | null) {
    if (!list) return;
    for (const f of Array.from(list).slice(0, 4 - files.length)) {
      try {
        if (f.type.startsWith('video')) { validateVideo(f); setFiles((x) => [...x, { blob: f, type: 'video', url: URL.createObjectURL(f) }]); setKind('video'); }
        else { const b = await processImage(f); setFiles((x) => [...x, { blob: b, type: 'image', url: URL.createObjectURL(b) }]); }
      } catch (e: any) { toast(e.message); }
    }
  }
  async function publish() {
    const recent = s.social.posts.filter((p) => p.userId === me.userId && Date.now() - p.ts < 120000).length;
    if (recent >= 3) return toast('You are posting too quickly. Please wait a couple of minutes.');
    if (!text.trim() && !files.length && kind !== 'workout') return toast('Add some text or media');
    if (text.length > 2200) return toast('Caption is too long (2200 characters max).');
    setBusy(true);
    try {
      const media = [] as Post['media'];
      for (const f of files) media.push({ id: await putMedia(f.blob), type: f.type });
      const w = s.workouts.find((x) => x.id === wo);
      let body = text.trim();
      if (stats && kind === 'transformation') { const first = s.weights[0]; const last = s.weights[s.weights.length - 1]; if (first && last) body += `\n\n${u.w(first.kg)} → ${u.w(last.kg)}`; }
      const post: Post = { id: uid(), userId: me.userId, ts: Date.now(), kind, text: body, media, likes: 0, workout: kind === 'workout' && w ? { name: w.name, volume: w.volume, minutes: Math.round((w.end - w.start) / 60000), exercises: w.entries.length } : undefined };
      update((d) => { d.social.posts.unshift(post); });
      if (isCloud(s)) bg(cloudCreatePost(post, files.map((f) => ({ blob: f.blob, type: f.type }))), (e) => toast('Cloud upload failed: ' + e.message));
      checkAchievements(); toast('Posted 🎉'); go('/community');
    } finally { setBusy(false); }
  }
  return (
    <div className="page">
      <Header left={<BackBtn />} title="New post" right={<Btn small disabled={busy} onClick={publish}>{busy ? '…' : 'Share'}</Btn>} />
      <div className="chips scroll">{([['photo', '📷 Photo'], ['video', '🎬 Video'], ['workout', '🏋️ Workout'], ['transformation', '🔄 Transformation'], ['achievement', '🏆 Achievement'], ['tip', '💡 Tip'], ['text', '✍️ Text']] as const).map(([k, l]) => <Chip key={k} on={kind === k} onClick={() => setKind(k)}>{l}</Chip>)}</div>
      <Card>
        <div className="row"><Avatar name={me.name} media={me.avatar} size={38} /><textarea className="post-input" rows={4} value={text} onChange={(e) => setText(e.target.value)} placeholder={kind === 'transformation' ? 'Share your journey — what changed, what worked?' : kind === 'tip' ? 'Share a fitness tip…' : 'What did you train today? #legday'} /></div>
        {kind === 'workout' && (s.workouts.length ? <Field label="Attach a workout"><select value={wo} onChange={(e) => setWo(e.target.value)}>{s.workouts.slice(0, 20).map((w) => <option key={w.id} value={w.id}>{w.name} — {fmt.date(w.date)}</option>)}</select></Field> : <p className="muted small">Log a workout first to attach it.</p>)}
        {kind === 'achievement' && <div className="chips">{ACHIEVEMENTS.filter((a) => s.achievements[a.id]).map((a) => <Chip key={a.id} onClick={() => setText(`Unlocked ${a.emoji} ${a.name} — ${a.desc}!`)}>{a.emoji} {a.name}</Chip>)}{!Object.keys(s.achievements).length && <small className="muted">Unlock badges by training and logging.</small>}</div>}
        {kind === 'transformation' && <label className="toggle-inline"><input type="checkbox" checked={stats} onChange={(e) => setStats(e.target.checked)} /> Include my start → current weight (off by default — your body data is private unless you choose)</label>}
        <div className="post-files">{files.map((f, i) => <div key={i} className="pf">{f.type === 'video' ? <video src={f.url} muted /> : <img src={f.url} alt="" />}<button onClick={() => setFiles(files.filter((_, k) => k !== i))}><Icon n="x" s={14} /></button></div>)}
          {files.length < 4 && <label className="pf add"><Icon n="camera" /><small>Photo/Video</small><input type="file" hidden multiple accept="image/jpeg,image/png,image/webp,video/mp4,video/quicktime,video/webm" onChange={(e) => addFiles(e.target.files)} /></label>}</div>
        <p className="muted small">Up to 4 files · images are compressed to 1440 px · videos up to 60 MB. {me.private ? '🔒 Your account is private: only approved followers see this.' : '🌍 Public post.'}</p>
      </Card>
    </div>
  );
}

export function UserProfile({ id }: { id: string }) {
  const s = useStore((x) => x); const me = s.profile!.userId;
  const u = userOf(s, id);
  const [list, setList] = useState<'followers' | 'following' | null>(null);
  if (!u) return <div className="page"><Header left={<BackBtn />} title="User" /><Empty icon="user" title="User not found" /></div>;
  const isMe = id === me; const fs = followState(s, id);
  const posts = s.social.posts.filter((p) => p.userId === id && !p.removed);
  const canSee = isMe || !u.private || fs === 'accepted';
  const followers = s.social.follows.filter((f) => f.to === id && f.status === 'accepted').length + (u.sample ? 120 + id.length * 37 : 0);
  const following = s.social.follows.filter((f) => f.from === id && f.status === 'accepted').length + (u.sample ? 80 + id.length * 11 : 0);
  const blocked = s.social.blocks.includes(id);
  function follow() {
    update((d) => {
      if (fs) d.social.follows = d.social.follows.filter((f) => !(f.from === me && f.to === id));
      else { d.social.follows.push({ from: me, to: id, status: u!.private ? 'pending' : 'accepted' }); if (!u!.private) notify(d, { type: 'follow', text: `You are now following @${u!.username}` }); }
    });
    if (isCloud(s)) bg(cloudFollow(id, !fs));
    if (!fs && u.private) toast('Follow request sent');
  }
  return (
    <div className="page">
      <Header left={<BackBtn />} title={'@' + u.username} right={isMe && <button className="icon-btn" onClick={() => go('/settings')} aria-label="Settings"><Icon n="gear" /></button>} />
      <div className="prof-h">
        <Avatar name={u.name} color={u.avatarColor} media={isMe ? s.profile!.avatar : undefined} size={84} />
        <div className="prof-n"><b>{u.name}{u.creator && <span className="verified">✓</span>}</b>{u.private && <Pill><Icon n="lock" s={12} /> Private</Pill>}{u.sample && <Pill>Sample account</Pill>}<p>{u.bio}</p></div>
      </div>
      <div className="prof-stats"><div><b>{posts.length}</b><small>Posts</small></div><button onClick={() => canSee && setList('followers')}><b>{followers}</b><small>Followers</small></button><button onClick={() => canSee && setList('following')}><b>{following}</b><small>Following</small></button></div>
      {!isMe && <div className="row">{blocked ? <Btn full kind="soft" onClick={() => update((d) => { d.social.blocks = d.social.blocks.filter((b) => b !== id); })}>Unblock</Btn>
        : <Btn full kind={fs ? 'soft' : 'primary'} onClick={follow}>{fs === 'accepted' ? 'Following' : fs === 'pending' ? 'Requested' : 'Follow'}</Btn>}</div>}
      {isMe && <div className="row"><Btn full kind="soft" onClick={() => go('/edit-profile')}>Edit profile</Btn><Btn full kind="soft" onClick={() => go('/bookmarks')}>Saved</Btn></div>}
      {canSee ? (posts.length ? posts.map((p) => <PostCard key={p.id} p={p} />) : <Empty icon="camera" title="No posts yet" />)
        : <Empty icon="lock" title="This account is private" text="Follow to see their posts once they approve." />}
      <Sheet open={!!list} onClose={() => setList(null)} title={list === 'followers' ? 'Followers' : 'Following'}>
        {(list === 'followers' ? s.social.follows.filter((f) => f.to === id && f.status === 'accepted').map((f) => f.from) : s.social.follows.filter((f) => f.from === id && f.status === 'accepted').map((f) => f.to))
          .map((uid2) => userOf(s, uid2)).filter(Boolean).map((x) => <Card key={x!.id} className="list-row" onClick={() => { setList(null); go('/user/' + x!.id); }}><Avatar name={x!.name} color={x!.avatarColor} size={36} /><div><b>{x!.name}</b><small>@{x!.username}</small></div></Card>)}
        {u.sample && <p className="muted small">Sample accounts show illustrative follower counts.</p>}
      </Sheet>
    </div>
  );
}

export function Bookmarks() {
  const s = useStore((x) => x);
  const posts = s.social.posts.filter((p) => s.social.bookmarks.includes(p.id));
  return <div className="page"><Header left={<BackBtn />} title="Saved posts" />{posts.map((p) => <PostCard key={p.id} p={p} />)}{!posts.length && <Empty icon="bookmark" title="Nothing saved" text="Tap the bookmark on any post to save it here." />}</div>;
}

export function SearchUsers() {
  const s = useStore((x) => x); const [q, setQ] = useState('');
  const res = s.social.users.filter((u) => !u.suspended && (u.name + u.username).toLowerCase().includes(q.toLowerCase()));
  return <div className="page"><Header left={<BackBtn />} title="Find people" />
    <div className="search"><Icon n="search" s={18} /><input autoFocus value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search name or @username" /></div>
    {res.map((u) => <Card key={u.id} className="list-row" onClick={() => go('/user/' + u.id)}><Avatar name={u.name} color={u.avatarColor} size={40} /><div style={{ flex: 1 }}><b>{u.name}{u.creator && <span className="verified">✓</span>}</b><small>@{u.username}{u.private ? ' · private' : ''}</small></div><Icon n="chev" s={18} /></Card>)}
  </div>;
}

export function Notifications() {
  const s = useStore((x) => x); const me = s.profile!;
  const requests = s.social.follows.filter((f) => f.to === me.userId && f.status === 'pending');
  React.useEffect(() => { const t = setTimeout(() => update((d) => { d.notifications.forEach((n) => { n.read = true; }); }), 1500); return () => clearTimeout(t); }, []);
  const icon: Record<string, string> = { like: 'heart', comment: 'comment', follow: 'user', request: 'user', mention: 'comment', achievement: 'trophy', challenge: 'trophy', system: 'bell' };
  return <div className="page"><Header left={<BackBtn />} title="Notifications" />
    {requests.length > 0 && <Card><span className="lbl">Follow requests</span>{requests.map((r) => { const u = userOf(s, r.from); return <div key={r.from} className="list-row"><Avatar name={u?.name || '?'} color={u?.avatarColor} size={36} /><div style={{ flex: 1 }}><b>{u?.name}</b><small>@{u?.username}</small></div>
      <Btn small onClick={() => update((d) => { const f = d.social.follows.find((x) => x.from === r.from && x.to === me.userId)!; f.status = 'accepted'; notify(d, { type: 'follow', text: `@${u?.username} now follows you` }); })}>Accept</Btn>
      <Btn small kind="ghost" onClick={() => update((d) => { d.social.follows = d.social.follows.filter((x) => !(x.from === r.from && x.to === me.userId)); })}>Decline</Btn></div>; })}</Card>}
    {s.notifications.map((n) => <Card key={n.id} className={'notif' + (n.read ? '' : ' unread')} onClick={() => n.postId && go('/post/' + n.postId)}><span className="notif-i"><Icon n={icon[n.type]} s={18} /></span><div><p>{n.text}</p><small>{fmt.ago(n.ts)}</small></div></Card>)}
    {!s.notifications.length && !requests.length && <Empty icon="bell" title="You're all caught up" text="Likes, comments, follows, mentions, PRs and badges appear here." />}
  </div>;
}

// ─────────── Challenges ───────────
export function Challenges() {
  const s = useStore((x) => x);
  const [open, setOpen] = useState<string | null>(null);
  const earned = Object.keys(s.achievements).length;
  return <div className="page"><Header left={<BackBtn />} title="Challenges" />
    {CHALLENGES.map((c) => { const pr = challengeProgress(s, c); return (
      <Card key={c.id} className="chal" onClick={() => setOpen(c.id)}>
        <span className="chal-e">{c.emoji}</span>
        <div style={{ flex: 1 }}><b>{c.name}</b><small>{pr ? (pr.complete ? '✅ Completed!' : `${pr.done}/${pr.total} ${c.auto === 'workout' ? 'weeks' : 'days'} · today: ${c.auto === 'water' ? 'hit water target' : fmt.n(pr.todayTarget) + ' ' + c.unit}`) : `${c.days} days · tap to join`}</small>
          {pr && <div className="bar"><i style={{ width: `${pr.pct * 100}%` }} /></div>}</div>
      </Card>); })}
    <div className="row-b sec-h"><h3>Badges</h3><span className="muted small">{earned}/{ACHIEVEMENTS.length}</span></div>
    <div className="badges">{ACHIEVEMENTS.map((a) => <div key={a.id} className={'bdg' + (s.achievements[a.id] ? ' on' : '')}><span>{a.emoji}</span><b>{a.name}</b><small>{a.desc}</small></div>)}</div>
    <ChallengeSheet id={open} onClose={() => setOpen(null)} />
  </div>;
}
function ChallengeSheet({ id, onClose }: { id: string | null; onClose: () => void }) {
  const s = useStore((x) => x); const c = CHALLENGES.find((x) => x.id === id); const [val, setVal] = useState(0);
  if (!c) return null;
  const pr = challengeProgress(s, c); const j = s.challenges[c.id]; const me = s.profile!;
  const todayVal = j?.log[today()] || (c.auto === 'steps' ? s.steps[today()] : 0) || 0;
  // Optional leaderboard: you + sample participants. Opt-in via Privacy settings.
  const board = [
    ...(me.leaderboard && pr ? [{ name: me.name + ' (you)', v: pr.done }] : []),
    { name: 'Rahul (sample)', v: Math.min(c.days, 12) }, { name: 'Anu (sample)', v: Math.min(c.days, 9) }, { name: 'Arjun (sample)', v: Math.min(c.days, 17) },
  ].sort((a, b) => b.v - a.v);
  return <Sheet open onClose={onClose} title={`${c.emoji} ${c.name}`}>
    <p className="muted">{c.desc}</p>
    {!j ? <Btn full onClick={() => { update((d) => { d.challenges[c.id] = { joined: Date.now(), log: {} }; notify(d, { type: 'challenge', text: `You joined ${c.name}. Day 1 starts today!` }); }); checkAchievements(); toast('Challenge joined!'); }}>Join challenge</Btn> : <>
      <div className="ex-stats"><div><small>Day</small><b>{pr!.dayIdx + 1}/{c.days}</b></div><div><small>Completed</small><b>{pr!.done}</b></div><div><small>Today</small><b>{c.auto === 'water' ? '💧' : fmt.n(pr!.todayTarget)}</b></div></div>
      {!c.auto || c.auto === 'steps' ? <><Field label={`Log today (${c.unit}) — logged: ${fmt.n(todayVal)}`}><NumIn value={val || (c.unit === 'check-in' ? 1 : pr!.todayTarget)} step={c.unit === 'steps' ? 500 : c.unit === 'seconds' ? 5 : 1} onChange={setVal} suffix={c.unit} /></Field>
        <Btn full onClick={() => { const v = val || (c.unit === 'check-in' ? 1 : pr!.todayTarget); update((d) => { d.challenges[c.id].log[today()] = v; if (c.auto === 'steps') d.steps[today()] = v; }); toast('Logged ✅'); }}>Save today's progress</Btn></>
        : <p className="muted small">Progress updates automatically from your {c.auto === 'water' ? 'water' : 'workout'} log.</p>}
      <h4 className="sec-h">Leaderboard <small className="muted">(optional)</small></h4>
      {board.map((b, i) => <div key={i} className="lb-row"><span>{i + 1}</span><b>{b.name}</b><em>{b.v} {c.auto === 'workout' ? 'wks' : 'days'}</em></div>)}
      {!me.leaderboard && <p className="muted small">You're hidden from leaderboards. Change this in Settings → Privacy.</p>}
      <Btn full kind="ghost" onClick={async () => { if (await ask('Leave this challenge? Progress will be lost.')) { update((d) => { delete d.challenges[c.id]; }); onClose(); } }}>Leave challenge</Btn>
    </>}
  </Sheet>;
}
