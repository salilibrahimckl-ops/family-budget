// Invite friends: one message with the Android download and the iPhone web-app link.
import React from 'react';
import { useStore } from '../lib/store';
import { Header, BackBtn, Card, Btn, Icon } from '../ui';
import { share, toast } from '../lib/extras';
import { APK_URL } from '../lib/updater';
import { WEB_APP_URL } from './Join';

export function inviteText(username?: string) {
  return `Train with me on Bro’s Fitness 💪 — workouts with video + 3D muscle guide, Kerala-friendly nutrition, and a community to chat.\n\n` +
    `📱 Android: ${APK_URL}\n(open the file, allow “install unknown apps” if asked)\n\n` +
    `🍎 iPhone: ${WEB_APP_URL}\n(open in Safari → Share → Add to Home Screen)\n\n` +
    (username ? `Find me as @${username} 🙌` : 'Sign in with your email — no password needed.');
}
const copy = async (t: string, what: string) => { try { await navigator.clipboard.writeText(t); toast(what + ' copied'); } catch { share(t); } };

export function Invite() {
  const u = useStore((s) => s.profile?.username);
  const text = inviteText(u);
  return (
    <div className="page">
      <Header left={<BackBtn />} title="Invite friends" />
      <Card className="invite-hero">
        <div style={{ fontSize: 40 }}>🏋️‍♂️🤝</div>
        <b>Bring your gym buddies</b>
        <p className="muted">One message works for both Android and iPhone. Free, no app store needed.</p>
        <Btn full icon="share" onClick={() => share(text, 'Join me on Bro’s Fitness')}>Share invite</Btn>
        <Btn full kind="soft" onClick={() => { location.href = 'https://wa.me/?text=' + encodeURIComponent(text); }}>Send on WhatsApp</Btn>
      </Card>
      <Card>
        <span className="lbl">📱 Android</span>
        <p className="muted small">Downloads the app (APK). Friends open the file and allow “install unknown apps” once. Later updates come through the in-app Update button.</p>
        <div className="invite-link"><code>{APK_URL}</code><button onClick={() => copy(APK_URL, 'Android link')} aria-label="Copy"><Icon n="copy" s={18} /></button></div>
      </Card>
      <Card>
        <span className="lbl">🍎 iPhone</span>
        <p className="muted small">Open in Safari → Share → <b>Add to Home Screen</b>. It always runs the latest version.</p>
        <div className="invite-link"><code>{WEB_APP_URL}</code><button onClick={() => copy(WEB_APP_URL, 'iPhone link')} aria-label="Copy"><Icon n="copy" s={18} /></button></div>
      </Card>
      {u && <p className="muted small center">Friends can find you in Community search as <b>@{u}</b>.</p>}
    </div>
  );
}
