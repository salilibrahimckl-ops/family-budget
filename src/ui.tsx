// Bro’s Fitness design-system components.
import React, { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { getMedia } from './lib/store';
import { toastStore } from './lib/extras';

// ─── Router ───
export function useRoute() {
  const [h, setH] = useState(location.hash || '#/home');
  useEffect(() => { const f = () => setH(location.hash || '#/home'); addEventListener('hashchange', f); return () => removeEventListener('hashchange', f); }, []);
  const [path, qs] = h.slice(1).split('?');
  return { parts: path.split('/').filter(Boolean), q: new URLSearchParams(qs || '') };
}
export const go = (to: string) => { location.hash = to; };
export const back = () => { if (history.length > 1) history.back(); else go('/home'); };

// ─── Icons ───
const P: Record<string, string> = {
  home: 'M3 11.5 12 4l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z',
  train: 'M6.5 6.5v11M17.5 6.5v11M3.5 9v6M20.5 9v6M6.5 12h11',
  food: 'M7 3v8a2 2 0 0 0 2 2v8M11 3v8a2 2 0 0 1-2 2M9 3v6M17 21V3c-2.2 0-4 2.5-4 6v4h4',
  users: 'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM2 21c0-4 3-6 7-6s7 2 7 6M16 3.5a4 4 0 0 1 0 7.5M22 21c0-3-1.7-5-4.5-5.7',
  user: 'M12 12a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9zM4 21c0-4.4 3.6-7 8-7s8 2.6 8 7',
  plus: 'M12 5v14M5 12h14', search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM21 21l-5-5', back: 'M15 5l-7 7 7 7',
  heart: 'M12 20s-7.5-4.6-9.3-9.2C1.5 7.4 3.9 4 7.3 4c2 0 3.4 1.1 4.7 2.8C13.3 5.1 14.7 4 16.7 4c3.4 0 5.8 3.4 4.6 6.8C19.5 15.4 12 20 12 20z',
  copy: 'M9 9h11v11H9zM5 15H4V4h11v1', comment: 'M4 5h16v11H9l-5 4z', share: 'M4 12v7h16v-7M12 3v13M7 8l5-5 5 5', bookmark: 'M6 3h12v18l-6-4-6 4z',
  bell: 'M6 9a6 6 0 1 1 12 0c0 6 2.5 7.5 2.5 7.5h-17S6 15 6 9zM10 20a2 2 0 0 0 4 0', gear: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 13.5l1.6 1.2-2 3.4-1.9-.7a7 7 0 0 1-2.1 1.2L14.7 21h-4l-.3-2.4a7 7 0 0 1-2.1-1.2l-1.9.7-2-3.4 1.6-1.2a7 7 0 0 1 0-3L4.4 9.3l2-3.4 1.9.7a7 7 0 0 1 2.1-1.2L10.7 3h4l.3 2.4a7 7 0 0 1 2.1 1.2l1.9-.7 2 3.4-1.6 1.2a7 7 0 0 1 0 3z',
  play: 'M7 4l13 8-13 8z', pause: 'M7 4h4v16H7zM13 4h4v16h-4z', check: 'M4 12.5l5 5L20 6.5', x: 'M6 6l12 12M18 6L6 18', chev: 'M9 5l7 7-7 7',
  drop: 'M12 3s7 7.6 7 12a7 7 0 0 1-14 0c0-4.4 7-12 7-12z', flame: 'M12 22c4 0 7-2.8 7-7 0-5-4-7-5-11-2.5 2-3 4.5-3 6.5-1.5-.8-2-2.3-2-3.5C6.5 9 5 11.6 5 15c0 4.2 3 7 7 7z',
  timer: 'M12 22a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM12 10v4l2.5 2M9 2h6', camera: 'M4 7h3l2-3h6l2 3h3v13H4zM12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
  trophy: 'M7 4h10v5a5 5 0 0 1-10 0zM7 6H4c0 3 1.5 4.5 3.5 4.5M17 6h3c0 3-1.5 4.5-3.5 4.5M10 14.5V18h4v-3.5M8 21h8', more: 'M5 12h.01M12 12h.01M19 12h.01',
  chart: 'M4 20V10M10 20V4M16 20v-7M22 20H2', spark: 'M12 2l2.4 6.6L21 11l-6.6 2.4L12 20l-2.4-6.6L3 11l6.6-2.4z', scale: 'M5 20h14l-2-12H7zM9 8a3 3 0 1 1 6 0M12 12l2-2',
  swap: 'M7 4 3 8l4 4M3 8h14M17 20l4-4-4-4M21 16H7', edit: 'M4 20h4L19 9l-4-4L4 16zM14 6l4 4', trash: 'M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13', shield: 'M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z',
  lock: 'M6 11h12v10H6zM8 11V7a4 4 0 1 1 8 0v4', video: 'M3 6h12v12H3zM15 10l6-3v10l-6-3z', send: 'M3 11 21 3l-8 18-2-8z', calendar: 'M4 6h16v15H4zM4 10h16M8 3v4M16 3v4', fire: 'M12 22c4 0 7-2.8 7-7 0-5-4-7-5-11-2.5 2-3 4.5-3 6.5-1.5-.8-2-2.3-2-3.5C6.5 9 5 11.6 5 15c0 4.2 3 7 7 7z', mic: 'M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3zM5 11a7 7 0 0 0 14 0M12 18v3', barcode: 'M4 5v14M7 5v14M11 5v14M14 5v14M18 5v14M20 5v14', star: 'M12 3l2.8 5.8 6.2.9-4.5 4.4 1 6.3L12 17.5 6.5 20.4l1-6.3L3 9.7l6.2-.9z',
};
export function Icon({ n, s = 22, w = 2, fill }: { n: string; s?: number; w?: number; fill?: boolean }) {
  return <svg width={s} height={s} viewBox="0 0 24 24" fill={fill ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth={w} strokeLinecap="round" strokeLinejoin="round" aria-hidden><path d={P[n] || P.more} /></svg>;
}

export function Logo({ s = 40 }: { s?: number }) {
  return (
    <svg width={s} height={s} viewBox="0 0 512 512" aria-label="Bro’s Fitness">
      <defs>
        <linearGradient id="lg-o" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#D4FF3A" /><stop offset="1" stopColor="#22E3B5" /></linearGradient>
        <radialGradient id="lg-b" cx=".3" cy=".25" r=".9"><stop offset="0" stopColor="#1F2630" /><stop offset="1" stopColor="#07090C" /></radialGradient>
      </defs>
      <rect width="512" height="512" rx="116" fill="url(#lg-b)" />
      <g transform="rotate(-24 256 256)"><ellipse cx="256" cy="262" rx="196" ry="84" fill="none" stroke="url(#lg-o)" strokeWidth="24" strokeDasharray="860 210" strokeLinecap="round" /></g>
      <path d="M196 118h118c56 0 92 28 92 74 0 28-14 48-38 59 33 10 52 35 52 68 0 52-39 83-103 83H196zM258 170v62h52c21 0 34-12 34-31s-13-31-34-31zM258 284v66h60c23 0 37-13 37-33s-14-33-37-33z" fill="#fff" fillRule="evenodd" transform="skewX(-8) translate(24 0)" />
      <circle cx="420" cy="170" r="24" fill="#D4FF3A" />
    </svg>
  );
}
export function Wordmark({ size = 22 }: { size?: number }) {
  return <span className="wordmark" style={{ fontSize: size }}>BRO’S <span>FITNESS</span></span>;
}

// ─── Layout primitives ───
export function Header({ title, sub, left, right, big }: { title: React.ReactNode; sub?: React.ReactNode; left?: React.ReactNode; right?: React.ReactNode; big?: boolean }) {
  return (
    <header className={'hdr' + (big ? ' big' : '')}>
      <div className="hdr-l">{left}</div>
      <div className="hdr-t"><h1>{title}</h1>{sub && <p>{sub}</p>}</div>
      <div className="hdr-r">{right}</div>
    </header>
  );
}
export const BackBtn = () => <button className="icon-btn" onClick={back} aria-label="Back"><Icon n="back" /></button>;
export function Card({ children, className = '', onClick, style }: { children: React.ReactNode; className?: string; onClick?: () => void; style?: React.CSSProperties }) {
  return <div className={'card ' + className + (onClick ? ' tap' : '')} onClick={onClick} style={style}>{children}</div>;
}
export function Btn({ children, kind = 'primary', onClick, disabled, full, small, type, icon }: { children?: React.ReactNode; kind?: 'primary' | 'ghost' | 'soft' | 'danger' | 'white'; onClick?: (e: React.MouseEvent) => void; disabled?: boolean; full?: boolean; small?: boolean; type?: 'submit' | 'button'; icon?: string }) {
  return <button type={type || 'button'} className={`btn ${kind}${full ? ' full' : ''}${small ? ' small' : ''}`} onClick={onClick} disabled={disabled}>{icon && <Icon n={icon} s={small ? 16 : 18} />}{children}</button>;
}
export function Chip({ on, children, onClick }: { on?: boolean; children: React.ReactNode; onClick?: () => void }) {
  return <button className={'chip' + (on ? ' on' : '')} onClick={onClick}>{children}</button>;
}
export function Seg<T extends string>({ value, options, onChange }: { value: T; options: { v: T; l: string }[]; onChange: (v: T) => void }) {
  return <div className="seg">{options.map((o) => <button key={o.v} className={o.v === value ? 'on' : ''} onClick={() => onChange(o.v)}>{o.l}</button>)}</div>;
}
export function Field({ label, children, hint }: { label: string; children: React.ReactNode; hint?: string }) {
  return <label className="field"><span>{label}</span>{children}{hint && <small>{hint}</small>}</label>;
}
export function Toggle({ on, onChange, label, desc }: { on: boolean; onChange: (v: boolean) => void; label: string; desc?: string }) {
  return (
    <button className="toggle-row" onClick={() => onChange(!on)}>
      <div><b>{label}</b>{desc && <small>{desc}</small>}</div>
      <span className={'toggle' + (on ? ' on' : '')}><i /></span>
    </button>
  );
}
export function Sheet({ open, onClose, title, children }: { open: boolean; onClose: () => void; title?: string; children: React.ReactNode }) {
  if (!open) return null;
  return (
    <div className="sheet-bg" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()}>
        <div className="sheet-grip" />
        {title && <div className="sheet-h"><h3>{title}</h3><button className="icon-btn" onClick={onClose} aria-label="Close"><Icon n="x" /></button></div>}
        <div className="sheet-c">{children}</div>
      </div>
    </div>
  );
}
export function Empty({ icon, title, text, action }: { icon: string; title: string; text?: string; action?: React.ReactNode }) {
  return <div className="empty"><div className="empty-i"><Icon n={icon} s={30} /></div><b>{title}</b>{text && <p>{text}</p>}{action}</div>;
}
export function Stat({ label, value, unit, sub }: { label: string; value: React.ReactNode; unit?: string; sub?: React.ReactNode }) {
  return <div className="stat"><small>{label}</small><b>{value}{unit && <em>{unit}</em>}</b>{sub && <span>{sub}</span>}</div>;
}
export function Pill({ children, tone = 'n' }: { children: React.ReactNode; tone?: 'n' | 'lime' | 'warn' | 'bad' | 'info' | 'pro' }) {
  return <span className={'pill ' + tone}>{children}</span>;
}

// ─── Charts ───
export function Ring({ value, max, size = 120, stroke = 12, color = 'var(--lime)', children, track = 'var(--track)' }: { value: number; max: number; size?: number; stroke?: number; color?: string; children?: React.ReactNode; track?: string }) {
  const r = (size - stroke) / 2; const c = 2 * Math.PI * r; const pct = Math.max(0, Math.min(1, max ? value / max : 0));
  return (
    <div className="ring" style={{ width: size, height: size }}>
      <svg width={size} height={size}>
        <circle cx={size / 2} cy={size / 2} r={r} stroke={track} strokeWidth={stroke} fill="none" />
        <circle cx={size / 2} cy={size / 2} r={r} stroke={color} strokeWidth={stroke} fill="none" strokeLinecap="round" strokeDasharray={c} strokeDashoffset={c * (1 - pct)} style={{ transition: 'stroke-dashoffset .8s cubic-bezier(.2,.8,.2,1)' }} transform={`rotate(-90 ${size / 2} ${size / 2})`} />
        {value > max && max > 0 && <circle cx={size / 2} cy={size / 2} r={r} stroke="var(--coral)" strokeWidth={stroke} fill="none" strokeLinecap="round" strokeDasharray={c} strokeDashoffset={c * (1 - Math.min(1, (value - max) / max))} transform={`rotate(-90 ${size / 2} ${size / 2})`} opacity=".9" />}
      </svg>
      <div className="ring-c">{children}</div>
    </div>
  );
}
export function Bar({ value, max, color = 'var(--lime)' }: { value: number; max: number; color?: string }) {
  return <div className="bar"><i style={{ width: `${Math.min(100, max ? (value / max) * 100 : 0)}%`, background: value > max * 1.05 ? 'var(--coral)' : color }} /></div>;
}
export function LineChart({ data, height = 160, unit = '', goal, color = 'var(--lime)' }: { data: { x: string; y: number }[]; height?: number; unit?: string; goal?: number; color?: string }) {
  const W = 340; const H = height; const pad = { l: 34, r: 10, t: 12, b: 22 };
  if (data.length < 2) return <div className="chart-empty">Add at least two entries to see a trend.</div>;
  const ys = data.map((d) => d.y).concat(goal !== undefined ? [goal] : []);
  let mn = Math.min(...ys); let mx = Math.max(...ys); if (mx - mn < 1) { mx += 1; mn -= 1; }
  const span = mx - mn; mn -= span * 0.12; mx += span * 0.12;
  const X = (i: number) => pad.l + (i / (data.length - 1)) * (W - pad.l - pad.r);
  const Y = (v: number) => pad.t + (1 - (v - mn) / (mx - mn)) * (H - pad.t - pad.b);
  const path = data.map((d, i) => `${i ? 'L' : 'M'}${X(i).toFixed(1)},${Y(d.y).toFixed(1)}`).join('');
  const area = path + `L${X(data.length - 1)},${H - pad.b}L${X(0)},${H - pad.b}Z`;
  const ticks = [mn + (mx - mn) * 0.15, (mn + mx) / 2, mx - (mx - mn) * 0.15];
  const id = 'g' + Math.random().toString(36).slice(2, 7);
  return (
    <svg className="chart" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" style={{ height }}>
      <defs><linearGradient id={id} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor={color} stopOpacity=".35" /><stop offset="1" stopColor={color} stopOpacity="0" /></linearGradient></defs>
      {ticks.map((t, i) => <g key={i}><line x1={pad.l} x2={W - pad.r} y1={Y(t)} y2={Y(t)} stroke="var(--line)" strokeDasharray="3 4" /><text x={pad.l - 6} y={Y(t) + 3} textAnchor="end" className="ax">{t.toFixed(t > 100 ? 0 : 1)}</text></g>)}
      {goal !== undefined && <g><line x1={pad.l} x2={W - pad.r} y1={Y(goal)} y2={Y(goal)} stroke="var(--coral)" strokeDasharray="5 4" /><text x={W - pad.r} y={Y(goal) - 4} textAnchor="end" className="ax" fill="var(--coral)">goal {goal}{unit}</text></g>}
      <path d={area} fill={`url(#${id})`} />
      <path d={path} fill="none" stroke={color} strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
      {data.map((d, i) => <circle key={i} cx={X(i)} cy={Y(d.y)} r={data.length > 20 ? 0 : 3} fill={color} />)}
      <text x={X(0)} y={H - 6} className="ax">{data[0].x}</text>
      <text x={X(data.length - 1)} y={H - 6} textAnchor="end" className="ax">{data[data.length - 1].x}</text>
    </svg>
  );
}
export function Bars({ data, height = 120, goal, color = 'var(--lime)', fmt = (v: number) => String(Math.round(v)) }: { data: { x: string; y: number }[]; height?: number; goal?: number; color?: string; fmt?: (v: number) => string }) {
  const mx = Math.max(goal || 0, ...data.map((d) => d.y), 1);
  return (
    <div className="bars" style={{ height }}>
      {goal !== undefined && <div className="bars-goal" style={{ bottom: `${(goal / mx) * 100 * 0.82 + 14}%` }} />}
      {data.map((d, i) => (
        <div key={i} className="bars-c">
          <small>{d.y ? fmt(d.y) : ''}</small>
          <i style={{ height: `${(d.y / mx) * 82}%`, background: goal && d.y >= goal ? color : 'var(--muted-bar)' }} />
          <span>{d.x}</span>
        </div>
      ))}
    </div>
  );
}

// ─── Media ───
export function useMediaUrl(id?: string) {
  const [u, setU] = useState<string | null>(null);
  useEffect(() => {
    let url: string | null = null; let live = true;
    if (id) getMedia(id).then((b) => { if (b && live) { url = URL.createObjectURL(b); setU(url); } });
    return () => { live = false; if (url) URL.revokeObjectURL(url); };
  }, [id]);
  return u;
}
export function Media({ m, className }: { m: { id?: string; art?: string; type: 'image' | 'video' }; className?: string }) {
  const u = useMediaUrl(m.id); const src = m.art || u;
  if (!src) return <div className={'media-ph ' + (className || '')} />;
  return m.type === 'video' ? <video className={className} src={src} controls playsInline preload="metadata" /> : <img className={className} src={src} alt="" loading="lazy" />;
}
export function Avatar({ name, color = '#C6FF3D', media, src, size = 40 }: { name: string; color?: string; media?: string; src?: string; size?: number }) {
  const u = useMediaUrl(media) || src;
  const initials = name.replace(/\(.*?\)/g, '').trim().split(/\s+/).map((x) => x[0] || '').join('').slice(0, 2).toUpperCase();
  return <div className="avatar" style={{ width: size, height: size, background: u ? `center/cover url(${u})` : color, fontSize: size * 0.38 }}>{!u && initials}</div>;
}

export function Toasts() {
  const list = useSyncExternalStore(toastStore.sub, toastStore.get);
  return <div className="toasts">{list.map((t) => <div key={t.id} className="toast">{t.text}</div>)}</div>;
}

export function useTicker(ms = 1000) {
  const [, s] = useState(0);
  useEffect(() => { const i = setInterval(() => s((x) => x + 1), ms); return () => clearInterval(i); }, [ms]);
}
export function NumIn({ value, onChange, step = 1, min = 0, suffix, w = 76 }: { value: number; onChange: (v: number) => void; step?: number; min?: number; suffix?: string; w?: number }) {
  const ref = useRef<HTMLInputElement>(null);
  return (
    <div className="numin">
      <button onClick={() => onChange(Math.max(min, +(value - step).toFixed(2)))}>−</button>
      <input ref={ref} inputMode="decimal" style={{ width: w }} value={Number.isFinite(value) ? value : ''} onChange={(e) => { const v = parseFloat(e.target.value); onChange(Number.isFinite(v) ? v : 0); }} />
      {suffix && <em>{suffix}</em>}
      <button onClick={() => onChange(+(value + step).toFixed(2))}>+</button>
    </div>
  );
}
export const fmt = {
  n: (v: number, d = 0) => v.toLocaleString('en-IN', { maximumFractionDigits: d, minimumFractionDigits: d }),
  ago: (ts: number) => { const s = (Date.now() - ts) / 1000; if (s < 60) return 'now'; if (s < 3600) return `${Math.floor(s / 60)}m`; if (s < 86400) return `${Math.floor(s / 3600)}h`; if (s < 604800) return `${Math.floor(s / 86400)}d`; return new Date(ts).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' }); },
  date: (d: string) => new Date(d + 'T00:00').toLocaleDateString('en-IN', { day: 'numeric', month: 'short' }),
  dur: (ms: number) => { const s = Math.floor(ms / 1000); const h = Math.floor(s / 3600); const m = Math.floor((s % 3600) / 60); const ss = s % 60; return (h ? h + ':' : '') + String(m).padStart(h ? 2 : 1, '0') + ':' + String(ss).padStart(2, '0'); },
};
