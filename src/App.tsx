import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { useStore, getState, update, notify } from './lib/store';
import { useRoute, Icon, Toasts, go } from './ui';
import { Welcome, AuthScreen } from './screens/Auth';
import { Onboarding } from './screens/Onboarding';
import { Home } from './screens/Home';
import { Train, ExerciseDetail, ProgramDetail, RoutineEditor, ActiveWorkout, WorkoutStart, WorkoutSummary } from './screens/Train';
import { Nutrition, AddFood, Water, Body, Targets } from './screens/Nutrition';
import { Feed, PostDetail, NewPost, UserProfile, Notifications, Challenges, Bookmarks, SearchUsers } from './screens/Social';
import { Me, EditProfile, Settings, Premium, Coach } from './screens/Profile';
import { Admin } from './screens/Admin';
import { Dialogs } from './lib/dialog';
import { CHALLENGES, startWebReminderLoop, t, isNative } from './lib/extras';
import { initReminders, requestPermission, scheduleAll } from './lib/reminders';
import { markBootOk } from './lib/updater';
import { consumeOAuthHash, isCloud, syncUp, pullFeed, bg } from './lib/cloud';

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
    if (location.hash.includes('access_token=')) consumeOAuthHash(location.hash).then(() => { location.hash = '#/home'; }).catch(() => {});
    const capApp = (window as any).Capacitor?.Plugins?.App;
    capApp?.addListener?.('appUrlOpen', (e: any) => { const h = e.url.split('#')[1]; if (h) consumeOAuthHash('#' + h); });
    capApp?.addListener?.('backButton', () => { if (location.hash && !['#/home', '#/', ''].includes(location.hash)) history.back(); else capApp.exitApp?.(); });
    startWebReminderLoop();
    markBootOk();
    initReminders((r) => go(r));
  }, []);
  useEffect(() => {
    if (!session || !profile || !isCloud(getState())) return;
    bg(syncUp()); bg(pullFeed());
    const i = setInterval(() => bg(syncUp()), 5 * 60e3);
    return () => clearInterval(i);
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
      <Toasts /><Dialogs />
    </div>
  );
}

createRoot(document.getElementById('root')!).render(<App />);
if ('serviceWorker' in navigator && location.protocol === 'https:' && !isNative() && (window as any).__FV_SW__) navigator.serviceWorker.register('sw.js').catch(() => {});
