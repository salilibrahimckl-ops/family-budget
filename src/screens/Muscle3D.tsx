// Interactive, anatomically accurate 3D muscle model for each exercise (falls back to the 2D chart).
import React, { useEffect, useRef, useState } from 'react';
import { Chip } from '../ui';
import { MuscleMap, targets } from './MuscleMap';
import { loadThree, loadModel, createViewer, Viewer, CREDIT } from '../lib/body3d';

const pretty = (n: string) => n.replace(/^Set of /, '').replace(/ muscle$/, '');

export function Muscle3D({ primary, secondary }: { primary: string; secondary: string[] }) {
  const host = useRef<HTMLDivElement>(null);
  const vw = useRef<Viewer | null>(null);
  const [st, setSt] = useState<'loading' | 'ready' | 'error' | '2d'>(() => (hasWebGL() ? 'loading' : '2d'));
  const [pct, setPct] = useState(0);
  const [err, setErr] = useState('');
  const [pick, setPick] = useState<string | null>(null);
  const [bones, setBones] = useState(true);
  const [iso, setIso] = useState(false);
  const [side, setSide] = useState<'focus' | 'front' | 'back' | 'left' | 'right'>('focus');
  const [retry, setRetry] = useState(0);

  useEffect(() => {
    if (st === '2d') return;
    let dead = false;
    setSt('loading'); setErr('');
    (async () => {
      try {
        const [T, parts] = await Promise.all([loadThree(), loadModel((f) => !dead && setPct(f))]);
        if (dead || !host.current) return;
        const { pri, sec } = targets(primary, secondary);
        vw.current = createViewer(host.current, T, parts, { pri, sec, onPick: (n) => setPick(n) });
        setSt('ready');
      } catch (e) { if (!dead) { setErr((e as Error).message || 'Could not load the 3D model'); setSt('error'); } }
    })();
    return () => { dead = true; vw.current?.dispose(); vw.current = null; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [primary, secondary.join('|'), retry, st === '2d']);

  if (st === '2d') return (
    <div>
      <MuscleMap primary={primary} secondary={secondary} />
      {hasWebGL() && <div className="m3d-bar center"><Chip onClick={() => setSt('loading')}>Show realistic 3D model</Chip></div>}
    </div>
  );
  const sideBtn = (v: typeof side, l: string) => <Chip on={side === v} onClick={() => { setSide(v); vw.current?.view(v); }}>{l}</Chip>;
  return (
    <div className="m3d">
      <div className="m3d-stage">
        <div ref={host} className="m3d-canvas" />
        {st === 'loading' && <div className="m3d-over">
          <div className="m3d-ring" style={{ ['--p' as string]: Math.round(pct * 100) }} />
          <b>Loading 3D muscle model{pct > 0 && pct < 1 ? ` · ${Math.round(pct * 100)}%` : '…'}</b>
          <small>About 3.5 MB, downloaded once — then it works offline.</small>
        </div>}
        {st === 'error' && <div className="m3d-over">
          <b>3D model unavailable</b><small>{err}</small>
          <div className="m3d-bar center"><Chip onClick={() => setRetry((r) => r + 1)}>Try again</Chip><Chip onClick={() => setSt('2d')}>Use 2D chart</Chip></div>
        </div>}
        {st === 'ready' && pick && <div className="m3d-pick" onClick={() => setPick(null)}>{pretty(pick)}</div>}
        {st === 'ready' && <div className="m3d-hint">Drag to turn · pinch to zoom · tap a muscle</div>}
      </div>
      {st === 'ready' && <>
        <div className="m3d-bar">{sideBtn('focus', 'Focus')}{sideBtn('front', 'Front')}{sideBtn('back', 'Back')}{sideBtn('left', 'Left')}{sideBtn('right', 'Right')}</div>
        <div className="m3d-bar">
          <Chip on={iso} onClick={() => { setIso(!iso); vw.current?.setIsolate(!iso); }}>Only worked muscles</Chip>
          <Chip on={bones} onClick={() => { setBones(!bones); vw.current?.setBones(!bones); }}>Skeleton</Chip>
          <Chip onClick={() => setSt('2d')}>2D chart</Chip>
        </div>
      </>}
      <div className="mm-legend"><span><i style={{ background: '#D8261B' }} />Main muscle</span><span><i style={{ background: '#F2862E' }} />Also working</span><span><i style={{ background: '#9A5A52' }} />Resting</span></div>
      <small className="m3d-credit">{CREDIT}</small>
    </div>
  );
}

let gl: boolean | null = null;
function hasWebGL() {
  if (gl !== null) return gl;
  try { const c = document.createElement('canvas'); gl = !!(c.getContext('webgl2') || c.getContext('webgl')); } catch { gl = false; }
  return gl;
}
