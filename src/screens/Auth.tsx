import React, { useState } from 'react';
import { update, useStore, uid, hashPw, getState } from '../lib/store';
import { cloudReady, cloudSignIn, cloudSignUp, cloudRecover } from '../lib/cloud';
import { Btn, Field, Logo, Wordmark, Icon } from '../ui';
import { toast } from '../lib/extras';
import { SignInButtons, inPreview } from './Join';

const SLIDES = [
  { t: 'Train anywhere', d: '100 exercises with video demos, step-by-step form and safety cues — plus an instant home version of every gym move.', e: '🏋️', c: ['#D4FF3A', '#22E3B5'] },
  { t: 'Eat with a plan', d: 'Calories and macros built from Mifflin-St Jeor and your goal. Log rice, puttu, dosa or chicken in plain English.', e: '🍛', c: ['#FFB020', '#FF5A36'] },
  { t: 'Rise together', d: 'Share workouts and transformations, join challenges and earn badges. Your body data stays private unless you choose.', e: '🔥', c: ['#B388FF', '#4FC3F7'] },
];

export function Welcome({ onDone }: { onDone: (mode: 'login' | 'register') => void }) {
  const [i, setI] = useState(0); const s = SLIDES[i];
  React.useEffect(() => { const t = setInterval(() => setI((x) => (x + 1) % SLIDES.length), 4000); return () => clearInterval(t); }, []);
  function quickStart() {
    const id = 'u-' + uid();
    update((d) => { d.accounts.push({ email: 'guest:' + id, salt: '', hash: '', userId: id }); d.session = { userId: id, email: 'guest', mode: 'local' }; d.settings.seenIntro = true; d.settings.admin = d.accounts.length === 1; });
  }
  return (
    <div className="welcome">
      <div className="welcome-top"><Logo s={44} /><Wordmark size={20} /></div>
      <div className="welcome-art" style={{ background: `radial-gradient(circle at 30% 30%, ${s.c[0]}55, transparent 60%), radial-gradient(circle at 75% 70%, ${s.c[1]}55, transparent 60%)` }}>
        <div className="welcome-emoji" key={i}>{s.e}</div>
        <div className="orbit" />
      </div>
      <div className="welcome-txt" key={'t' + i}><h2>{s.t}</h2><p>{s.d}</p></div>
      <div className="dots">{SLIDES.map((_, k) => <i key={k} className={k === i ? 'on' : ''} onClick={() => setI(k)} />)}</div>
      <div className="welcome-cta">
        {cloudReady() && !inPreview() ? <>
          <SignInButtons />
          <p className="muted small center" style={{ margin: '2px 0 0' }}>One sign-in for workouts, community and chat. No new password.</p>
          <Btn full kind="ghost" onClick={quickStart}>Try it first without an account</Btn>
        </> : <>
          <Btn full onClick={quickStart}>Get started — it’s free</Btn>
          <p className="muted small center" style={{ margin: '2px 0 4px' }}>No sign-up needed. Takes about 30 seconds.</p>
          <Btn full kind="ghost" onClick={() => onDone('login')}>I already have an account</Btn>
        </>}
      </div>
    </div>
  );
}

