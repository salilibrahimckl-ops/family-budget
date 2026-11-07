// Anatomical front/back muscle chart (stylised, drawn by hand from standard anatomy references).
// Left half is drawn once and mirrored, so both sides match.
import React from 'react';

type R = 'chest' | 'delts' | 'biceps' | 'forearms' | 'abs' | 'obliques' | 'serratus' | 'quads' | 'adductors' | 'calves' | 'tibialis' | 'traps' | 'lats' | 'rhomboids' | 'triceps' | 'glutes' | 'hamstrings' | 'lowback' | 'neck';

const PRIMARY: Record<string, R[]> = {
  chest: ['chest'], back: ['lats', 'traps', 'rhomboids'], shoulders: ['delts'], biceps: ['biceps'], triceps: ['triceps'], forearms: ['forearms'],
  abs: ['abs'], obliques: ['obliques'], quads: ['quads'], hamstrings: ['hamstrings'], glutes: ['glutes'], calves: ['calves'],
  fullbody: ['quads', 'glutes', 'chest', 'lats', 'delts', 'abs', 'hamstrings'],
};
const KW: [RegExp, R][] = [[/chest|pec/i, 'chest'], [/delt|shoulder|rotator/i, 'delts'], [/bicep|brachi/i, 'biceps'], [/forearm|grip|wrist/i, 'forearms'],
  [/core|abs|transvers/i, 'abs'], [/oblique/i, 'obliques'], [/serratus/i, 'serratus'], [/quad|legs/i, 'quads'], [/adductor/i, 'adductors'], [/calf|calves|soleus/i, 'calves'],
  [/trap/i, 'traps'], [/\blats?\b|latissimus|upper back/i, 'lats'], [/rhomboid|mid trap|lower trap/i, 'rhomboids'], [/tricep/i, 'triceps'], [/glute/i, 'glutes'], [/hamstring/i, 'hamstrings'],
  [/erector|lower back|spinal/i, 'lowback'], [/hip flexor/i, 'quads']];

// [region, path] — left half of the body (viewer's left), 200×460 canvas, centre x = 100
const FRONT: [R | 'skin', string][] = [
  ['neck', 'M93 60 Q88 70 86 82 L96 86 Q98 72 100 62 Z'],
  ['traps', 'M86 66 Q72 74 58 80 Q70 84 84 84 Z'],
  ['delts', 'M58 80 Q44 82 39 98 Q36 116 42 134 Q48 122 56 114 Q64 102 70 88 Q66 82 58 80 Z'],
  ['chest', 'M99 88 L74 86 Q64 90 60 104 Q58 120 66 130 Q80 138 99 132 Z'],
  ['serratus', 'M62 132 Q60 140 63 148 L70 146 L68 136 Z M63 150 Q62 158 65 165 L72 162 L70 151 Z'],
  ['biceps', 'M43 136 Q36 152 37 170 Q39 186 46 192 Q54 182 56 164 Q57 146 53 134 Q48 132 43 136 Z'],
  ['forearms', 'M38 194 Q29 212 29 234 Q31 252 35 264 L45 264 Q52 244 53 222 Q53 204 49 194 Q44 190 38 194 Z'],
  ['skin', 'M34 266 Q30 280 34 292 Q40 298 46 290 Q48 278 46 266 Z'],
  ['abs', 'M87 138 L98 137 L98 155 L86 156 Z M86 159 L98 158 L98 177 L86 178 Z M86 181 L98 180 L98 199 L87 200 Z M87 203 L98 202 L98 234 Q92 232 89 222 Z'],
  ['obliques', 'M68 138 L84 140 L84 222 Q74 214 68 196 Q64 172 68 154 Z'],
  ['adductors', 'M89 244 Q98 252 98 270 Q97 288 92 298 Q86 278 84 256 Z'],
  ['quads', 'M64 238 Q53 268 54 306 Q57 338 69 352 L76 330 Q71 292 73 254 Z M76 244 Q70 292 77 340 L88 344 Q93 300 90 256 Q84 246 76 244 Z M87 318 Q80 334 84 352 Q95 356 96 338 Q95 324 87 318 Z'],
  ['skin', 'M68 354 Q66 364 70 372 L92 372 Q96 362 94 354 Z'],
  ['tibialis', 'M67 376 Q61 402 64 432 L71 434 Q74 404 74 378 Z'],
  ['calves', 'M77 376 Q90 394 86 426 L80 428 Q76 402 76 378 Z'],
  ['skin', 'M62 436 Q56 446 60 454 L86 454 Q88 444 82 436 Z'],
];
const BACK: [R | 'skin', string][] = [
  ['traps', 'M100 60 L88 64 Q72 72 58 80 Q74 88 86 112 L100 152 Z'],
  ['delts', 'M58 80 Q43 84 39 100 Q38 118 43 134 Q52 118 62 108 Q68 94 58 80 Z'],
  ['rhomboids', 'M66 100 Q62 112 68 124 Q80 124 90 118 Q84 106 74 96 Z'],
  ['lats', 'M68 128 Q60 152 65 178 Q74 202 92 216 L98 208 L97 162 Q89 142 84 128 Q76 126 68 128 Z'],
  ['lowback', 'M91 172 Q86 196 91 222 L99 230 L99 166 Z'],
  ['triceps', 'M43 136 Q35 152 37 172 Q41 188 48 193 Q56 178 56 158 Q55 142 51 134 Q47 132 43 136 Z'],
  ['forearms', 'M38 195 Q29 213 29 235 Q31 252 35 264 L45 264 Q52 244 53 222 Q53 204 49 195 Q44 191 38 195 Z'],
  ['skin', 'M34 266 Q30 280 34 292 Q40 298 46 290 Q48 278 46 266 Z'],
  ['glutes', 'M66 230 Q57 250 62 270 Q76 288 99 284 L99 234 Q84 224 66 230 Z'],
  ['hamstrings', 'M61 286 Q55 320 63 352 L77 356 Q80 320 77 290 Z M80 290 Q84 322 82 354 L94 354 Q98 320 96 288 Z'],
  ['skin', 'M66 358 Q64 366 68 372 L92 372 Q96 364 94 358 Z'],
  ['calves', 'M64 374 Q55 394 61 420 Q70 428 78 418 Q80 396 76 374 Z M79 374 Q93 390 88 418 Q84 428 79 418 Z'],
  ['skin', 'M66 424 Q64 436 64 440 L84 440 Q84 432 82 424 Z M62 440 Q56 448 60 454 L86 454 Q88 446 84 440 Z'],
];
const SILHOUETTE = 'M100 62 L90 64 Q66 70 50 80 Q36 92 36 120 Q34 150 34 192 Q26 222 28 262 L33 292 L47 292 L54 262 Q57 226 60 198 L62 150 Q62 196 63 230 Q53 262 54 310 Q57 346 63 372 Q57 404 60 440 L58 456 L88 456 L85 440 Q90 404 88 372 Q93 344 95 300 L99 262 L100 262 Z';

