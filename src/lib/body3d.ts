// Realistic 3D muscle atlas. Anatomy data: BodyParts3D © The Database Center for Life Science (DBCLS), CC BY 4.0,
// prepared (decimated, latissimus + rectus abdominis rebuilt) by scripts/build-body3d.py. Rendering: three.js r128.
/* eslint-disable @typescript-eslint/no-explicit-any */
declare global { interface Window { THREE?: any } }

const ASSET = 'body3d.bin';
const ASSET_URLS = [
  './' + ASSET + '.gz',
  'https://raw.githubusercontent.com/salilibrahimckl-ops/family-budget/fitverse-assets/' + ASSET + '.gz',
  'https://cdn.jsdelivr.net/gh/salilibrahimckl-ops/family-budget@fitverse-assets/' + ASSET + '.gz',
];
const THREE_URLS = ['./three.min.js', 'https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js', 'https://cdn.jsdelivr.net/npm/three@0.128.0/build/three.min.js'];
export const CREDIT = 'Anatomy: BodyParts3D © DBCLS, CC BY 4.0';

export type Part = { name: string; kind: 'muscle' | 'bone'; region: string; pos: Float32Array; nrm: Float32Array; idx: Uint16Array | Uint32Array };

// ---- tiny IndexedDB cache (so the model works offline after the first load) ----
function cacheDb(): Promise<IDBDatabase> {
  return new Promise((res, rej) => { try { const r = indexedDB.open('bros-3d', 1); r.onupgradeneeded = () => r.result.createObjectStore('f'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); } catch (e) { rej(e); } });
}
async function cacheGet(k: string): Promise<any> {
  try { const d = await cacheDb(); return await new Promise((res) => { const q = d.transaction('f').objectStore('f').get(k); q.onsuccess = () => res(q.result); q.onerror = () => res(undefined); }); } catch { return undefined; }
}
async function cacheSet(k: string, v: any) { try { const d = await cacheDb(); d.transaction('f', 'readwrite').objectStore('f').put(v, k); } catch { /* storage full or blocked */ } }

// ---- three.js loader ----
let threeP: Promise<any> | null = null;
function addScript(src: string) {
  return new Promise<void>((res, rej) => { const s = document.createElement('script'); s.src = src; s.async = true; s.onload = () => res(); s.onerror = () => { s.remove(); rej(new Error('script ' + src)); }; document.head.appendChild(s); });
}
export function loadThree(): Promise<any> {
  if (window.THREE) return Promise.resolve(window.THREE);
  if (threeP) return threeP;
  threeP = (async () => {
    const cached: string | undefined = await cacheGet('three-r128');
    if (cached) { try { new Function(cached)(); if (window.THREE) return window.THREE; } catch { /* eval blocked — fall through */ } }
    for (const u of THREE_URLS) {
      try {
        await addScript(u);
        if (window.THREE) {
          if (!cached && u.startsWith('http')) fetch(u).then((r) => (r.ok ? r.text() : '')).then((t) => { if (t.length > 100000) cacheSet('three-r128', t); }).catch(() => undefined);
          return window.THREE;
        }
      } catch { /* try next */ }
    }
    threeP = null;
    throw new Error('3D engine could not load (check your internet connection).');
  })();
  return threeP;
}