export function AuthScreen({ initial }: { initial: 'login' | 'register' }) {
  const [mode, setMode] = useState<'login' | 'register' | 'forgot'>(initial);
  const [email, setEmail] = useState(''); const [pw, setPw] = useState(''); const [pw2, setPw2] = useState('');
  const [show, setShow] = useState(false); const [busy, setBusy] = useState(false); const [err, setErr] = useState('');
  const cloud = useStore(() => cloudReady());

  const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.trim());
  const strong = pw.length >= 8 && /[A-Za-z]/.test(pw) && /\d/.test(pw);

  async function submit(e: React.FormEvent) {
    e.preventDefault(); setErr('');
    const em = email.trim().toLowerCase();
    if (!validEmail) return setErr('Enter a valid email address.');
    if (mode === 'forgot') {
      setBusy(true);
      try {
        if (cloud) { await cloudRecover(em); toast('Password reset email sent. Check your inbox.'); }
        else toast('On-device accounts have no email server. Use "Reset on this device" below, or connect Supabase in Settings for email recovery.');
        setMode('login');
      } catch (x: any) { setErr(x.message); } finally { setBusy(false); }
      return;
    }
    if (mode === 'register') {
      if (!strong) return setErr('Use at least 8 characters with letters and numbers.');
      if (pw !== pw2) return setErr('Passwords do not match.');
    }
    setBusy(true);
    try {
      if (cloud) {
        const r = mode === 'register' ? await cloudSignUp(em, pw) : await cloudSignIn(em, pw);
        if ('needsConfirm' in r && r.needsConfirm) { toast('Check your email to confirm your account, then sign in.'); setMode('login'); return; }
        const t = r as any;
        update((d) => { d.session = { userId: t.userId, email: em, mode: 'cloud', token: t.token, refresh: t.refresh, exp: t.exp }; });
      } else {
        const acc = getState().accounts.find((a) => a.email === em);
        if (mode === 'register') {
          if (acc) throw new Error('An account with this email already exists on this device. Sign in instead.');
          const salt = uid() + uid(); const hash = await hashPw(pw, salt); const id = 'u-' + uid();
          update((d) => { d.accounts.push({ email: em, salt, hash, userId: id }); d.session = { userId: id, email: em, mode: 'local' }; d.settings.admin = d.accounts.length === 1; });
        } else {
          if (!acc) throw new Error('No account found with this email on this device.');
          if ((await hashPw(pw, acc.salt)) !== acc.hash) throw new Error('Incorrect password.');
          update((d) => { d.session = { userId: acc.userId, email: em, mode: 'local' }; });
        }
      }
    } catch (x: any) { setErr(x.message || 'Something went wrong'); } finally { setBusy(false); }
  }


  function resetLocal() {
    const em = email.trim().toLowerCase(); const acc = getState().accounts.find((a) => a.email === em);
    if (!acc) return setErr('No on-device account with that email.');
    if (!strong) return setErr('Type a new password (8+ characters, letters and numbers) in the password box first.');
    hashPw(pw, acc.salt).then((h) => { update((d) => { const a = d.accounts.find((x) => x.email === em)!; a.hash = h; }); toast('Password updated on this device.'); setMode('login'); });
  }

  return (
    <div className="auth">
      <div className="auth-head"><Logo s={56} /><h2>{mode === 'register' ? 'Create account' : mode === 'login' ? 'Welcome back' : 'Reset password'}</h2>
        <p>{mode === 'register' ? 'Start your Bro’s Fitness journey.' : mode === 'login' ? 'Sign in to continue training.' : 'We\'ll help you get back in.'}</p></div>
      <form onSubmit={submit} className="auth-form">
        <Field label="Email"><input type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" /></Field>
        {mode !== 'forgot' && (
          <Field label="Password" hint={mode === 'register' ? (strong ? '✓ Strong enough' : '8+ characters, letters and numbers') : undefined}>
            <div className="pw"><input type={show ? 'text' : 'password'} autoComplete={mode === 'register' ? 'new-password' : 'current-password'} value={pw} onChange={(e) => setPw(e.target.value)} placeholder="••••••••" /><button type="button" onClick={() => setShow(!show)}>{show ? 'Hide' : 'Show'}</button></div>
          </Field>
        )}
        {mode === 'register' && <Field label="Confirm password"><input type={show ? 'text' : 'password'} value={pw2} onChange={(e) => setPw2(e.target.value)} placeholder="••••••••" /></Field>}
        {mode === 'forgot' && !cloud && <Field label="New password (on-device reset)"><input type="password" value={pw} onChange={(e) => setPw(e.target.value)} placeholder="New password" /></Field>}
        {err && <div className="err">{err}</div>}
        <Btn type="submit" full disabled={busy}>{busy ? 'Please wait…' : mode === 'register' ? 'Create account' : mode === 'login' ? 'Sign in' : 'Send reset link'}</Btn>
        {mode === 'forgot' && !cloud && <Btn full kind="soft" onClick={resetLocal}>Reset on this device</Btn>}
      </form>
      {mode !== 'forgot' && cloud && !inPreview() && <>
        <div className="or"><span>or</span></div>
        <SignInButtons />
      </>}
      <div className="auth-switch">
        {mode === 'login' && <><button onClick={() => setMode('forgot')}>Forgot password?</button><span>·</span><button onClick={() => setMode('register')}>Create account</button></>}
        {mode === 'register' && <button onClick={() => setMode('login')}>Already have an account? Sign in</button>}
        {mode === 'forgot' && <button onClick={() => setMode('login')}>Back to sign in</button>}
      </div>
      <p className="auth-note"><Icon n="shield" s={14} /> {cloud ? 'Your account works on every phone — Android and iPhone.' : 'On-device mode: your account and data stay on this phone.'}</p>
    </div>
  );
}
