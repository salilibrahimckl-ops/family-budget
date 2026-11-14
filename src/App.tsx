import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { useStore, getState, update, notify, subscribe } from './lib/store';
import { useRoute, Icon, Toasts, go } from './ui';
import { Welcome, AuthScreen } from './screens/Auth';
import { Onboarding } from './screens/Onboarding';
import { Home } from './screens/Home';
import { Train, ExerciseDetail, ProgramDetail, RoutineEditor, ActiveWorkout, WorkoutStart, WorkoutSummary } from './screens/Train';
import { Nutrition, AddFood, Water, Body, Targets } from './screens/Nutrition';
import { Messages, ChatThread } from './screens/Chat';
import { Invite } from './screens/Invite';
import { LogActivity } from './screens/Activity';
import { FriendChallengeDetail, refreshFriendChallenges } from './screens/FriendChallenges';
import { Feed, PostDetail, NewPost, UserProfile, Notifications, Challenges, Bookmarks, SearchUsers } from './screens/Social';
import { Me, EditProfile, Settings, Premium, Coach } from './screens/Profile';
import { Admin } from './screens/Admin';
import { Dialogs } from './lib/dialog';
import { CHALLENGES, startWebReminderLoop, t, isNative, toast } from './lib/extras';
import { initReminders, requestPermission, scheduleAll } from './lib/reminders';
import { markBootOk, startWebAutoUpdate } from './lib/updater';
import { syncWatch } from './lib/watch';
import { UpdatePrompt } from './screens/UpdatePrompt';
import { consumeOAuthHash, isCloud, syncUp, pullFeed, bg, ensureProfile, pushStats } from './lib/cloud';
import { weekStats } from './lib/activity';

function TabBar({ cur }: { cur: string }) {
  const tabs: [string, string, string][] = [['home', 'home', t('home')], ['train', 'train', t('train')], ['nutrition', 'food', t('nutrition')], ['community', 'users', t('community')], ['me', 'user', t('profile')]];
  const active = useStore((s) => !!s.active);
  return (
    <nav className="tabbar">
      {tabs.map(([k, ic, l]) => <button key={k} className={cur === k ? 'on' : ''} onClick={() => go('/' + k)} aria-label={l}><Icon n={ic} s={23} w={cur === k ? 2.4 : 1.9} /><span>{l}</span>{k === 'train' && active && <i className="live-dot" />}</button>)}
    </nav>
  );
}

function Routes() {
  const { parts } = useRoute();
  const [a, b] = parts;
  switch (a) {
    case 'home': case undefined: return <Home />;
    case 'train': return <Train />;
    case 'exercise': return <ExerciseDetail key={b} id={b} />;
    case 'program': return <ProgramDetail id={b} />;
    case 'routine': return <RoutineEditor id={b} />;
    case 'workout': return b === 'start' ? <WorkoutStart parts={parts} /> : <ActiveWorkout />;
    case 'workout-summary': return <WorkoutSummary id={b} />;
    case 'nutrition': return <Nutrition />;
    case 'food': return <AddFood />;
    case 'water': return <Water />;
    case 'body': return <Body />;
    case 'targets': return <Targets />;
    case 'community': return <Feed />;
    case 'post': return <PostDetail id={b} />;
    case 'new-post': return <NewPost />;
    case 'user': return <UserProfile key={b} id={b} />;
    case 'notifications': return <Notifications />;
    case 'challenges': return <Challenges />;
    case 'bookmarks': return <Bookmarks />;
    case 'search-users': return <SearchUsers />;
    case 'invite': return <Invite />;
    case 'activity': return <LogActivity key={location.hash} />;
    case 'fchallenge': return <FriendChallengeDetail key={b} id={b} />;
    case 'messages': return <Messages />;
    case 'chat': return <ChatThread key={b} other={b} />;
    case 'me': return <Me />;
    case 'edit-profile': return <EditProfile />;
    case 'settings': return <Settings />;
    case 'premium': return <Premium />;
    case 'coach': return <Coach />;
    case 'admin': return <Admin />;
    default: return <Home />;
  }
}

