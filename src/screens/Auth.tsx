import React, { useState } from 'react';
import { update, useStore, uid, hashPw, getState } from '../lib/store';
import { cloudReady, cloudSignIn, cloudSignUp, cloudRecover, oauthUrl } from '../lib/cloud';
import { Btn, Field, Logo, Wordmark, Icon, Sheet } from '../ui';
import { toast } from '../lib/extras';

const SLIDES = [
  { t: 'Train anywhere', d: '90+ exercises with step-by-step form, breathing and safety cues — and an instant home version of every gym move.', e: '🏋️', c: ['#D4FF3A', '#22E3B5'] },
  { t: 'Eat with a plan', d: 'Calories and macros built from Mifflin-St Jeor and your goal. Log rice, puttu, dosa or chicken in plain English.', e: '🍛', c: ['#FFB020', '#FF5A36'] },
  { t: 'Rise together', d: 'Share workouts and transformations, join challenges and earn badges. Your body data stays private unless you choose.', e: '🔥', c: ['#B388FF', '#4FC3F7'] },
];

export function Welcome({ onDone }: { onDone: (mode: 'login' | 'register') => void }) {
  const [i, setI] = useState(0); const s = SLIDES[i];
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
        {i < SLIDES.length - 1 ? <Btn full onClick={() => setI(i + 1)}>Continue</Btn> : <Btn full onClick={() => onDone('register')}>Create your account</Btn>}
        <Btn full kind="ghost" onClick={() => onDone('login')}>I already have an account</Btn>
      </div>
    </div>
  );
}

export function AuthScreen({ initial }: { initial: 'login' | 'register' }) {
  const [mode, setMode] = useState<'login' | 'register' | 'forgot'>(initial);
  const [email, setEmail] = useState(''); const [pw, setPw] = useState(''); const [pw2, setPw2] = useState('');
  const [show, setShow] = useState(false); const [busy, setBusy] = useState(false); const [err, setErr] = useState('');
  const [oauthInfo, setOauthInfo] = useState<string | null>(null);
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

  function oauth(p: 'google' | 'apple') {
    if (!cloud) { setOauthInfo(p); return; }
    location.href = oauthUrl(p);
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
        <p>{mode === 'register' ? 'Start your FITVERSE journey.' : mode === 'login' ? 'Sign in to continue training.' : 'We\'ll help you get back in.'}</p></div>
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
      {mode !== 'forgot' && <>
        <div className="or"><span>or continue with</span></div>
        <div className="oauth">
          <button onClick={() => oauth('google')}><svg width="18" height="18" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z" /><path fill="#FF3D00" d="m6.3 14.7 6.6 4.8C14.7 15.1 19 12 24 12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" /><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z" /><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z" /></svg>Google</button>
          <button onClick={() => oauth('apple')}><svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M16.4 12.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.4.8 1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.7-1-2.7-4.1zM13.9 5c.7-.9 1.2-2 1.1-3.2-1 0-2.3.7-3 1.6-.7.8-1.2 2-1.1 3.1 1.1.1 2.3-.6 3-1.5z" /></svg>Apple</button>
        </div>
      </>}
      <div className="auth-switch">
        {mode === 'login' && <><button onClick={() => setMode('forgot')}>Forgot password?</button><span>·</span><button onClick={() => setMode('register')}>Create account</button></>}
        {mode === 'register' && <button onClick={() => setMode('login')}>Already have an account? Sign in</button>}
        {mode === 'forgot' && <button onClick={() => setMode('login')}>Back to sign in</button>}
      </div>
      <p className="auth-note"><Icon n="shield" s={14} /> {cloud ? 'Cloud sync is on — your account is stored in your Supabase project.' : 'On-device mode: your account and data stay on this phone. Connect Supabase in Settings for cloud sync across devices.'}</p>
      <Sheet open={!!oauthInfo} onClose={() => setOauthInfo(null)} title={`${oauthInfo === 'google' ? 'Google' : 'Apple'} sign-in needs setup`}>
        <p className="muted">Social sign-in runs through Supabase Auth so no secret keys live in the app. To turn it on:</p>
        <ol className="steps-list">
          <li>Create a free project at supabase.com and run <code>supabase/schema.sql</code>.</li>
          <li>In Supabase → Authentication → Providers, enable {oauthInfo === 'google' ? 'Google (needs a Google Cloud OAuth client ID)' : 'Apple (needs an Apple Developer account)'}.</li>
          <li>Add <code>com.fitverse.app://auth-callback</code> to the allowed redirect URLs.</li>
          <li>In FITVERSE → Profile → Settings → Cloud, paste your project URL and anon key.</li>
        </ol>
        <p className="muted">Until then, create an account with email — it takes 10 seconds.</p>
        <Btn full onClick={() => { setOauthInfo(null); setMode('register'); }}>Use email instead</Btn>
      </Sheet>
    </div>
  );
}