export function MuscleMap({ primary, secondary }: { primary: string; secondary: string[] }) {
  const pri = new Set(PRIMARY[primary] || []);
  const sec = new Set<R>(); secondary.forEach((s) => KW.forEach(([re, r]) => { if (re.test(s) && !pri.has(r)) sec.add(r); }));
  const fill = (r: R | 'skin') => (r === 'skin' ? 'url(#mm-skin)' : pri.has(r as R) ? 'url(#mm-pri)' : sec.has(r as R) ? 'url(#mm-sec)' : 'url(#mm-off)');
  const Half = ({ parts }: { parts: [R | 'skin', string][] }) => <>{parts.map(([r, d], i) => <path key={i} d={d} fill={fill(r)} stroke="var(--mm-line)" strokeWidth="1.1" strokeLinejoin="round" />)}</>;
  const Figure = ({ parts, x, back, label }: { parts: [R | 'skin', string][]; x: number; back?: boolean; label: string }) => (
    <g transform={`translate(${x} 0)`}>
      <path d={SILHOUETTE} fill="url(#mm-skin)" /><path d={SILHOUETTE} fill="url(#mm-skin)" transform="translate(200 0) scale(-1 1)" />
      <ellipse cx="100" cy="34" rx="20" ry="25" fill="url(#mm-skin)" />
      {back && <path d="M86 40 Q100 66 114 40 Q112 58 100 60 Q88 58 86 40Z" fill="var(--mm-hair)" opacity=".5" />}
      <Half parts={parts} />
      <g transform="translate(200 0) scale(-1 1)"><Half parts={parts} /></g>
      {!back && <path d="M100 136 L100 236" stroke="var(--mm-line)" strokeWidth="1.4" />}
      {/* fibre hints */}
      <g stroke="#000" strokeOpacity=".12" strokeWidth=".8" fill="none">
        {!back ? <><path d="M70 98 Q84 108 98 104 M66 112 Q82 122 98 118 M64 124 Q80 132 98 128" /><path d="M130 98 Q116 108 102 104 M134 112 Q118 122 102 118 M136 124 Q120 132 102 128" />
          <path d="M60 260 Q62 300 70 340 M140 260 Q138 300 130 340" /></>
          : <><path d="M80 140 Q84 170 94 200 M120 140 Q116 170 106 200" /><path d="M70 240 Q84 262 98 266 M130 240 Q116 262 102 266" /></>}
      </g>
      <text x="100" y="474" textAnchor="middle" className="mm-lbl">{label}</text>
    </g>
  );
  return (
    <div className="mmap">
      <svg viewBox="0 0 410 484" width="100%" style={{ maxWidth: 360 }} role="img" aria-label="Muscles worked">
        <defs>
          <linearGradient id="mm-pri" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#E4FF6A" /><stop offset="1" stopColor="#8FD400" /></linearGradient>
          <linearGradient id="mm-sec" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#FFB070" /><stop offset="1" stopColor="#E0661F" /></linearGradient>
          <linearGradient id="mm-off" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="var(--mm-off-a)" /><stop offset="1" stopColor="var(--mm-off-b)" /></linearGradient>
          <linearGradient id="mm-skin" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="var(--mm-skin-a)" /><stop offset="1" stopColor="var(--mm-skin-b)" /></linearGradient>
        </defs>
        <Figure parts={FRONT} x={0} label="Front" />
        <Figure parts={BACK} x={210} back label="Back" />
      </svg>
      <div className="mm-legend"><span><i style={{ background: '#C6FF3D' }} />Main muscle</span><span><i style={{ background: '#F08A3E' }} />Also working</span></div>
    </div>
  );
}
