// Schematic (non-anatomical) front/back muscle map used to show primary vs secondary muscles.
import React from 'react';

type R = 'chest' | 'delts' | 'biceps' | 'forearms' | 'abs' | 'obliques' | 'quads' | 'calves' | 'traps' | 'lats' | 'triceps' | 'glutes' | 'hamstrings' | 'lowback';
const PRIMARY: Record<string, R[]> = {
  chest: ['chest'], back: ['lats', 'traps'], shoulders: ['delts'], biceps: ['biceps'], triceps: ['triceps'], forearms: ['forearms'], abs: ['abs'], obliques: ['obliques'],
  quads: ['quads'], hamstrings: ['hamstrings'], glutes: ['glutes'], calves: ['calves'], fullbody: ['quads', 'glutes', 'chest', 'lats', 'delts', 'abs'],
};
const KW: [RegExp, R][] = [[/chest|pec/i, 'chest'], [/delt|shoulder|rotator/i, 'delts'], [/bicep|brachi/i, 'biceps'], [/forearm|grip|wrist/i, 'forearms'], [/core|abs|transvers/i, 'abs'], [/oblique/i, 'obliques'], [/quad|legs/i, 'quads'], [/calf|calves|soleus/i, 'calves'], [/trap/i, 'traps'], [/lat|back|rhomboid/i, 'lats'], [/tricep/i, 'triceps'], [/glute/i, 'glutes'], [/hamstring/i, 'hamstrings'], [/erector|lower back/i, 'lowback'], [/adductor|hip flexor/i, 'quads']];

export function MuscleMap({ primary, secondary }: { primary: string; secondary: string[] }) {
  const pri = new Set(PRIMARY[primary] || []);
  const sec = new Set<R>(); secondary.forEach((s) => KW.forEach(([re, r]) => { if (re.test(s) && !pri.has(r)) sec.add(r); }));
  const fill = (r: R) => (pri.has(r) ? 'var(--lime)' : sec.has(r) ? 'var(--lime-dim)' : 'var(--body)');
  const Body = ({ x, back }: { x: number; back?: boolean }) => (
    <g transform={`translate(${x} 0)`}>
      <circle cx="60" cy="18" r="13" fill="var(--body-2)" />
      <rect x="53" y="30" width="14" height="8" fill="var(--body-2)" />
      {/* torso */}
      {!back ? <>
        <path d="M30 42 Q60 34 90 42 L88 66 Q60 74 32 66Z" fill={fill('chest')} />
        <rect x="46" y="70" width="28" height="42" rx="8" fill={fill('abs')} />
        <path d="M33 70 L45 72 L45 112 L37 110 Q31 92 33 70Z" fill={fill('obliques')} /><path d="M87 70 L75 72 L75 112 L83 110 Q89 92 87 70Z" fill={fill('obliques')} />
      </> : <>
        <path d="M38 38 Q60 30 82 38 L76 54 Q60 58 44 54Z" fill={fill('traps')} />
        <path d="M33 56 Q60 62 87 56 L80 96 Q60 104 40 96Z" fill={fill('lats')} />
        <rect x="46" y="98" width="28" height="16" rx="6" fill={fill('lowback')} />
        <path d="M36 114 Q60 108 84 114 L84 134 Q60 142 36 134Z" fill={fill('glutes')} />
      </>}
      {/* shoulders */}
      <ellipse cx="25" cy="48" rx="11" ry="12" fill={fill('delts')} /><ellipse cx="95" cy="48" rx="11" ry="12" fill={fill('delts')} />
      {/* upper arms */}
      <rect x="13" y="58" width="14" height="34" rx="7" fill={fill(back ? 'triceps' : 'biceps')} /><rect x="93" y="58" width="14" height="34" rx="7" fill={fill(back ? 'triceps' : 'biceps')} />
      {/* forearms */}
      <rect x="9" y="94" width="13" height="34" rx="6" fill={fill('forearms')} /><rect x="98" y="94" width="13" height="34" rx="6" fill={fill('forearms')} />
      {/* hips */}
      {!back && <path d="M36 114 Q60 108 84 114 L82 128 Q60 134 38 128Z" fill="var(--body-2)" />}
      {/* thighs */}
      <rect x="36" y={back ? 136 : 128} width="20" height={back ? 48 : 56} rx="9" fill={fill(back ? 'hamstrings' : 'quads')} /><rect x="64" y={back ? 136 : 128} width="20" height={back ? 48 : 56} rx="9" fill={fill(back ? 'hamstrings' : 'quads')} />
      {/* calves */}
      <rect x="38" y="190" width="16" height="40" rx="8" fill={fill('calves')} /><rect x="66" y="190" width="16" height="40" rx="8" fill={fill('calves')} />
      <text x="60" y="248" textAnchor="middle" className="mm-lbl">{back ? 'Back' : 'Front'}</text>
    </g>
  );
  return (
    <div className="mmap">
      <svg viewBox="0 0 270 254" width="100%" style={{ maxWidth: 300 }}>
        <Body x={5} /><Body x={145} back />
      </svg>
      <div className="mm-legend"><span><i style={{ background: 'var(--lime)' }} />Primary</span><span><i style={{ background: 'var(--lime-dim)' }} />Secondary</span><small>Schematic diagram</small></div>
    </div>
  );
}