// ---- model loader ----
let modelP: Promise<Part[]> | null = null;
async function gunzip(buf: ArrayBuffer): Promise<ArrayBuffer> {
  const u = new Uint8Array(buf);
  if (u[0] !== 0x1f || u[1] !== 0x8b) return buf; // already decompressed by the server
  const DS = (window as any).DecompressionStream;
  if (!DS) throw new Error('This browser cannot unpack the 3D model. Please update it.');
  return new Response(new Blob([buf]).stream().pipeThrough(new DS('gzip'))).arrayBuffer();
}
async function fetchWithProgress(url: string, onProgress: (f: number) => void): Promise<ArrayBuffer> {
  const r = await fetch(url);
  if (!r.ok) throw new Error('HTTP ' + r.status);
  const total = +(r.headers.get('content-length') || 0) || 4.1e6;
  if (!r.body || !(r.body as any).getReader) return r.arrayBuffer();
  const rd = r.body.getReader(); const chunks: Uint8Array[] = []; let got = 0;
  for (;;) { const { done, value } = await rd.read(); if (done) break; chunks.push(value); got += value.length; onProgress(Math.min(0.99, got / total)); }
  const out = new Uint8Array(got); let o = 0; chunks.forEach((c) => { out.set(c, o); o += c.length; });
  return out.buffer;
}
function parse(buf: ArrayBuffer): Part[] {
  const dv = new DataView(buf);
  if (String.fromCharCode(dv.getUint8(0), dv.getUint8(1), dv.getUint8(2), dv.getUint8(3)) !== 'BF3D') throw new Error('Bad 3D model file');
  const hl = dv.getUint32(4, true);
  const hdr = JSON.parse(new TextDecoder().decode(new Uint8Array(buf, 8, hl)));
  const base = 8 + hl;
  return hdr.parts.map(([name, kind, region, off, v, ic, lo, hi]: any) => {
    const o = base + off;
    const q = new Uint16Array(buf, o, v * 3); const pos = new Float32Array(v * 3);
    for (let i = 0; i < v * 3; i++) { const k = i % 3; pos[i] = lo[k] + (q[i] / 65535) * (hi[k] - lo[k]); }
    const no = o + v * 6; const n8 = new Int8Array(buf, no, v * 3); const nrm = new Float32Array(v * 3);
    for (let i = 0; i < v * 3; i++) nrm[i] = n8[i] / 127;
    let io = no + v * 3; io = (io + 3) & ~3;
    const idx = v < 65536 ? new Uint16Array(buf, io, ic) : new Uint32Array(buf, io, ic);
    return { name, kind, region, pos, nrm, idx };
  });
}
export function loadModel(onProgress: (f: number) => void = () => undefined): Promise<Part[]> {
  if (modelP) return modelP;
  modelP = (async () => {
    const cached: ArrayBuffer | undefined = await cacheGet(ASSET);
    if (cached) { try { onProgress(1); return parse(cached); } catch { /* corrupt cache — refetch */ } }
    let lastErr: any;
    for (const u of ASSET_URLS) {
      try {
        const raw = await fetchWithProgress(u, onProgress);
        const buf = await gunzip(raw);
        const parts = parse(buf);
        cacheSet(ASSET, buf);
        onProgress(1);
        return parts;
      } catch (e) { lastErr = e; }
    }
    modelP = null;
    throw lastErr || new Error('3D model unavailable');
  })();
  return modelP;
}
export async function isCached() { return !!(await cacheGet(ASSET)); }

// ---- viewer ----
const FRONT_REGIONS = new Set(['chest', 'abs', 'obliques', 'quads', 'biceps', 'serratus', 'tibialis', 'hipflex', 'adductors', 'forearms', 'delts', 'neck']);
export type ViewerOpts = { pri: Set<string>; sec: Set<string>; onPick?: (name: string | null) => void };
export type Viewer = { view: (v: 'front' | 'back' | 'left' | 'right' | 'focus') => void; setBones: (b: boolean) => void; setIsolate: (b: boolean) => void; dispose: () => void };

const C = { pri: 0xd8261b, priE: 0x4a0600, sec: 0xf2862e, secE: 0x2a1000, off: 0x9a5a52, bone: 0xe9dfc8 };