function App() {
  const session = useStore((s) => s.session);
  const profile = useStore((s) => s.profile);
  const theme = useStore((s) => s.settings.theme);
  const seenIntro = useStore((s) => s.settings.seenIntro);
  const [authMode, setAuthMode] = useState<'login' | 'register' | null>(null);
  const { parts } = useRoute();

  useEffect(() => { document.documentElement.dataset.theme = theme; const m = document.querySelector('meta[name=theme-color]'); m?.setAttribute('content', theme === 'dark' ? '#0A0C0F' : '#F5F6F2'); }, [theme]);
  useEffect(() => {
    // restore admin-created challenges
    for (const c of getState().customChallenges) if (!CHALLENGES.find((x) => x.id === c.id)) CHALLENGES.push({ ...c, targetFor: () => c.target });
    if (location.hash.includes('access_token=')) consumeOAuthHash(location.hash).then(() => { location.hash = '#/community'; }).catch(() => {});
    if (location.hash.includes('error_description=')) { const m = new URLSearchParams(location.hash.slice(1)).get('error_description'); if (m) setTimeout(() => toast('Sign-in: ' + m), 600); location.hash = '#/home'; }
    const capApp = (window as any).Capacitor?.Plugins?.App;
    capApp?.addListener?.('appUrlOpen', (e: any) => { const h = e.url.split('#')[1]; if (h) consumeOAuthHash('#' + h).then((ok) => { if (ok) toast('Signed in — welcome to the community!'); }).catch((x) => toast('Sign-in failed: ' + x.message)); });
    capApp?.addListener?.('backButton', () => { if (location.hash && !['#/home', '#/', ''].includes(location.hash)) history.back(); else capApp.exitApp?.(); });
    startWebReminderLoop();
    setTimeout(() => syncWatch().catch(() => undefined), 2500);
    capApp?.addListener?.('appStateChange', (st: any) => { if (st?.isActive) syncWatch().catch(() => undefined); });
    markBootOk(); startWebAutoUpdate();
    initReminders((r) => go(r));
  }, []);
  useEffect(() => {
    if (!session || !profile || !isCloud(getState())) return;
    bg(ensureProfile().then(() => syncUp())); bg(pullFeed());
    // Weekly totals for the friends leaderboard: send on open and whenever a workout/sport changes them.
    let lastKey = '', timer: any = 0;
    const pushIfChanged = (force = false) => {
      const st = weekStats(getState()); const key = [st.week, st.kcal, st.minutes, st.workouts, st.streak].join('|');
      if (!force && key === lastKey) return; lastKey = key;
      clearTimeout(timer); timer = setTimeout(() => { pushStats(st).catch((e) => { lastKey = ''; console.warn('stats', e); }); refreshFriendChallenges().catch(() => undefined); }, force ? 0 : 2500);
    };
    setTimeout(() => pushIfChanged(true), 3000);
    const unsub = subscribe(() => pushIfChanged());
    const i = setInterval(() => { bg(syncUp()); bg(pullFeed()); pushIfChanged(true); }, 5 * 60e3);
    return () => { clearInterval(i); clearTimeout(timer); unsub(); };
  }, [session?.userId, !!profile]);
  useEffect(() => {
    if (profile && isNative() && !getState().settings.notify?.asked) { update((d) => { d.settings.notify = { ...(d.settings.notify || {} as any), asked: true } as any; }); setTimeout(() => requestPermission().then(() => scheduleAll()), 1500); }
    if (profile && !getState().notifications.length) update((d) => notify(d, { type: 'system', text: 'Welcome to Bro’s Fitness! Your plan and targets are ready. Tap Train to start today\'s workout.' }));
  }, [!!profile]);

  if (!session) {
    if (!seenIntro && !authMode) return <><Welcome onDone={(m) => { update((d) => { d.settings.seenIntro = true; }); setAuthMode(m); }} /><Toasts /><Dialogs /></>;
    return <><AuthScreen initial={authMode || 'login'} key={authMode || 'login'} /><Toasts /><Dialogs /></>;
  }
  if (!profile || profile.userId !== session.userId) return <><Onboarding /><Toasts /><Dialogs /></>;
  const tabRoots = ['home', 'train', 'nutrition', 'community', 'me', undefined];
  const showTabs = tabRoots.includes(parts[0]);
  return (
    <div className={'app' + (showTabs ? ' with-tabs' : '')}>
      <main className="main"><Routes /></main>
      {showTabs && <TabBar cur={parts[0] || 'home'} />}
      <UpdatePrompt />
      <Toasts /><Dialogs />
    </div>
  );
}

createRoot(document.getElementById('root')!).render(<App />);
if ('serviceWorker' in navigator && location.protocol === 'https:' && !isNative() && (window as any).__FV_SW__) navigator.serviceWorker.register('sw.js').catch(() => {});
