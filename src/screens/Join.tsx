// One sign-in for the whole app: Google account or just an email address (6-digit code). No extra community login.
import React, { useState } from 'react';
import { useStore } from '../lib/store';
import { Btn, Field, Icon, Sheet } from '../ui';
import { cloudReady, isCloud, oauthUrl, sendEmailCode, verifyEmailCode, providers, cloudSignIn, cloudSignUp, applySession } from '../lib/cloud';
import { toast } from '../lib/extras';

export const GoogleG = () => <svg width="18" height="18" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z" /><path fill="#FF3D00" d="m6.3 14.7 6.6 4.8C14.7 15.1 19 12 24 12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" /><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z" /><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z" /></svg>;

export function useCloud() {
  const ready = useStore(() => cloudReady());
  const signedIn = useStore((s) => isCloud(s));
  const email = useStore((s) => s.session?.email || '');
  return { ready, signedIn, email };
}
export function googleSignIn() { location.href = oauthUrl('google'); }
/** Full web app (iPhone / any browser) — the claude.ai preview can't reach the community server. */
export const WEB_APP_URL = 'https://salilibrahimckl-ops.github.io/family-budget/fitness/';
export const inPreview = () => { try { return window.top !== window && !(window as any).Capacitor?.isNativePlatform?.(); } catch { return true; } };
const netMsg = (e: any) => (/failed to fetch|load failed|networkerror/i.test(e?.message || '') ? 'Can’t reach the community server. Check your internet, or open the full app: ' + WEB_APP_URL : e?.message || 'Something went wrong');

/** "Continue with Google" + "Continue with email" buttons. */
export function SignInButtons({ onEmail }: { onEmail?: () => void }) {
  const [open, setOpen] = useState(false);
  const [google, setGoogle] = useState(false);
  React.useEffect(() => { let on = true; providers().then((p) => on && setGoogle(p.google)); return () => { on = false; }; }, []);
  return (
    <div className="join-btns">
      {google && <button className="g-btn" onClick={googleSignIn}><GoogleG /> Continue with Google</button>}
      <button className="e-btn" onClick={() => (onEmail ? onEmail() : setOpen(true))}><Icon n="send" s={17} /> Continue with email</button>
      <EmailCodeSheet open={open} onClose={() => setOpen(false)} />
    </div>
  );
}