export function createViewer(el: HTMLElement, T: any, parts: Part[], o: ViewerOpts): Viewer {
  const W = () => Math.max(10, el.clientWidth), H = () => Math.max(10, el.clientHeight);
  const renderer = new T.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setSize(W(), H());
  renderer.outputEncoding = T.sRGBEncoding;
  renderer.toneMapping = T.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.0;
  renderer.domElement.style.touchAction = 'none';
  el.appendChild(renderer.domElement);
  const scene = new T.Scene();
  const cam = new T.PerspectiveCamera(28, W() / H(), 0.01, 20);
  scene.add(new T.HemisphereLight(0xfff1e6, 0x2b2220, 0.8));
  const key = new T.DirectionalLight(0xffffff, 1.25); key.position.set(1.2, 2.2, 2.4); scene.add(key);
  const rim = new T.DirectionalLight(0xbcd4ff, 0.7); rim.position.set(-1.8, 1.4, -2.2); scene.add(rim);
  const fill = new T.DirectionalLight(0xffe0d0, 0.35); fill.position.set(-2, 0.4, 1.5); scene.add(fill);
  // Lights follow the camera so the side you look at is always lit.
  const lightRig = new T.Group(); [key, rim, fill].forEach((l) => { scene.remove(l); lightRig.add(l); }); scene.add(lightRig);

  const lin = (m: any) => { m.color.convertSRGBToLinear(); if (m.emissive) m.emissive.convertSRGBToLinear(); return m; };
  const mk = (color: number, emissive = 0, opts: any = {}) => lin(new T.MeshPhysicalMaterial({ color, emissive, roughness: 0.5, metalness: 0, clearcoat: 0.45, clearcoatRoughness: 0.35, side: T.DoubleSide, ...opts }));
  const mPri = mk(C.pri, C.priE), mSec = mk(C.sec, C.secE), mOff = mk(C.off, 0, { roughness: 0.62, clearcoat: 0.25 });
  const mGhost = mk(C.off, 0, { transparent: true, opacity: 0.14, depthWrite: false, clearcoat: 0 });
  const mBone = lin(new T.MeshStandardMaterial({ color: C.bone, roughness: 0.75, metalness: 0, side: T.DoubleSide }));

  const priE = mPri.emissive.clone();
  const root = new T.Group(); scene.add(root);
  const muscles: any[] = [];
  const box = new T.Box3(); const focusBox = new T.Box3(); let frontScore = 0;
  const boneGeo: Part[] = [];
  parts.forEach((p) => {
    if (p.kind === 'bone') { boneGeo.push(p); return; }
    const g = new T.BufferGeometry();
    g.setAttribute('position', new T.BufferAttribute(p.pos, 3)); g.setAttribute('normal', new T.BufferAttribute(p.nrm, 3)); g.setIndex(new T.BufferAttribute(p.idx, 1));
    g.computeBoundingBox(); g.computeBoundingSphere();
    const role = o.pri.has(p.region) ? 'pri' : o.sec.has(p.region) ? 'sec' : 'off';
    const m = new T.Mesh(g, role === 'pri' ? mPri : role === 'sec' ? mSec : mOff);
    m.userData = { name: p.name, role };
    if (role === 'pri') { focusBox.union(g.boundingBox); frontScore += FRONT_REGIONS.has(p.region) ? 1 : -1; }
    box.union(g.boundingBox); muscles.push(m); root.add(m);
  });
  // Bones merged into one mesh (fewer draw calls on phones)
  let vt = 0, it = 0; boneGeo.forEach((p) => { vt += p.pos.length / 3; it += p.idx.length; });
  const bp = new Float32Array(vt * 3), bn = new Float32Array(vt * 3), bi = new Uint32Array(it); let vo = 0, io2 = 0;
  const boneRanges: [number, string][] = [];
  boneGeo.forEach((p) => { boneRanges.push([io2 / 3, p.name]); bp.set(p.pos, vo * 3); bn.set(p.nrm, vo * 3); for (let i = 0; i < p.idx.length; i++) bi[io2 + i] = p.idx[i] + vo; vo += p.pos.length / 3; io2 += p.idx.length; });
  const bg = new T.BufferGeometry(); bg.setAttribute('position', new T.BufferAttribute(bp, 3)); bg.setAttribute('normal', new T.BufferAttribute(bn, 3)); bg.setIndex(new T.BufferAttribute(bi, 1));
  const bones = new T.Mesh(bg, mBone); bones.userData = { name: 'Skeleton', role: 'bone' }; root.add(bones);

  const center = new T.Vector3(); box.getCenter(center);
  const size = new T.Vector3(); box.getSize(size);
  // Orbit state
  let theta = 0, phi = 0.08, dist = 0, tTheta = 0, tPhi = 0.08, tDist = 0;
  const target = center.clone(), tTarget = center.clone();
  const fitDist = (h: number) => (h / 2) / Math.tan((cam.fov * Math.PI) / 360) * 1.12 / Math.min(1, W() / H() * 1.6);
  const full = { d: fitDist(size.y), t: center.clone() };
  const focus = (() => {
    if (focusBox.isEmpty()) return full;
    const c = new T.Vector3(); focusBox.getCenter(c); const s = new T.Vector3(); focusBox.getSize(s);
    const h = Math.max(s.y, s.x * 1.1, 0.35);
    return { d: Math.min(full.d, fitDist(h) * 1.7), t: c };
  })();
  const startBack = frontScore < 0;
  function view(v: 'front' | 'back' | 'left' | 'right' | 'focus') {
    idle = false;
    if (v === 'focus') { tTheta = startBack ? Math.PI : 0; tPhi = 0.08; tDist = focus.d; tTarget.copy(focus.t); return; }
    tTheta = v === 'front' ? 0 : v === 'back' ? Math.PI : v === 'left' ? -Math.PI / 2 : Math.PI / 2;
    tPhi = 0.05; tDist = full.d; tTarget.copy(full.t);
    // keep the angle change short (no spinning the long way round)
    while (tTheta - theta > Math.PI) tTheta -= 2 * Math.PI; while (theta - tTheta > Math.PI) tTheta += 2 * Math.PI;
  }
  // Start on the full body, then glide into the worked muscles
  theta = tTheta = startBack ? Math.PI : 0; dist = full.d; target.copy(full.t);
  let idle = true; const t0 = performance.now();
  setTimeout(() => { if (!disposed) { tDist = focus.d; tTarget.copy(focus.t); } }, 450);
  tDist = dist; tTarget.copy(target);

  // ---- input: drag = rotate, pinch/wheel = zoom, two-finger drag = pan, tap = name ----
  const ptrs = new Map<number, { x: number; y: number }>(); let moved = 0, pinch0 = 0, dist0 = 0, mid0 = { x: 0, y: 0 }, tgt0 = new T.Vector3(), downAt = 0, lastTap = 0;
  const cv = renderer.domElement as HTMLCanvasElement;
  const onDown = (e: PointerEvent) => {
    cv.setPointerCapture(e.pointerId); ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY }); idle = false; moved = 0; downAt = performance.now();
    if (ptrs.size === 2) { const [a, b] = [...ptrs.values()]; pinch0 = Math.hypot(a.x - b.x, a.y - b.y); dist0 = tDist; mid0 = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }; tgt0 = tTarget.clone(); }
  };
  const onMove = (e: PointerEvent) => {
    const p = ptrs.get(e.pointerId); if (!p) return;
    const dx = e.clientX - p.x, dy = e.clientY - p.y; moved += Math.abs(dx) + Math.abs(dy);
    p.x = e.clientX; p.y = e.clientY;
    if (ptrs.size === 1) { tTheta -= dx * 0.009; tPhi = Math.max(-1.2, Math.min(1.2, tPhi + dy * 0.006)); }
    else if (ptrs.size === 2) {
      const [a, b] = [...ptrs.values()]; const d = Math.hypot(a.x - b.x, a.y - b.y);
      if (pinch0 > 0) tDist = Math.max(0.25, Math.min(full.d * 1.6, dist0 * (pinch0 / d)));
      const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2; const k = tDist / H() * 0.9;
      tTarget.copy(tgt0); tTarget.y += (my - mid0.y) * k;
      const right = new T.Vector3(Math.cos(theta), 0, -Math.sin(theta)); tTarget.addScaledVector(right, -(mx - mid0.x) * k);
    }
  };
  const ray = new T.Raycaster(); const ndc = new T.Vector2();
  const onUp = (e: PointerEvent) => {
    const was = ptrs.size; ptrs.delete(e.pointerId); if (ptrs.size < 2) pinch0 = 0;
    if (was === 1 && moved < 8 && performance.now() - downAt < 400) {
      const now = performance.now();
      if (now - lastTap < 320) { view('focus'); lastTap = 0; return; }
      lastTap = now;
      const r = cv.getBoundingClientRect(); ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
      ray.setFromCamera(ndc, cam);
      const vis = muscles.filter((m) => m.visible && m.material !== mGhost).concat(bones.visible ? [bones] : []);
      const hit = ray.intersectObjects(vis, false)[0];
      let nm: string | null = hit ? hit.object.userData.name : null;
      if (hit && hit.object === bones && hit.faceIndex != null) { for (const [f, n] of boneRanges) { if (f <= hit.faceIndex) nm = n; else break; } }
      o.onPick?.(nm);
    }
  };
  const onWheel = (e: WheelEvent) => { e.preventDefault(); idle = false; tDist = Math.max(0.25, Math.min(full.d * 1.6, tDist * (1 + Math.sign(e.deltaY) * 0.12))); };
  cv.addEventListener('pointerdown', onDown); cv.addEventListener('pointermove', onMove); cv.addEventListener('pointerup', onUp); cv.addEventListener('pointercancel', onUp);
  cv.addEventListener('wheel', onWheel, { passive: false });

  // ---- render loop (pauses when off-screen) ----
  let disposed = false, visible = true, raf = 0;
  const io = 'IntersectionObserver' in window ? new IntersectionObserver((es) => { visible = es[0]?.isIntersecting ?? true; if (visible) loop(); }) : null; io?.observe(el);
  const ro = 'ResizeObserver' in window ? new ResizeObserver(() => { renderer.setSize(W(), H()); cam.aspect = W() / H(); cam.updateProjectionMatrix(); }) : null; ro?.observe(el);
  function loop() {
    if (disposed || !visible) { raf = 0; return; }
    if (raf) return;
    raf = requestAnimationFrame(() => { raf = 0; frame(); loop(); });
  }
  function frame() {
    const t = (performance.now() - t0) / 1000;
    const sway = idle ? Math.sin(t * 0.5) * 0.32 : 0;
    const a = 0.12;
    theta += (tTheta - theta) * a; phi += (tPhi - phi) * a; dist += (tDist - dist) * a; target.lerp(tTarget, a);
    const th = theta + sway;
    cam.position.set(target.x + dist * Math.sin(th) * Math.cos(phi), target.y + dist * Math.sin(phi), target.z + dist * Math.cos(th) * Math.cos(phi));
    cam.lookAt(target); lightRig.quaternion.copy(cam.quaternion);
    const pulse = 0.55 + 0.45 * Math.sin(t * 3);
    mPri.emissive.copy(priE).multiplyScalar(0.6 + pulse * 1.6);
    renderer.render(scene, cam);
  }
  loop();
  let isolate = false;
  return {
    view: (v) => { view(v); },
    setBones: (b) => { bones.visible = b; },
    setIsolate: (b) => { isolate = b; muscles.forEach((m) => { if (m.userData.role === 'off') m.material = isolate ? mGhost : mOff; m.renderOrder = m.userData.role === 'off' && isolate ? 2 : 0; }); },
    dispose: () => {
      disposed = true; if (raf) cancelAnimationFrame(raf); io?.disconnect(); ro?.disconnect();
      cv.removeEventListener('pointerdown', onDown); cv.removeEventListener('pointermove', onMove); cv.removeEventListener('pointerup', onUp); cv.removeEventListener('pointercancel', onUp); cv.removeEventListener('wheel', onWheel);
      muscles.forEach((m) => m.geometry.dispose()); bg.dispose(); [mPri, mSec, mOff, mGhost, mBone].forEach((m) => m.dispose());
      renderer.dispose(); cv.remove();
    },
  };
}
