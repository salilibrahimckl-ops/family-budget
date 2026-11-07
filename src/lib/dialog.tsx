// In-app confirm/prompt dialogs (native confirm/prompt are blocked in sandboxed web views).
import React, { useState, useSyncExternalStore } from 'react';
type D = { msg: string; text?: string; input: boolean; resolve: (v: any) => void } | null;
let cur: D = null; const subs = new Set<() => void>();
const set = (d: D) => { cur = d; subs.forEach((f) => f()); };
export const ask = (msg: string) => new Promise<boolean>((resolve) => set({ msg, input: false, resolve }));
export const askText = (msg: string, text = '') => new Promise<string | null>((resolve) => set({ msg, text, input: true, resolve }));
export function Dialogs() {
  const d = useSyncExternalStore((f) => { subs.add(f); return () => subs.delete(f); }, () => cur);
  const [v, setV] = useState('');
  React.useEffect(() => { setV(d?.text || ''); }, [d]);
  if (!d) return null;
  const close = (val: any) => { d.resolve(val); set(null); };
  return (
    <div className="sheet-bg dlg-bg" onClick={() => close(d.input ? null : false)}>
      <div className="dlg" onClick={(e) => e.stopPropagation()}>
        <p>{d.msg}</p>
        {d.input && <input autoFocus value={v} onChange={(e) => setV(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && close(v.trim() || null)} />}
        <div className="dlg-a"><button className="btn ghost small" onClick={() => close(d.input ? null : false)}>Cancel</button><button className="btn primary small" onClick={() => close(d.input ? (v.trim() || null) : true)}>OK</button></div>
      </div>
    </div>
  );
}