export function EmailCodeSheet({ open, onClose, onDone }: { open: boolean; onClose: () => void; onDone?: () => void }) {
  const [email, setEmail] = useState(''); const [pw, setPw] = useState(''); const [code, setCode] = useState(''); const [show, setShow] = useState(false);
  const [step, setStep] = useState<'pw' | 'link' | 'sent'>('pw'); const [busy, setBusy] = useState(false); const [err, setErr] = useState('');
  const emRef = React.useRef<HTMLInputElement>(null); const pwRef = React.useRef<HTMLInputElement>(null);
  // iPhone autofill sometimes fills the box without telling React — read the box itself too.
  const em = () => (email || emRef.current?.value || '').trim().toLowerCase();
  const pass = () => pw || pwRef.current?.value || '';
  const valid = (e: string) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e);
  const done = (who: string) => { toast('Signed in as ' + who); onClose(); onDone?.(); setStep('pw'); setCode(''); setPw(''); };
  async function withPassword() {
    const e = em(), p = pass(); setErr('');
    if (!valid(e)) return setErr('Type your email address.');
    if (p.length < 6) return setErr('Choose a password of at least 6 characters.');
    setBusy(true);
    try {
      try { const t = await cloudSignIn(e, p); applySession(t); return done(e); }
      catch (x: any) { if (!/invalid login|invalid credentials|not found/i.test(x.message)) throw x; }
      // New here (or wrong password): try creating the account.
      try {
        const r = await cloudSignUp(e, p);
        if ('needsConfirm' in r && r.needsConfirm) { setErr('Account created — open the confirmation email once, then sign in here.'); return; }
        applySession(r as any); return done(e);
      } catch (x: any) {
        if (/already registered|already exists/i.test(x.message)) return setErr('Wrong password for this email. Try again, or use “Email me a sign-in link” below.');
        throw x;
      }
    } catch (x: any) { setErr(friendly(x)); } finally { setBusy(false); }
  }
  async function sendLink() {
    const e = em(); if (!valid(e)) return setErr('Type your email address.');
    setBusy(true); setErr('');
    try { await sendEmailCode(e); setStep('sent'); } catch (x: any) { setErr(friendly(x)); } finally { setBusy(false); }
  }
  async function verify() {
    if (code.replace(/\D/g, '').length < 6) return setErr('Type the 6-digit code from the email.');
    setBusy(true); setErr('');
    try { await verifyEmailCode(em(), code.replace(/\D/g, '')); done(em()); }
    catch (x: any) { setErr(/expired|invalid/i.test(x.message) ? 'That code is wrong or expired.' : friendly(x)); } finally { setBusy(false); }
  }
  const emailBox = <Field label="Your email"><input ref={emRef} type="email" inputMode="email" autoComplete="email" autoCapitalize="none" autoCorrect="off" value={email} onChange={(e) => setEmail(e.target.value)} onInput={(e) => setEmail((e.target as HTMLInputElement).value)} placeholder="you@gmail.com" /></Field>;
  return (
    <Sheet open={open} onClose={onClose} title={step === 'sent' ? 'Check your email' : 'Sign in with email'}>
      {step === 'pw' && <>
        <p className="muted">Use your email and a password. New here? The same button creates your account. Works on every phone.</p>
        {emailBox}
        <Field label="Password"><div className="pw"><input ref={pwRef} type={show ? 'text' : 'password'} autoComplete="current-password" value={pw} onChange={(e) => setPw(e.target.value)} onInput={(e) => setPw((e.target as HTMLInputElement).value)} onKeyDown={(e) => e.key === 'Enter' && withPassword()} placeholder="6+ characters" /><button type="button" onClick={() => setShow(!show)}>{show ? 'Hide' : 'Show'}</button></div></Field>
        {err && <div className="err">{err}</div>}
        <Btn full disabled={busy} onClick={withPassword}>{busy ? 'Please wait…' : 'Continue'}</Btn>
        <button className="link" onClick={() => { setStep('link'); setErr(''); }}>Forgot password / prefer no password? Email me a sign-in link</button>
      </>}
      {step === 'link' && <>
        <p className="muted">We’ll email you a link — tap it on this phone to sign in. (Only a few emails can be sent per hour.)</p>
        {emailBox}
        {err && <div className="err">{err}</div>}
        <Btn full disabled={busy} onClick={sendLink}>{busy ? 'Sending…' : 'Email me a sign-in link'}</Btn>
        <button className="link" onClick={() => { setStep('pw'); setErr(''); }}>Use a password instead</button>
      </>}
      {step === 'sent' && <>
        <p className="muted">We sent an email to <b>{em()}</b>. Open it on this phone and tap <b>Sign in</b>. (Check Spam.)</p>
        <p className="muted small">If it shows a 6-digit code, type it here:</p>
        <Field label="Code"><input className="otp" inputMode="numeric" autoComplete="one-time-code" maxLength={8} value={code} onChange={(e) => setCode(e.target.value.replace(/[^0-9]/g, ''))} placeholder="••••••" /></Field>
        {err && <div className="err">{err}</div>}
        <Btn full disabled={busy} onClick={verify}>{busy ? 'Checking…' : 'Sign in with code'}</Btn>
        <button className="link" onClick={() => { setStep('pw'); setErr(''); }}>Back</button>
      </>}
    </Sheet>
  );
}
const friendly = (x: any) => /rate limit|too many|security purposes/i.test(x?.message || '') ? 'Too many emails right now — use “Continue” with a password instead (no email needed).' : netMsg(x);

/** Friendly card shown in Community / Chat when this phone isn't signed in yet. */
export function JoinCard({ title = 'Join the Bro’s community', text = 'Post, comment and chat with friends using the Google account or email you already have. Your workouts stay on this phone.' }: { title?: string; text?: string }) {
  const { ready } = useCloud();
  return (
    <div className="join-card">
      <div className="join-ico">👋</div>
      <b>{title}</b>
      {ready && inPreview() ? <><p>This preview can’t connect to the community. Open the full Bro’s Fitness web app (and add it to your Home Screen) to post and chat.</p><a className="g-btn join-link" href={WEB_APP_URL} target="_blank" rel="noreferrer">Open the full app</a></>
        : ready ? <><p>{text}</p><SignInButtons /></>
        : <p>The community server isn’t connected in this version yet, so posts and chats stay on this phone for now. It turns on automatically with an app update — no extra login needed.</p>}
    </div>
  );
}
