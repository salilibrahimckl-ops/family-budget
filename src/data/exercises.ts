// Bro’s Fitness exercise library.
// Coaching cues follow widely taught strength-coaching standards (NSCA / ACE style technique cues).
// No demonstration videos are bundled. `video` stays empty until an admin attaches a licensed URL.

export type Equip = 'none' | 'bands' | 'dumbbells' | 'homegym' | 'gym';
export type Muscle =
  | 'chest' | 'back' | 'shoulders' | 'biceps' | 'triceps' | 'forearms' | 'abs'
  | 'obliques' | 'quads' | 'hamstrings' | 'glutes' | 'calves' | 'fullbody';

export interface Exercise {
  id: string;
  name: string;
  muscle: Muscle;
  secondary: string[];
  equip: Equip;
  gear: string;
  type: 'strength' | 'bodyweight' | 'cardio' | 'core' | 'plyometric';
  mech: 'compound' | 'isolation';
  level: 1 | 2 | 3;
  start: string;
  steps: string[];
  breath: string;
  posture: string;
  mistakes: string[];
  safety: string[];
  sets: string;
  reps: string;
  rest: string;
  tempo?: string;
  alts: Partial<Record<Equip, string>>;
  video?: string;
  premium?: boolean;
}

export const MUSCLES: { key: Muscle; name: string; emoji: string }[] = [
  { key: 'chest', name: 'Chest', emoji: '🫁' },
  { key: 'back', name: 'Back', emoji: '🔙' },
  { key: 'shoulders', name: 'Shoulders', emoji: '🏔️' },
  { key: 'biceps', name: 'Biceps', emoji: '💪' },
  { key: 'triceps', name: 'Triceps', emoji: '🦾' },
  { key: 'forearms', name: 'Forearms', emoji: '✊' },
  { key: 'abs', name: 'Abdominals', emoji: '🧱' },
  { key: 'obliques', name: 'Obliques', emoji: '🌀' },
  { key: 'quads', name: 'Quadriceps', emoji: '🦵' },
  { key: 'hamstrings', name: 'Hamstrings', emoji: '🦿' },
  { key: 'glutes', name: 'Glutes', emoji: '🍑' },
  { key: 'calves', name: 'Calves', emoji: '🦶' },
  { key: 'fullbody', name: 'Full body', emoji: '⚡' },
];

export const EQUIP: { key: Equip; name: string; desc: string }[] = [
  { key: 'none', name: 'No equipment', desc: 'Bodyweight only — floor, wall, a sturdy chair' },
  { key: 'bands', name: 'Resistance bands', desc: 'Loop and tube bands with a door anchor' },
  { key: 'dumbbells', name: 'Dumbbells', desc: 'A pair of dumbbells (adjustable is ideal)' },
  { key: 'homegym', name: 'Home gym', desc: 'Dumbbells, bench, pull-up bar, barbell and rack' },
  { key: 'gym', name: 'Fully equipped gym', desc: 'Machines, cables, barbells and free weights' },
];
export const EQUIP_RANK: Record<Equip, number> = { none: 0, bands: 1, dumbbells: 2, homegym: 3, gym: 4 };

const C = { ribs: 'Ribs down, braced core, neutral neck.' };

export const EXERCISES: Exercise[] = [
  // ───────────── CHEST ─────────────
  {
    id: 'bench-press', name: 'Barbell Bench Press', muscle: 'chest', secondary: ['Front delts', 'Triceps'],
    equip: 'homegym', gear: 'Barbell, flat bench, rack', type: 'strength', mech: 'compound', level: 2,
    start: 'Lie on the bench with eyes under the bar. Feet flat, shoulder blades squeezed together and down, slight natural arch. Grip slightly wider than shoulder width, wrists stacked over elbows.',
    steps: ['Unrack the bar and hold it over your shoulders with straight arms.', 'Lower the bar under control to the lower chest / nipple line, elbows about 45–70° from the torso.', 'Touch the chest lightly without bouncing.', 'Press up and slightly back toward the rack position until the elbows are straight.'],
    breath: 'Big breath in and brace before lowering; hold through the bottom; exhale as you pass the hardest part of the press.',
    posture: 'Shoulder blades stay pinned, glutes stay on the bench, feet drive into the floor. Forearms vertical at the bottom.',
    mistakes: ['Flaring elbows to 90°, which stresses the shoulders', 'Bouncing the bar off the chest', 'Lifting the hips off the bench', 'Bent-back wrists'],
    safety: ['Use a spotter or safety pins for heavy sets', 'Never bench with a thumbless grip', 'Stop if you feel sharp shoulder pain'],
    sets: '3–5', reps: '5–10', rest: '2–3 min', tempo: '2-1-1', alts: { none: 'push-up', bands: 'band-chest-press', dumbbells: 'db-floor-press' },
  },
  {
    id: 'incline-db-press', name: 'Incline Dumbbell Press', muscle: 'chest', secondary: ['Upper chest (clavicular head)', 'Front delts', 'Triceps'],
    equip: 'homegym', gear: 'Dumbbells, adjustable bench (30–45°)', type: 'strength', mech: 'compound', level: 2,
    start: 'Set the bench to 30–45°. Sit back with dumbbells on your thighs, kick them up one at a time and lie back with the weights at upper-chest level, palms forward or slightly turned in.',
    steps: ['Press the dumbbells up and slightly together over the upper chest.', 'Lower slowly until the elbows are just below the bench line and you feel a stretch across the upper chest.', 'Press back up without clanging the dumbbells together.'],
    breath: 'Inhale on the way down, exhale as you press.',
    posture: 'Shoulder blades retracted, chest proud, lower back in a natural arch, feet planted.',
    mistakes: ['Bench set too steep (turns it into a shoulder press)', 'Dropping the weights too deep and losing shoulder position', 'Short, partial reps'],
    safety: ['Lower the dumbbells to your thighs before sitting up at the end', 'Choose a weight you can control for every rep'],
    sets: '3–4', reps: '8–12', rest: '90 s', alts: { none: 'decline-push-up', bands: 'band-chest-press', dumbbells: 'db-floor-press' },
  },
  {
    id: 'cable-fly', name: 'Cable Chest Fly', muscle: 'chest', secondary: ['Front delts'],
    equip: 'gym', gear: 'Cable crossover station', type: 'strength', mech: 'isolation', level: 1,
    start: 'Set both pulleys at shoulder height. Take a handle in each hand, step forward into a split stance, arms out wide with a soft bend in the elbows.',
    steps: ['Keeping the elbow bend fixed, bring the hands together in a wide arc in front of the chest.', 'Squeeze the chest for a moment.', 'Return slowly until you feel a stretch, without letting the arms travel behind the body.'],
    breath: 'Exhale as the hands come together; inhale as they open.',
    posture: 'Slight forward lean, chest up, shoulders down away from the ears.',
    mistakes: ['Turning it into a press by bending the elbows more', 'Using too much weight and shrugging', 'Over-stretching the shoulder at the back'],
    safety: ['Stop the stretch at a comfortable range — this is not a flexibility test'],
    sets: '3', reps: '12–15', rest: '60 s', alts: { none: 'push-up', bands: 'band-chest-fly', dumbbells: 'db-floor-press' },
  },
  {
    id: 'pec-deck', name: 'Pec Deck Machine', muscle: 'chest', secondary: ['Front delts'],
    equip: 'gym', gear: 'Pec deck / fly machine', type: 'strength', mech: 'isolation', level: 1,
    start: 'Adjust the seat so the handles are at chest height. Sit tall, back against the pad, hands on the handles with elbows slightly bent.',
    steps: ['Bring the handles together in front of the chest in a hugging motion.', 'Pause and squeeze.', 'Open slowly until the handles are in line with the chest.'],
    breath: 'Exhale as you close, inhale as you open.',
    posture: 'Back and head against the pad; shoulders down.',
    mistakes: ['Seat too low so shoulders roll forward', 'Letting the weight stack slam'],
    safety: ['Do not let the handles pull your arms behind the line of the body'],
    sets: '3', reps: '12–15', rest: '60 s', alts: { none: 'push-up', bands: 'band-chest-fly', dumbbells: 'db-floor-press' },
  },
  {
    id: 'chest-dip', name: 'Chest Dip', muscle: 'chest', secondary: ['Triceps', 'Front delts'],
    equip: 'homegym', gear: 'Parallel dip bars', type: 'bodyweight', mech: 'compound', level: 3,
    start: 'Support yourself on the bars with straight arms, lean the torso forward about 30°, knees slightly bent.',
    steps: ['Lower by bending the elbows until the upper arms are about parallel to the floor.', 'Keep the forward lean.', 'Press back up to straight arms.'],
    breath: 'Inhale on the way down, exhale pressing up.',
    posture: 'Shoulders down and back; do not shrug toward the ears.',
    mistakes: ['Going too deep with shoulders rolling forward', 'Staying upright (shifts work to triceps)', 'Swinging'],
    safety: ['Skip or limit depth if you have shoulder (AC joint) pain', 'Build up with push-ups first'],
    sets: '3', reps: '6–12', rest: '90 s', alts: { none: 'decline-push-up', bands: 'band-chest-press', dumbbells: 'db-floor-press' },
  },
  {
    id: 'push-up', name: 'Push-Up', muscle: 'chest', secondary: ['Triceps', 'Front delts', 'Core'],
    equip: 'none', gear: 'None', type: 'bodyweight', mech: 'compound', level: 1,
    start: 'Hands slightly wider than shoulders, fingers spread, body in a straight line from head to heels, glutes and core tight.',
    steps: ['Lower your chest toward the floor, elbows at roughly 45° from the body.', 'Go down until the chest is a fist-height from the floor.', 'Push the floor away to return to the top.'],
    breath: 'Inhale as you lower, exhale as you push.',
    posture: 'One straight line — no sagging hips or piked bottom. Neck neutral, eyes slightly ahead of hands.',
    mistakes: ['Hips sagging', 'Elbows flared straight out', 'Half reps', 'Head dropping first'],
    safety: ['Use the incline version if you cannot keep a straight body', 'Wrist pain: try push-up handles or fists on a mat'],
    sets: '3–4', reps: '8–20', rest: '60–90 s', alts: {},
  },
  {
    id: 'incline-push-up', name: 'Incline Push-Up', muscle: 'chest', secondary: ['Triceps', 'Front delts'],
    equip: 'none', gear: 'Bench, table or wall', type: 'bodyweight', mech: 'compound', level: 1,
    start: 'Hands on a sturdy raised surface (table edge, bed frame or wall), body straight, feet back.',
    steps: ['Lower the chest to the edge.', 'Press back to straight arms.', 'Lower the surface over the weeks to progress.'],
    breath: 'Inhale down, exhale up.', posture: C.ribs + ' Straight line head-to-heels.',
    mistakes: ['Hips piking', 'Using an unstable surface'], safety: ['Make sure the surface cannot slide'],
    sets: '3', reps: '10–20', rest: '60 s', alts: {},
  },
  {
    id: 'decline-push-up', name: 'Decline Push-Up', muscle: 'chest', secondary: ['Upper chest', 'Front delts', 'Triceps'],
    equip: 'none', gear: 'Chair, bed or step for the feet', type: 'bodyweight', mech: 'compound', level: 2,
    start: 'Feet on a raised surface, hands on the floor slightly wider than shoulders, body straight.',
    steps: ['Lower the chest toward the floor between the hands.', 'Press back up.', 'Higher feet = harder and more upper chest/shoulder emphasis.'],
    breath: 'Inhale down, exhale up.', posture: 'Keep glutes tight so the lower back does not sag.',
    mistakes: ['Lower back sagging', 'Neck cranes forward'], safety: ['Use a stable surface that will not tip'],
    sets: '3', reps: '8–15', rest: '60–90 s', alts: {},
  },
  {
    id: 'db-floor-press', name: 'Dumbbell Floor Press', muscle: 'chest', secondary: ['Triceps', 'Front delts'],
    equip: 'dumbbells', gear: 'Dumbbells', type: 'strength', mech: 'compound', level: 1,
    start: 'Lie on the floor, knees bent, dumbbells held above the chest, palms facing forward or each other.',
    steps: ['Lower until the upper arms touch the floor softly.', 'Pause briefly.', 'Press back up over the chest.'],
    breath: 'Inhale down, exhale up.', posture: 'Shoulder blades squeezed into the floor.',
    mistakes: ['Slamming elbows into the floor', 'Elbows flared to 90°'], safety: ['Roll to the side to set dumbbells down'],
    sets: '3–4', reps: '8–12', rest: '90 s', alts: { none: 'push-up' },
  },
  {
    id: 'band-chest-press', name: 'Resistance-Band Chest Press', muscle: 'chest', secondary: ['Triceps', 'Front delts'],
    equip: 'bands', gear: 'Tube band with door anchor or wrapped around the back', type: 'strength', mech: 'compound', level: 1,
    start: 'Anchor the band behind you at chest height (door anchor) or wrap it around your upper back. Step into a split stance, handles at chest level.',
    steps: ['Press the handles forward until the arms are straight.', 'Squeeze the chest.', 'Return slowly, resisting the band.'],
    breath: 'Exhale as you press, inhale on the return.', posture: 'Slight forward lean, core braced, shoulders down.',
    mistakes: ['Letting the band snap the arms back', 'Shrugging'], safety: ['Check the band for nicks before every session', 'Make sure the door is closed and locked toward you'],
    sets: '3', reps: '12–20', rest: '60 s', alts: { none: 'push-up' },
  },
  {
    id: 'band-chest-fly', name: 'Resistance-Band Chest Fly', muscle: 'chest', secondary: ['Front delts'],
    equip: 'bands', gear: 'Tube band with door anchor', type: 'strength', mech: 'isolation', level: 1,
    start: 'Anchor the band behind you at chest height, arms out wide, soft elbows.',
    steps: ['Hug the arms together in a wide arc.', 'Squeeze.', 'Open slowly under control.'],
    breath: 'Exhale as the hands meet.', posture: 'Chest up, ribs down.',
    mistakes: ['Bending the elbows into a press'], safety: ['Secure anchor point'],
    sets: '3', reps: '15–20', rest: '45–60 s', alts: { none: 'push-up' },
  },

  // ───────────── BACK ─────────────
  {
    id: 'lat-pulldown', name: 'Lat Pulldown', muscle: 'back', secondary: ['Biceps', 'Rear delts', 'Rhomboids'],
    equip: 'gym', gear: 'Lat pulldown machine', type: 'strength', mech: 'compound', level: 1,
    start: 'Thighs locked under the pad, grip the bar slightly wider than shoulders, arms straight, slight lean back.',
    steps: ['Pull the shoulder blades down first, then drive the elbows down toward the ribs.', 'Bring the bar to the upper chest.', 'Return under control to full arm extension.'],
    breath: 'Exhale as you pull down, inhale as the bar returns.', posture: 'Chest tall toward the bar; avoid leaning far back.',
    mistakes: ['Pulling behind the neck', 'Big body swing', 'Pulling with the hands rather than the elbows'],
    safety: ['Keep the bar in front of the head'], sets: '3–4', reps: '8–12', rest: '90 s',
    alts: { none: 'superman', bands: 'band-pulldown', dumbbells: 'db-row', homegym: 'pull-up' },
  },
  {
    id: 'pull-up', name: 'Pull-Up', muscle: 'back', secondary: ['Biceps', 'Rear delts', 'Core'],
    equip: 'homegym', gear: 'Pull-up bar', type: 'bodyweight', mech: 'compound', level: 3,
    start: 'Hang from the bar with an overhand grip slightly wider than shoulders, arms straight, legs together.',
    steps: ['Pull the shoulder blades down and back.', 'Drive the elbows down until the chin clears the bar.', 'Lower all the way to a straight-arm hang.'],
    breath: 'Exhale on the way up, inhale on the way down.', posture: 'Ribs down, slight hollow body, no swinging.',
    mistakes: ['Kipping or swinging', 'Half reps', 'Chin poking up to "reach" the bar'],
    safety: ['Use band assistance or negatives if you cannot do 3 strict reps', 'Check the bar is secure'], sets: '3–4', reps: '4–10', rest: '2 min',
    alts: { none: 'inverted-row', bands: 'band-pulldown' },
  },
  {
    id: 'seated-cable-row', name: 'Seated Cable Row', muscle: 'back', secondary: ['Biceps', 'Rear delts', 'Traps'],
    equip: 'gym', gear: 'Cable row station, V-handle', type: 'strength', mech: 'compound', level: 1,
    start: 'Sit with feet on the platform, knees soft, torso upright, arms extended holding the handle.',
    steps: ['Pull the handle to the lower ribs, driving the elbows back.', 'Squeeze the shoulder blades together.', 'Extend the arms slowly, letting the shoulder blades move forward without rounding the lower back.'],
    breath: 'Exhale as you pull, inhale on the return.', posture: 'Tall chest, neutral spine; torso stays nearly still.',
    mistakes: ['Rocking the torso back and forth', 'Shrugging the shoulders up', 'Rounding the lower back'],
    safety: ['Reduce load if the lower back takes over'], sets: '3–4', reps: '8–12', rest: '90 s',
    alts: { none: 'inverted-row', bands: 'band-row', dumbbells: 'db-row' },
  },
  {
    id: 'barbell-row', name: 'Barbell Bent-Over Row', muscle: 'back', secondary: ['Biceps', 'Rear delts', 'Spinal erectors'],
    equip: 'homegym', gear: 'Barbell', type: 'strength', mech: 'compound', level: 2,
    start: 'Hold the bar with an overhand grip just outside the knees. Hinge at the hips until the torso is about 30–45° from horizontal, knees soft, back flat.',
    steps: ['Row the bar toward the lower ribs/upper stomach.', 'Squeeze the shoulder blades.', 'Lower to straight arms without changing torso angle.'],
    breath: 'Brace before each rep; exhale at the top.', posture: 'Flat back, neck neutral, weight mid-foot.',
    mistakes: ['Standing up with each rep', 'Rounded back', 'Jerking the weight'],
    safety: ['Avoid if you have an acute lower-back problem — use a chest-supported row instead'], sets: '3–4', reps: '6–10', rest: '2 min',
    alts: { none: 'inverted-row', bands: 'band-row', dumbbells: 'db-row' },
  },
  {
    id: 'deadlift', name: 'Conventional Deadlift', muscle: 'back', secondary: ['Glutes', 'Hamstrings', 'Quads', 'Forearms', 'Traps'],
    equip: 'homegym', gear: 'Barbell and plates', type: 'strength', mech: 'compound', level: 3,
    start: 'Bar over mid-foot, feet hip-width. Hinge down and grip just outside the legs. Shins touch the bar, hips between knees and shoulders, back flat, chest up.',
    steps: ['Take the slack out of the bar ("pull yourself into position").', 'Push the floor away and stand up, keeping the bar against the legs.', 'Lock out by squeezing the glutes — do not lean back.', 'Lower by pushing the hips back, then bending the knees once the bar passes them.'],
    breath: 'Big breath into the belly and brace before each rep; exhale at the top or after setting the bar down.',
    posture: 'Neutral spine from neck to pelvis throughout. Shoulders slightly in front of the bar at the start.',
    mistakes: ['Rounding the lower back', 'Bar drifting away from the legs', 'Hips shooting up first', 'Hyper-extending at lockout'],
    safety: ['Learn the hip hinge with light weight first', 'Stop immediately with sharp back pain', 'Do not train to failure'], sets: '3–5', reps: '3–6', rest: '3 min',
    alts: { none: 'single-leg-rdl', bands: 'band-good-morning', dumbbells: 'db-rdl' },
  },
  {
    id: 'db-row', name: 'One-Arm Dumbbell Row', muscle: 'back', secondary: ['Biceps', 'Rear delts'],
    equip: 'dumbbells', gear: 'Dumbbell, bench or sturdy chair', type: 'strength', mech: 'compound', level: 1,
    start: 'One hand and knee on a bench (or hand on a chair), back flat and parallel-ish to the floor, dumbbell hanging under the shoulder.',
    steps: ['Row the dumbbell toward the hip, elbow close to the body.', 'Squeeze the shoulder blade back.', 'Lower to a full stretch.'],
    breath: 'Exhale as you row.', posture: 'Square hips and shoulders, flat back, no twisting.',
    mistakes: ['Twisting the torso to lift', 'Pulling to the chest instead of the hip'], safety: ['Keep the supporting arm straight and stable'],
    sets: '3–4', reps: '8–12 each', rest: '60–90 s', alts: { none: 'inverted-row', bands: 'band-row' },
  },
  {
    id: 'band-pulldown', name: 'Resistance-Band Lat Pulldown', muscle: 'back', secondary: ['Biceps', 'Rear delts'],
    equip: 'bands', gear: 'Band anchored high (door top) ', type: 'strength', mech: 'compound', level: 1,
    start: 'Anchor the band high. Kneel facing the anchor, arms extended up holding the band.',
    steps: ['Pull the elbows down to the sides of your ribs.', 'Squeeze the lats.', 'Return slowly overhead.'],
    breath: 'Exhale as you pull.', posture: 'Tall torso, slight lean back, ribs down.',
    mistakes: ['Shrugging', 'Rushing the return'], safety: ['Ensure the anchor is secure overhead'],
    sets: '3', reps: '12–20', rest: '60 s', alts: { none: 'superman' },
  },
  {
    id: 'band-row', name: 'Resistance-Band Row', muscle: 'back', secondary: ['Biceps', 'Rear delts'],
    equip: 'bands', gear: 'Band (loop around feet or door anchor)', type: 'strength', mech: 'compound', level: 1,
    start: 'Sit with legs straight and the band looped around the feet, or stand facing a chest-height anchor. Arms extended.',
    steps: ['Pull the handles to the lower ribs.', 'Squeeze the shoulder blades together.', 'Return slowly.'],
    breath: 'Exhale as you pull.', posture: 'Tall spine; do not lean back to cheat.',
    mistakes: ['Shrugging up', 'Rounding the back'], safety: ['Check band condition'],
    sets: '3', reps: '12–20', rest: '60 s', alts: { none: 'inverted-row' },
  },
  {
    id: 'band-good-morning', name: 'Resistance-Band Good Morning', muscle: 'hamstrings', secondary: ['Glutes', 'Spinal erectors'],
    equip: 'bands', gear: 'Loop band', type: 'strength', mech: 'compound', level: 1,
    start: 'Stand on the band, loop the other end behind your neck/upper back (on the traps).',
    steps: ['Push the hips back, keeping a flat back and soft knees.', 'Lower the torso until you feel a hamstring stretch.', 'Drive the hips forward to stand tall.'],
    breath: 'Inhale as you hinge, exhale as you stand.', posture: 'Neutral spine, weight in the heels.',
    mistakes: ['Rounding the back', 'Squatting instead of hinging'], safety: ['Keep the band off the neck bones — rest it on the upper back'],
    sets: '3', reps: '12–15', rest: '60 s', alts: { none: 'single-leg-rdl' },
  },
  {
    id: 'inverted-row', name: 'Inverted Row (Table Row)', muscle: 'back', secondary: ['Biceps', 'Rear delts', 'Core'],
    equip: 'none', gear: 'Sturdy table or low bar', type: 'bodyweight', mech: 'compound', level: 2,
    start: 'Lie under a sturdy table (or bar at hip height), grip the edge, body straight, heels on the floor.',
    steps: ['Pull your chest up to the edge.', 'Squeeze the shoulder blades.', 'Lower to straight arms.'],
    breath: 'Exhale up, inhale down.', posture: 'Straight body like a moving plank.',
    mistakes: ['Hips sagging', 'Partial range'], safety: ['Test that the table can take your full weight and cannot tip'],
    sets: '3', reps: '8–15', rest: '60–90 s', alts: {},
  },
  {
    id: 'superman', name: 'Superman Hold', muscle: 'back', secondary: ['Glutes', 'Spinal erectors'],
    equip: 'none', gear: 'Mat', type: 'bodyweight', mech: 'isolation', level: 1,
    start: 'Lie face-down, arms extended overhead, legs straight.',
    steps: ['Lift arms, chest and legs a few centimetres off the floor.', 'Hold for 2–3 s, squeezing the upper back and glutes.', 'Lower slowly.'],
    breath: 'Breathe steadily; do not hold the breath on long holds.', posture: 'Look at the floor to keep the neck neutral.',
    mistakes: ['Cranking the neck up', 'Lifting too high and pinching the lower back'], safety: ['Small range is enough'],
    sets: '3', reps: '10–12', rest: '45 s', alts: {},
  },
  {
    id: 'prone-ytw', name: 'Prone Y-T-W Raise', muscle: 'back', secondary: ['Rear delts', 'Lower traps', 'Rotator cuff'],
    equip: 'none', gear: 'Mat', type: 'bodyweight', mech: 'isolation', level: 1,
    start: 'Lie face-down, forehead on a folded towel, arms by your side.',
    steps: ['Raise the arms into a "Y" and hold 2 s.', 'Move to a "T" and hold 2 s.', 'Pull elbows into a "W" and hold 2 s. That is one rep.'],
    breath: 'Steady breathing.', posture: 'Thumbs up, shoulders down away from the ears.',
    mistakes: ['Shrugging', 'Arching the lower back'], safety: ['Great as a warm-up for pressing days'],
    sets: '2–3', reps: '6–8', rest: '45 s', alts: {},
  },

  // ───────────── SHOULDERS ─────────────
  {
    id: 'ohp', name: 'Barbell Overhead Press', muscle: 'shoulders', secondary: ['Triceps', 'Upper chest', 'Core'],
    equip: 'homegym', gear: 'Barbell, rack', type: 'strength', mech: 'compound', level: 2,
    start: 'Bar on the front of the shoulders, grip just outside shoulder width, elbows slightly in front of the bar, feet hip-width, glutes squeezed.',
    steps: ['Move the head back slightly and press the bar straight up.', 'Once the bar passes the forehead, push the head "through the window".', 'Lock out overhead with the bar over mid-foot.', 'Lower to the shoulders under control.'],
    breath: 'Brace before each rep; exhale at the top.', posture: 'Ribs down, glutes tight — do not lean back into a standing incline press.',
    mistakes: ['Excessive lower-back arch', 'Pressing the bar forward around the face', 'Flared elbows at the start'],
    safety: ['Reduce load if you cannot keep ribs down', 'Avoid with active shoulder impingement — consult a physiotherapist'], sets: '3–5', reps: '5–8', rest: '2–3 min',
    alts: { none: 'pike-push-up', bands: 'band-ohp', dumbbells: 'db-shoulder-press' },
  },
  {
    id: 'db-shoulder-press', name: 'Seated Dumbbell Shoulder Press', muscle: 'shoulders', secondary: ['Triceps', 'Upper chest'],
    equip: 'dumbbells', gear: 'Dumbbells (bench optional)', type: 'strength', mech: 'compound', level: 1,
    start: 'Sit tall (bench back upright if available), dumbbells at shoulder height, palms forward, elbows slightly in front of the body.',
    steps: ['Press the dumbbells up until the arms are straight overhead.', 'Lower slowly to ear/chin level.'],
    breath: 'Exhale as you press.', posture: 'Back against the pad, ribs down.',
    mistakes: ['Arching the back off the bench', 'Banging dumbbells together at the top'], safety: ['Start light — shoulders fatigue quickly'],
    sets: '3–4', reps: '8–12', rest: '90 s', alts: { none: 'pike-push-up', bands: 'band-ohp' },
  },
  {
    id: 'lateral-raise', name: 'Dumbbell Lateral Raise', muscle: 'shoulders', secondary: ['Upper traps'],
    equip: 'dumbbells', gear: 'Light dumbbells', type: 'strength', mech: 'isolation', level: 1,
    start: 'Stand tall, dumbbells at the sides, slight bend in the elbows, slight forward lean.',
    steps: ['Raise the arms out to the sides until they reach shoulder height.', 'Lead with the elbows, pinkies roughly level with thumbs.', 'Lower slowly over 2–3 s.'],
    breath: 'Exhale as you raise.', posture: 'Shoulders down; neck relaxed.',
    mistakes: ['Swinging with momentum', 'Shrugging', 'Raising far above shoulder height'], safety: ['Light weights, strict form'],
    sets: '3–4', reps: '12–20', rest: '60 s', alts: { none: 'pike-push-up', bands: 'band-lateral-raise' },
  },
  {
    id: 'cable-lateral-raise', name: 'Cable Lateral Raise', muscle: 'shoulders', secondary: [],
    equip: 'gym', gear: 'Low cable pulley', type: 'strength', mech: 'isolation', level: 1,
    start: 'Stand side-on to a low pulley, handle in the far hand across the front of the body.',
    steps: ['Raise the arm out to the side to shoulder height.', 'Lower slowly to the start.'],
    breath: 'Exhale up.', posture: 'Tall stance, other hand holding the machine.',
    mistakes: ['Leaning away to cheat'], safety: ['Light load'],
    sets: '3', reps: '12–15 each', rest: '45–60 s', alts: { none: 'pike-push-up', bands: 'band-lateral-raise', dumbbells: 'lateral-raise' },
  },
  {
    id: 'face-pull', name: 'Cable Face Pull', muscle: 'shoulders', secondary: ['Rear delts', 'Rotator cuff', 'Mid traps'],
    equip: 'gym', gear: 'Cable with rope at upper-chest/face height', type: 'strength', mech: 'isolation', level: 1,
    start: 'Grip the rope with thumbs pointing back, step back so the arms are straight.',
    steps: ['Pull the rope toward your face, splitting the ends apart.', 'Finish with hands beside the ears, elbows high ("double biceps" pose).', 'Return slowly.'],
    breath: 'Exhale as you pull.', posture: 'Ribs down, do not lean back.',
    mistakes: ['Using too much weight', 'Pulling to the chest with elbows low'], safety: ['Excellent shoulder-health exercise — keep it light'],
    sets: '3', reps: '12–20', rest: '60 s', alts: { none: 'prone-ytw', bands: 'band-face-pull', dumbbells: 'reverse-db-fly' },
  },
  {
    id: 'reverse-db-fly', name: 'Bent-Over Reverse Dumbbell Fly', muscle: 'shoulders', secondary: ['Rear delts', 'Rhomboids'],
    equip: 'dumbbells', gear: 'Light dumbbells', type: 'strength', mech: 'isolation', level: 1,
    start: 'Hinge forward until the torso is nearly parallel to the floor, dumbbells hanging, soft elbows.',
    steps: ['Raise the arms out to the sides.', 'Squeeze the back of the shoulders.', 'Lower slowly.'],
    breath: 'Exhale as you raise.', posture: 'Flat back, neck neutral.',
    mistakes: ['Using momentum', 'Rounding the back'], safety: ['Light weights only'],
    sets: '3', reps: '12–15', rest: '60 s', alts: { none: 'prone-ytw', bands: 'band-face-pull' },
  },
  {
    id: 'pike-push-up', name: 'Pike Push-Up', muscle: 'shoulders', secondary: ['Triceps', 'Upper chest'],
    equip: 'none', gear: 'None (feet on a step to progress)', type: 'bodyweight', mech: 'compound', level: 2,
    start: 'Start in a push-up position and walk the feet in, lifting the hips high into an inverted "V". Hands shoulder-width.',
    steps: ['Bend the elbows and lower the top of the head toward a point slightly in front of the hands.', 'Press back up to straight arms.'],
    breath: 'Inhale down, exhale up.', posture: 'Hips high, elbows track back at about 45°.',
    mistakes: ['Hips dropping into a normal push-up', 'Elbows flaring wide'], safety: ['Control the descent — do not hit your head'],
    sets: '3', reps: '6–12', rest: '90 s', alts: {},
  },
  {
    id: 'band-ohp', name: 'Resistance-Band Overhead Press', muscle: 'shoulders', secondary: ['Triceps'],
    equip: 'bands', gear: 'Loop or tube band', type: 'strength', mech: 'compound', level: 1,
    start: 'Stand on the band, handles at shoulder height, palms forward.',
    steps: ['Press up until the arms are straight overhead.', 'Lower slowly to shoulder height.'],
    breath: 'Exhale as you press.', posture: 'Ribs down, glutes tight.', mistakes: ['Arching the lower back'], safety: ['Keep the band securely under the feet'],
    sets: '3', reps: '12–15', rest: '60 s', alts: { none: 'pike-push-up' },
  },
  {
    id: 'band-lateral-raise', name: 'Resistance-Band Lateral Raise', muscle: 'shoulders', secondary: [],
    equip: 'bands', gear: 'Light band', type: 'strength', mech: 'isolation', level: 1,
    start: 'Stand on the middle of the band, handles at the sides.',
    steps: ['Raise arms to shoulder height.', 'Lower slowly.'], breath: 'Exhale up.', posture: 'Shoulders down.',
    mistakes: ['Shrugging'], safety: ['Use a light band'], sets: '3', reps: '15–20', rest: '45 s', alts: { none: 'pike-push-up' },
  },
  {
    id: 'band-face-pull', name: 'Resistance-Band Face Pull', muscle: 'shoulders', secondary: ['Rear delts', 'Rotator cuff'],
    equip: 'bands', gear: 'Band anchored at face height', type: 'strength', mech: 'isolation', level: 1,
    start: 'Hold the band with arms straight at face height.', steps: ['Pull toward the face, elbows high, hands finishing by the ears.', 'Return slowly.'],
    breath: 'Exhale as you pull.', posture: 'Tall, ribs down.', mistakes: ['Elbows dropping'], safety: ['Secure anchor'],
    sets: '3', reps: '15–20', rest: '45 s', alts: { none: 'prone-ytw' },
  },

  // ───────────── BICEPS ─────────────
  {
    id: 'barbell-curl', name: 'Barbell Curl', muscle: 'biceps', secondary: ['Brachialis', 'Forearms'],
    equip: 'homegym', gear: 'Barbell or EZ-bar', type: 'strength', mech: 'isolation', level: 1,
    start: 'Stand tall, underhand grip at shoulder width, arms straight, elbows by the sides.',
    steps: ['Curl the bar up by bending the elbows only.', 'Squeeze at the top without letting the elbows drift forward much.', 'Lower slowly to straight arms.'],
    breath: 'Exhale as you curl.', posture: 'No hip swing; shoulders back.',
    mistakes: ['Swinging the body', 'Cutting the bottom range short'], safety: ['Use an EZ-bar if straight-bar curls bother the wrists'],
    sets: '3', reps: '8–12', rest: '60–90 s', alts: { none: 'backpack-curl', bands: 'band-curl', dumbbells: 'hammer-curl' },
  },
  {
    id: 'cable-curl', name: 'Cable Biceps Curl', muscle: 'biceps', secondary: ['Forearms'],
    equip: 'gym', gear: 'Low cable with straight bar or rope', type: 'strength', mech: 'isolation', level: 1,
    start: 'Face a low pulley, hold the bar underhand, arms straight.', steps: ['Curl up keeping the elbows by the sides.', 'Squeeze.', 'Lower slowly.'],
    breath: 'Exhale up.', posture: 'Tall, still torso.', mistakes: ['Leaning back'], safety: ['Moderate weight'],
    sets: '3', reps: '10–15', rest: '60 s', alts: { none: 'backpack-curl', bands: 'band-curl', dumbbells: 'hammer-curl' },
  },
  {
    id: 'hammer-curl', name: 'Dumbbell Hammer Curl', muscle: 'biceps', secondary: ['Brachialis', 'Brachioradialis'],
    equip: 'dumbbells', gear: 'Dumbbells', type: 'strength', mech: 'isolation', level: 1,
    start: 'Stand with dumbbells at the sides, palms facing each other.', steps: ['Curl up keeping palms facing in.', 'Lower slowly.'],
    breath: 'Exhale up.', posture: 'Elbows pinned to the sides.', mistakes: ['Swinging'], safety: ['Control the lowering'],
    sets: '3', reps: '10–12', rest: '60 s', alts: { none: 'backpack-curl', bands: 'band-curl' },
  },
  {
    id: 'incline-db-curl', name: 'Incline Dumbbell Curl', muscle: 'biceps', secondary: ['Biceps long head'],
    equip: 'homegym', gear: 'Dumbbells, incline bench (45–60°)', type: 'strength', mech: 'isolation', level: 2,
    start: 'Sit back on an incline bench, arms hanging straight down behind the body line, palms forward.',
    steps: ['Curl up without moving the upper arm forward.', 'Lower slowly into a full stretch.'], breath: 'Exhale up.', posture: 'Head and back on the bench.',
    mistakes: ['Upper arm swinging forward'], safety: ['Lighter than standing curls'], sets: '3', reps: '10–12', rest: '60 s',
    alts: { none: 'backpack-curl', bands: 'band-curl', dumbbells: 'hammer-curl' },
  },
  {
    id: 'preacher-curl', name: 'Preacher Curl (Machine or EZ-Bar)', muscle: 'biceps', secondary: ['Brachialis'],
    equip: 'gym', gear: 'Preacher bench / machine', type: 'strength', mech: 'isolation', level: 1,
    start: 'Upper arms flat on the pad, armpits snug to the top edge, underhand grip.',
    steps: ['Curl up until the forearms are near vertical.', 'Lower slowly to almost straight.'], breath: 'Exhale up.', posture: 'Chest against pad.',
    mistakes: ['Dropping fast into a locked elbow'], safety: ['Avoid bouncing at the bottom — this stresses the elbow'], sets: '3', reps: '10–12', rest: '60 s',
    alts: { none: 'backpack-curl', bands: 'band-curl', dumbbells: 'hammer-curl' },
  },
  {
    id: 'chin-up', name: 'Chin-Up', muscle: 'biceps', secondary: ['Lats', 'Rear delts'],
    equip: 'homegym', gear: 'Pull-up bar', type: 'bodyweight', mech: 'compound', level: 3,
    start: 'Hang with an underhand, shoulder-width grip.', steps: ['Pull until the chin is over the bar.', 'Lower fully.'],
    breath: 'Exhale up.', posture: 'Slight hollow body; no swinging.', mistakes: ['Half reps', 'Kipping'], safety: ['Use negatives to build up'],
    sets: '3', reps: '4–10', rest: '2 min', alts: { none: 'inverted-row', bands: 'band-curl' },
  },
  {
    id: 'band-curl', name: 'Resistance-Band Curl', muscle: 'biceps', secondary: ['Forearms'],
    equip: 'bands', gear: 'Band', type: 'strength', mech: 'isolation', level: 1,
    start: 'Stand on the band with feet hip-width, handles in hand, palms forward.', steps: ['Curl up, elbows fixed.', 'Lower slowly — resist the band.'],
    breath: 'Exhale up.', posture: 'Tall and still.', mistakes: ['Letting the band yank the arms down'], safety: ['Check band for tears'],
    sets: '3', reps: '12–20', rest: '45–60 s', alts: { none: 'backpack-curl' },
  },
  {
    id: 'backpack-curl', name: 'Backpack Curl', muscle: 'biceps', secondary: ['Forearms'],
    equip: 'none', gear: 'Backpack loaded with books or water bottles', type: 'strength', mech: 'isolation', level: 1,
    start: 'Hold a loaded backpack by the top handle or both straps, arms straight.', steps: ['Curl the bag up keeping elbows by your sides.', 'Lower slowly over 3 s.'],
    breath: 'Exhale up.', posture: 'Tall, no swinging.', mistakes: ['Overloading so you swing'], safety: ['Make sure the handle/straps are strong'],
    sets: '3', reps: '12–20', rest: '60 s', alts: {},
  },

  // ───────────── TRICEPS ─────────────
  {
    id: 'cable-pushdown', name: 'Cable Triceps Pushdown', muscle: 'triceps', secondary: [],
    equip: 'gym', gear: 'High cable, rope or straight bar', type: 'strength', mech: 'isolation', level: 1,
    start: 'Face the high pulley, elbows tucked at the sides, forearms about parallel to the floor.',
    steps: ['Push down until the elbows are straight (split the rope at the bottom).', 'Return to forearms parallel without the elbows moving forward.'],
    breath: 'Exhale as you push.', posture: 'Slight forward lean, shoulders down.', mistakes: ['Elbows flaring or drifting', 'Leaning over the weight'], safety: ['Moderate load'],
    sets: '3', reps: '10–15', rest: '60 s', alts: { none: 'bench-dip', bands: 'band-pushdown', dumbbells: 'overhead-db-extension' },
  },
  {
    id: 'skull-crusher', name: 'EZ-Bar Skull Crusher', muscle: 'triceps', secondary: [],
    equip: 'homegym', gear: 'EZ-bar, flat bench', type: 'strength', mech: 'isolation', level: 2,
    start: 'Lie on a bench, hold the bar over the shoulders with a narrow grip, arms angled slightly back toward the head.',
    steps: ['Bend the elbows to lower the bar toward the top of the head / just behind it.', 'Extend back to the start.'],
    breath: 'Inhale down, exhale up.', posture: 'Upper arms stay still.', mistakes: ['Elbows flaring out', 'Going too heavy'], safety: ['Use a spotter or choose a weight you fully control — the bar travels near the face'],
    sets: '3', reps: '8–12', rest: '60–90 s', alts: { none: 'diamond-push-up', bands: 'band-overhead-extension', dumbbells: 'overhead-db-extension' },
  },
  {
    id: 'close-grip-bench', name: 'Close-Grip Bench Press', muscle: 'triceps', secondary: ['Chest', 'Front delts'],
    equip: 'homegym', gear: 'Barbell, bench, rack', type: 'strength', mech: 'compound', level: 2,
    start: 'Set up like a bench press but grip at about shoulder width.', steps: ['Lower to the lower chest with elbows tucked.', 'Press up.'],
    breath: 'Brace and inhale down; exhale up.', posture: 'Shoulder blades pinned.', mistakes: ['Grip too narrow (wrist strain)'], safety: ['Use safety pins'],
    sets: '3–4', reps: '6–10', rest: '2 min', alts: { none: 'diamond-push-up', bands: 'band-pushdown', dumbbells: 'db-floor-press' },
  },
  {
    id: 'overhead-db-extension', name: 'Overhead Dumbbell Triceps Extension', muscle: 'triceps', secondary: ['Triceps long head'],
    equip: 'dumbbells', gear: 'One dumbbell', type: 'strength', mech: 'isolation', level: 1,
    start: 'Sit or stand tall holding one dumbbell overhead with both hands under the top plate.',
    steps: ['Lower the dumbbell behind the head by bending the elbows.', 'Extend back up to straight arms.'], breath: 'Inhale down, exhale up.',
    posture: 'Elbows point forward, ribs down.', mistakes: ['Flaring elbows', 'Arching the back'], safety: ['Grip securely — the weight is over your head'],
    sets: '3', reps: '10–12', rest: '60 s', alts: { none: 'bench-dip', bands: 'band-overhead-extension' },
  },
  {
    id: 'bench-dip', name: 'Bench / Chair Dip', muscle: 'triceps', secondary: ['Chest', 'Front delts'],
    equip: 'none', gear: 'Sturdy chair or bench', type: 'bodyweight', mech: 'compound', level: 1,
    start: 'Hands on the edge of a stable chair behind you, fingers forward, legs bent (easier) or straight (harder), hips close to the chair.',
    steps: ['Lower by bending the elbows to about 90°.', 'Press back up to straight arms.'], breath: 'Inhale down, exhale up.',
    posture: 'Shoulders down and back, chest up, hips stay close to the chair.', mistakes: ['Dropping too deep', 'Shoulders rolling forward'],
    safety: ['Stop at 90° elbow bend; skip if it hurts the front of the shoulder', 'Chair against a wall so it cannot slide'],
    sets: '3', reps: '10–15', rest: '60 s', alts: {},
  },
  {
    id: 'diamond-push-up', name: 'Diamond (Close-Grip) Push-Up', muscle: 'triceps', secondary: ['Chest', 'Front delts'],
    equip: 'none', gear: 'None', type: 'bodyweight', mech: 'compound', level: 2,
    start: 'Push-up position with hands close together under the chest (index fingers and thumbs forming a diamond, or simply narrow).',
    steps: ['Lower the chest toward the hands, elbows close to the body.', 'Press up.'], breath: 'Inhale down, exhale up.', posture: 'Straight line head-to-heels.',
    mistakes: ['Elbows flaring', 'Hips sagging'], safety: ['Hands slightly wider if wrists hurt'], sets: '3', reps: '6–15', rest: '60–90 s', alts: {},
  },
  {
    id: 'band-pushdown', name: 'Resistance-Band Triceps Pushdown', muscle: 'triceps', secondary: [],
    equip: 'bands', gear: 'Band anchored high', type: 'strength', mech: 'isolation', level: 1,
    start: 'Face a high anchor, elbows at the sides.', steps: ['Push down to straight arms.', 'Return slowly.'], breath: 'Exhale down.',
    posture: 'Elbows stay still.', mistakes: ['Elbows drifting forward'], safety: ['Secure anchor'], sets: '3', reps: '15–20', rest: '45 s', alts: { none: 'bench-dip' },
  },
  {
    id: 'band-overhead-extension', name: 'Resistance-Band Overhead Extension', muscle: 'triceps', secondary: ['Triceps long head'],
    equip: 'bands', gear: 'Band', type: 'strength', mech: 'isolation', level: 1,
    start: 'Stand on the band in a split stance, hold the band behind your head with elbows pointing up.', steps: ['Extend the arms overhead.', 'Return slowly.'],
    breath: 'Exhale up.', posture: 'Ribs down.', mistakes: ['Elbows flaring'], safety: ['Check band'], sets: '3', reps: '12–20', rest: '45 s', alts: { none: 'diamond-push-up' },
  },

  // ───────────── FOREARMS ─────────────
  {
    id: 'wrist-curl', name: 'Dumbbell Wrist Curl', muscle: 'forearms', secondary: ['Wrist flexors'],
    equip: 'dumbbells', gear: 'Light dumbbells, bench', type: 'strength', mech: 'isolation', level: 1,
    start: 'Sit with forearms resting on the thighs, palms up, wrists just past the knees.', steps: ['Let the dumbbell roll down to the fingers.', 'Curl the wrist up as high as possible.', 'Lower slowly.'],
    breath: 'Breathe normally.', posture: 'Forearms stay on the thighs.', mistakes: ['Using the whole arm'], safety: ['Light weight, high reps'],
    sets: '3', reps: '15–20', rest: '45 s', alts: { none: 'towel-wring', bands: 'towel-wring' },
  },
  {
    id: 'reverse-wrist-curl', name: 'Reverse Wrist Curl', muscle: 'forearms', secondary: ['Wrist extensors'],
    equip: 'dumbbells', gear: 'Light dumbbells', type: 'strength', mech: 'isolation', level: 1,
    start: 'Forearms on thighs, palms down.', steps: ['Raise the back of the hand up.', 'Lower slowly.'], breath: 'Breathe normally.',
    posture: 'Forearms still.', mistakes: ['Too heavy'], safety: ['Helpful for "tennis elbow" prevention, but stop if painful'],
    sets: '3', reps: '15–20', rest: '45 s', alts: { none: 'towel-wring' },
  },
  {
    id: 'farmer-carry', name: "Farmer's Carry", muscle: 'forearms', secondary: ['Traps', 'Core', 'Glutes'],
    equip: 'dumbbells', gear: 'Heavy dumbbells or kettlebells', type: 'strength', mech: 'compound', level: 1,
    start: 'Pick up a heavy dumbbell in each hand with a proper hip hinge. Stand tall.', steps: ['Walk with short, controlled steps for the set distance/time.', 'Set the weights down with a hinge.'],
    breath: 'Short, braced breaths.', posture: 'Tall chest, shoulders down and back, no leaning.', mistakes: ['Shrugging', 'Leaning to one side'], safety: ['Clear walking path'],
    sets: '3', reps: '30–40 m', rest: '90 s', alts: { none: 'dead-hang' },
  },
  {
    id: 'dead-hang', name: 'Dead Hang', muscle: 'forearms', secondary: ['Lats', 'Shoulders'],
    equip: 'homegym', gear: 'Pull-up bar', type: 'bodyweight', mech: 'isolation', level: 1,
    start: 'Grip the bar overhand, shoulder-width.', steps: ['Hang with arms straight and feet off the floor.', 'Keep the shoulders gently engaged (not fully slumped).', 'Hold for time.'],
    breath: 'Breathe slowly.', posture: 'Relaxed legs, active shoulders.', mistakes: ['Letting shoulders fully collapse into the ears'], safety: ['Step down carefully'],
    sets: '3', reps: '20–45 s', rest: '60 s', alts: { none: 'towel-wring' },
  },
  {
    id: 'towel-wring', name: 'Towel Wring', muscle: 'forearms', secondary: ['Grip'],
    equip: 'none', gear: 'Thick towel (wet for more resistance)', type: 'strength', mech: 'isolation', level: 1,
    start: 'Hold a rolled towel horizontally in front of you with both hands.', steps: ['Twist the hands in opposite directions as hard as you can, like wringing water out.', 'Hold 5 s, then reverse direction.'],
    breath: 'Do not hold your breath.', posture: 'Elbows bent, shoulders relaxed.', mistakes: ['Shrugging'], safety: ['Easy on irritated elbows'],
    sets: '3', reps: '6 each way', rest: '45 s', alts: {},
  },

  // ───────────── ABS ─────────────
  {
    id: 'cable-crunch', name: 'Kneeling Cable Crunch', muscle: 'abs', secondary: ['Obliques'],
    equip: 'gym', gear: 'High cable with rope', type: 'core', mech: 'isolation', level: 2,
    start: 'Kneel facing the pulley, hold the rope beside your head, hips stay high.', steps: ['Crunch down by curling the ribs toward the pelvis.', 'Return slowly to a long spine.'],
    breath: 'Exhale fully as you crunch.', posture: 'Hips stay still; movement comes from the spine.', mistakes: ['Pulling with the arms', 'Sitting back on the heels'], safety: ['Moderate weight'],
    sets: '3', reps: '12–15', rest: '60 s', alts: { none: 'crunch', bands: 'crunch', dumbbells: 'crunch' },
  },
  {
    id: 'hanging-leg-raise', name: 'Hanging Leg Raise', muscle: 'abs', secondary: ['Hip flexors', 'Grip'],
    equip: 'homegym', gear: 'Pull-up bar', type: 'core', mech: 'isolation', level: 3,
    start: 'Hang from the bar, legs together.', steps: ['Raise the legs (bent = easier, straight = harder) while curling the pelvis up.', 'Lower slowly without swinging.'],
    breath: 'Exhale as you lift.', posture: 'Active shoulders, minimal swing.', mistakes: ['Swinging', 'Only lifting the legs without curling the pelvis'], safety: ['Start with knee raises'],
    sets: '3', reps: '8–12', rest: '60–90 s', alts: { none: 'reverse-crunch' },
  },
  {
    id: 'plank', name: 'Front Plank', muscle: 'abs', secondary: ['Shoulders', 'Glutes'],
    equip: 'none', gear: 'Mat', type: 'core', mech: 'isolation', level: 1,
    start: 'Forearms on the floor under the shoulders, legs straight, toes tucked.', steps: ['Lift into a straight line from head to heels.', 'Squeeze glutes, pull belly button gently in, and hold.'],
    breath: 'Slow, controlled breathing through the hold.', posture: 'Neutral neck, no sagging or piking.', mistakes: ['Hips sagging', 'Holding the breath', 'Bottom too high'],
    safety: ['Stop when form breaks — 3 good 30 s holds beat one sloppy 2-min hold'], sets: '3', reps: '20–60 s', rest: '45 s', alts: {},
  },
  {
    id: 'crunch', name: 'Crunch', muscle: 'abs', secondary: [],
    equip: 'none', gear: 'Mat', type: 'core', mech: 'isolation', level: 1,
    start: 'Lie on the back, knees bent, feet flat, fingertips lightly behind the ears or arms crossed on chest.', steps: ['Curl the shoulders off the floor by bringing ribs toward hips.', 'Pause, then lower slowly.'],
    breath: 'Exhale as you curl up.', posture: 'Space between chin and chest.', mistakes: ['Pulling on the neck', 'Using momentum'], safety: ['Keep the range small and controlled'],
    sets: '3', reps: '15–20', rest: '45 s', alts: {},
  },
  {
    id: 'dead-bug', name: 'Dead Bug', muscle: 'abs', secondary: ['Deep core (transversus)'],
    equip: 'none', gear: 'Mat', type: 'core', mech: 'isolation', level: 1,
    start: 'Lie on the back, arms reaching to the ceiling, hips and knees at 90°.', steps: ['Press the lower back gently into the floor.', 'Slowly extend opposite arm and leg toward the floor.', 'Return and switch sides.'],
    breath: 'Exhale as you extend.', posture: 'Lower back stays in contact with the floor.', mistakes: ['Back arching off the floor', 'Moving fast'], safety: ['Very back-friendly core exercise'],
    sets: '3', reps: '8–10 each side', rest: '45 s', alts: {},
  },
  {
    id: 'reverse-crunch', name: 'Reverse Crunch', muscle: 'abs', secondary: ['Lower abs emphasis'],
    equip: 'none', gear: 'Mat', type: 'core', mech: 'isolation', level: 1,
    start: 'Lie on the back, hands by the sides, knees bent at 90° with feet in the air.', steps: ['Curl the hips off the floor, bringing knees toward the chest.', 'Lower slowly.'],
    breath: 'Exhale as you curl.', posture: 'Upper back stays down.', mistakes: ['Swinging the legs'], safety: ['Slow and controlled'],
    sets: '3', reps: '12–15', rest: '45 s', alts: {},
  },
  {
    id: 'ab-wheel', name: 'Ab Wheel Rollout', muscle: 'abs', secondary: ['Lats', 'Shoulders'],
    equip: 'homegym', gear: 'Ab wheel', type: 'core', mech: 'compound', level: 3,
    start: 'Kneel on a mat with the wheel under the shoulders.', steps: ['Roll forward slowly, keeping the hips in line and abs braced.', 'Go only as far as you can without the lower back sagging.', 'Pull back with the abs.'],
    breath: 'Inhale as you roll out, exhale back.', posture: 'Slight posterior pelvic tilt (tuck the tail).', mistakes: ['Lower back sagging', 'Going too far too soon'], safety: ['Progress range slowly; avoid with lower-back pain'],
    sets: '3', reps: '6–12', rest: '60–90 s', alts: { none: 'plank' },
  },

  // ───────────── OBLIQUES ─────────────
  {
    id: 'cable-woodchop', name: 'Cable Woodchop', muscle: 'obliques', secondary: ['Abs', 'Shoulders'],
    equip: 'gym', gear: 'Cable, handle', type: 'core', mech: 'compound', level: 2,
    start: 'Stand side-on to a high pulley, both hands on the handle, feet wider than shoulders.', steps: ['Rotate and pull the handle diagonally down across the body to the opposite hip.', 'Pivot the back foot.', 'Return slowly.'],
    breath: 'Exhale through the chop.', posture: 'Arms fairly straight; rotation from the trunk and hips.', mistakes: ['Pulling with the arms only'], safety: ['Moderate load'],
    sets: '3', reps: '10–12 each', rest: '60 s', alts: { none: 'russian-twist', bands: 'pallof-press' },
  },
  {
    id: 'side-plank', name: 'Side Plank', muscle: 'obliques', secondary: ['Glute medius', 'Shoulders'],
    equip: 'none', gear: 'Mat', type: 'core', mech: 'isolation', level: 1,
    start: 'Lie on your side, elbow under the shoulder, legs stacked (or knees bent for easier).', steps: ['Lift the hips into a straight line.', 'Hold, then switch sides.'],
    breath: 'Steady breathing.', posture: 'Hips forward, not piked back.', mistakes: ['Hips sagging'], safety: ['Bend the knees to regress'],
    sets: '3', reps: '20–45 s each', rest: '45 s', alts: {},
  },
  {
    id: 'russian-twist', name: 'Russian Twist', muscle: 'obliques', secondary: ['Abs', 'Hip flexors'],
    equip: 'none', gear: 'Mat (water bottle optional)', type: 'core', mech: 'isolation', level: 1,
    start: 'Sit with knees bent, lean back about 45° with a tall chest, feet down (easier) or up.', steps: ['Rotate the shoulders to one side, bringing the hands beside the hip.', 'Rotate to the other side.'],
    breath: 'Exhale on each twist.', posture: 'Long spine, move from the ribcage.', mistakes: ['Just moving the arms', 'Rounding the back'], safety: ['Skip if it aggravates lower-back pain — use side planks'],
    sets: '3', reps: '10–15 each side', rest: '45 s', alts: {},
  },
  {
    id: 'pallof-press', name: 'Pallof Press (Band)', muscle: 'obliques', secondary: ['Deep core'],
    equip: 'bands', gear: 'Band anchored at chest height', type: 'core', mech: 'isolation', level: 1,
    start: 'Stand side-on to the anchor, band held at the chest with both hands, feet shoulder-width.', steps: ['Press the hands straight out in front.', 'Resist the band pulling you to rotate; hold 2 s.', 'Return to the chest.'],
    breath: 'Exhale as you press.', posture: 'Square hips and shoulders.', mistakes: ['Letting the torso rotate'], safety: ['Back-friendly anti-rotation work'],
    sets: '3', reps: '10–12 each side', rest: '45 s', alts: { none: 'side-plank' },
  },
  {
    id: 'bicycle-crunch', name: 'Bicycle Crunch', muscle: 'obliques', secondary: ['Abs'],
    equip: 'none', gear: 'Mat', type: 'core', mech: 'isolation', level: 1,
    start: 'Lie on the back, hands lightly behind the head, legs raised with knees bent.', steps: ['Bring one elbow toward the opposite knee while extending the other leg.', 'Switch sides in a slow pedalling motion.'],
    breath: 'Exhale on each twist.', posture: 'Lower back pressed down.', mistakes: ['Pulling on the neck', 'Going too fast'], safety: ['Slow tempo'],
    sets: '3', reps: '12–20 each side', rest: '45 s', alts: {},
  },

  // ───────────── QUADS ─────────────
  {
    id: 'back-squat', name: 'Barbell Back Squat', muscle: 'quads', secondary: ['Glutes', 'Adductors', 'Core', 'Spinal erectors'],
    equip: 'homegym', gear: 'Barbell, squat rack', type: 'strength', mech: 'compound', level: 3,
    start: 'Bar on the upper traps, hands just outside shoulders, feet shoulder-width, toes slightly out.',
    steps: ['Brace, then sit down between the hips by bending hips and knees together.', 'Knees track over the toes.', 'Descend to at least thighs parallel if mobility allows.', 'Drive up through the whole foot.'],
    breath: 'Big breath and brace at the top; hold on the way down; exhale near the top.', posture: 'Chest up, neutral spine, whole foot planted.',
    mistakes: ['Knees caving in', 'Heels lifting', 'Lower back rounding at the bottom ("butt wink")', 'Bouncing out of the hole'],
    safety: ['Always use safety bars set just below your bottom position', 'Learn to bail the bar safely', 'Stop with sharp knee or back pain'], sets: '3–5', reps: '5–8', rest: '2–3 min',
    alts: { none: 'bodyweight-squat', bands: 'bodyweight-squat', dumbbells: 'goblet-squat' },
  },
  {
    id: 'leg-press', name: 'Leg Press', muscle: 'quads', secondary: ['Glutes', 'Adductors'],
    equip: 'gym', gear: 'Leg press machine', type: 'strength', mech: 'compound', level: 1,
    start: 'Sit with back flat on the pad, feet shoulder-width in the middle of the platform.', steps: ['Release the safeties and lower the platform until the knees reach about 90°.', 'Press back without locking the knees hard.'],
    breath: 'Inhale down, exhale up.', posture: 'Lower back and hips stay glued to the pad.', mistakes: ['Going so deep the hips roll off the pad', 'Locking knees out', 'Knees caving in'],
    safety: ['Always re-engage safeties before getting out'], sets: '3–4', reps: '10–15', rest: '90 s',
    alts: { none: 'bulgarian-split-squat', bands: 'bulgarian-split-squat', dumbbells: 'goblet-squat' },
  },
  {
    id: 'leg-extension', name: 'Leg Extension', muscle: 'quads', secondary: [],
    equip: 'gym', gear: 'Leg extension machine', type: 'strength', mech: 'isolation', level: 1,
    start: 'Sit with the knee joint in line with the machine pivot, pad on the lower shins.', steps: ['Extend the knees until legs are straight.', 'Squeeze the quads for a second.', 'Lower slowly.'],
    breath: 'Exhale up.', posture: 'Hold the handles, hips down.', mistakes: ['Kicking with momentum'], safety: ['Lighter loads if you have kneecap pain'],
    sets: '3', reps: '12–15', rest: '60 s', alts: { none: 'sissy-squat', bands: 'wall-sit', dumbbells: 'goblet-squat' },
  },
  {
    id: 'goblet-squat', name: 'Goblet Squat', muscle: 'quads', secondary: ['Glutes', 'Core'],
    equip: 'dumbbells', gear: 'One dumbbell or kettlebell', type: 'strength', mech: 'compound', level: 1,
    start: 'Hold a dumbbell vertically against the chest, feet shoulder-width, toes slightly out.', steps: ['Squat down between the knees, elbows inside the knees.', 'Pause at the bottom.', 'Stand up through the whole foot.'],
    breath: 'Inhale down, exhale up.', posture: 'Upright torso, chest proud.', mistakes: ['Heels lifting', 'Knees caving'], safety: ['Great for learning the squat pattern'],
    sets: '3–4', reps: '10–15', rest: '90 s', alts: { none: 'bodyweight-squat' },
  },
  {
    id: 'bodyweight-squat', name: 'Bodyweight Squat', muscle: 'quads', secondary: ['Glutes'],
    equip: 'none', gear: 'None', type: 'bodyweight', mech: 'compound', level: 1,
    start: 'Feet shoulder-width, toes slightly out, arms out front for balance.', steps: ['Sit down and back to at least parallel.', 'Stand back up, squeezing the glutes at the top.', 'Add a 3-second descent or a pause to make it harder.'],
    breath: 'Inhale down, exhale up.', posture: 'Chest up, heels down.', mistakes: ['Knees collapsing inward', 'Rising onto toes'], safety: ['Use a chair behind you as a depth target'],
    sets: '3', reps: '15–25', rest: '60 s', alts: {},
  },
  {
    id: 'bulgarian-split-squat', name: 'Bulgarian Split Squat', muscle: 'quads', secondary: ['Glutes', 'Adductors'],
    equip: 'none', gear: 'Bench, chair or bed for the back foot (dumbbells optional)', type: 'strength', mech: 'compound', level: 2,
    start: 'Stand about two feet in front of a bench, place the top of the back foot on it.', steps: ['Lower straight down until the back knee nearly touches the floor.', 'Front knee tracks over toes.', 'Drive up through the front foot.'],
    breath: 'Inhale down, exhale up.', posture: 'Torso upright (more quads) or slight lean (more glutes).', mistakes: ['Front foot too close', 'Knee caving inward', 'Bouncing off the back leg'],
    safety: ['Hold a wall or chair for balance at first'], sets: '3', reps: '8–12 each', rest: '60–90 s', alts: {},
  },
  {
    id: 'sissy-squat', name: 'Bodyweight Sissy Squat (Assisted)', muscle: 'quads', secondary: ['Hip flexors'],
    equip: 'none', gear: 'Something to hold for balance', type: 'bodyweight', mech: 'isolation', level: 3,
    start: 'Stand holding a door frame or pole, feet hip-width, heels may rise.', steps: ['Push the knees forward and lean the body back in a straight line from knees to head.', 'Lower as far as comfortable.', 'Return by pushing the knees back.'],
    breath: 'Inhale down, exhale up.', posture: 'Hips stay extended (no sitting back).', mistakes: ['Sitting back into a normal squat', 'Going too deep too soon'],
    safety: ['Not appropriate for everyone — avoid with knee pain, patellar tendon issues or after knee surgery', 'Start with a very small range'], sets: '2–3', reps: '6–12', rest: '60–90 s', alts: {},
  },
  {
    id: 'walking-lunge', name: 'Walking Lunge', muscle: 'quads', secondary: ['Glutes', 'Hamstrings'],
    equip: 'none', gear: 'Space (dumbbells optional)', type: 'bodyweight', mech: 'compound', level: 1,
    start: 'Stand tall, feet hip-width.', steps: ['Step forward and lower until both knees are about 90°.', 'Push through the front foot and step through into the next lunge.'],
    breath: 'Inhale down, exhale up.', posture: 'Tall torso, front knee over the mid-foot.', mistakes: ['Short steps', 'Back knee slamming the floor'], safety: ['Clear walking path'],
    sets: '3', reps: '10–12 each leg', rest: '60–90 s', alts: {},
  },
  {
    id: 'step-up', name: 'Step-Up', muscle: 'quads', secondary: ['Glutes'],
    equip: 'none', gear: 'Sturdy step or bench', type: 'bodyweight', mech: 'compound', level: 1,
    start: 'Stand facing a knee-height step, one foot fully on it.', steps: ['Drive through the top foot to stand up on the step.', 'Lower slowly with the same leg.'],
    breath: 'Exhale up.', posture: 'Upright torso, push through the heel of the working leg.', mistakes: ['Pushing off the bottom leg'], safety: ['Stable surface only'],
    sets: '3', reps: '10–12 each', rest: '60 s', alts: {},
  },
  {
    id: 'wall-sit', name: 'Wall Sit', muscle: 'quads', secondary: ['Glutes'],
    equip: 'none', gear: 'Wall', type: 'bodyweight', mech: 'isolation', level: 1,
    start: 'Back against a wall, slide down until knees and hips are at 90°.', steps: ['Hold the position.', 'Push the lower back into the wall.'],
    breath: 'Keep breathing steadily.', posture: 'Knees over ankles.', mistakes: ['Knees ahead of the toes', 'Holding the breath'], safety: ['Raise higher if knees ache'],
    sets: '3', reps: '30–60 s', rest: '60 s', alts: {},
  },

  // ───────────── HAMSTRINGS ─────────────
  {
    id: 'romanian-deadlift', name: 'Barbell Romanian Deadlift', muscle: 'hamstrings', secondary: ['Glutes', 'Spinal erectors', 'Forearms'],
    equip: 'homegym', gear: 'Barbell', type: 'strength', mech: 'compound', level: 2,
    start: 'Stand tall holding the bar at the hips, overhand grip, soft knees.', steps: ['Push the hips back, sliding the bar down the thighs.', 'Lower until you feel a strong hamstring stretch (usually mid-shin).', 'Drive the hips forward to stand tall.'],
    breath: 'Inhale and brace as you lower; exhale at the top.', posture: 'Flat back, bar close to the legs, knee angle stays nearly fixed.', mistakes: ['Rounding the back', 'Squatting the weight down', 'Bar drifting forward'],
    safety: ['Range is set by your hamstring flexibility — not by touching the floor'], sets: '3–4', reps: '8–10', rest: '2 min',
    alts: { none: 'single-leg-rdl', bands: 'band-good-morning', dumbbells: 'db-rdl' },
  },
  {
    id: 'db-rdl', name: 'Dumbbell Romanian Deadlift', muscle: 'hamstrings', secondary: ['Glutes', 'Lower back'],
    equip: 'dumbbells', gear: 'Dumbbells', type: 'strength', mech: 'compound', level: 1,
    start: 'Stand holding dumbbells in front of the thighs.', steps: ['Hinge back keeping the dumbbells close to the legs.', 'Feel the hamstring stretch.', 'Stand tall, squeezing the glutes.'],
    breath: 'Inhale down, exhale up.', posture: 'Flat back, soft knees.', mistakes: ['Rounding'], safety: ['Light to start'],
    sets: '3', reps: '10–12', rest: '90 s', alts: { none: 'single-leg-rdl', bands: 'band-good-morning' },
  },
  {
    id: 'lying-leg-curl', name: 'Lying Leg Curl', muscle: 'hamstrings', secondary: ['Calves'],
    equip: 'gym', gear: 'Lying leg curl machine', type: 'strength', mech: 'isolation', level: 1,
    start: 'Lie face-down, pad just above the heels, knees just off the bench edge.', steps: ['Curl the heels toward the glutes.', 'Squeeze.', 'Lower slowly.'],
    breath: 'Exhale up.', posture: 'Hips pressed into the pad.', mistakes: ['Hips lifting', 'Jerking'], safety: ['Control the negative to avoid cramping'],
    sets: '3', reps: '10–15', rest: '60 s', alts: { none: 'sliding-leg-curl', bands: 'band-leg-curl', dumbbells: 'db-rdl' },
  },
  {
    id: 'seated-leg-curl', name: 'Seated Leg Curl', muscle: 'hamstrings', secondary: [],
    equip: 'gym', gear: 'Seated leg curl machine', type: 'strength', mech: 'isolation', level: 1,
    start: 'Sit with the knees aligned with the pivot, thigh pad locked down, legs straight.', steps: ['Curl the heels down and back.', 'Return slowly.'], breath: 'Exhale as you curl.',
    posture: 'Back against pad, lean forward slightly for more stretch.', mistakes: ['Partial reps'], safety: ['Lock the thigh pad securely'],
    sets: '3', reps: '10–15', rest: '60 s', alts: { none: 'sliding-leg-curl', bands: 'band-leg-curl', dumbbells: 'db-rdl' },
  },
  {
    id: 'nordic-curl', name: 'Nordic Hamstring Curl (Eccentric)', muscle: 'hamstrings', secondary: ['Glutes'],
    equip: 'none', gear: 'Partner or something heavy to hook the heels under; cushion for knees', type: 'bodyweight', mech: 'isolation', level: 3,
    start: 'Kneel on a cushion, heels anchored, body upright from knees to head.', steps: ['Lower the body forward as slowly as you can, keeping hips extended.', 'Catch yourself with the hands.', 'Push back up with the hands and repeat.'],
    breath: 'Breathe out slowly as you lower.', posture: 'Straight line knees-to-head; do not bend at the hips.', mistakes: ['Breaking at the hips', 'Dropping fast'], safety: ['Very demanding — start with 3–5 reps and expect soreness'],
    sets: '2–3', reps: '3–6', rest: '2 min', alts: {},
  },
  {
    id: 'single-leg-rdl', name: 'Single-Leg Romanian Deadlift (Bodyweight)', muscle: 'hamstrings', secondary: ['Glutes', 'Balance'],
    equip: 'none', gear: 'None (hold a bottle or dumbbell to progress)', type: 'bodyweight', mech: 'compound', level: 2,
    start: 'Stand on one leg, slight knee bend.', steps: ['Hinge forward, reaching the hands toward the floor as the free leg extends back.', 'Keep hips square.', 'Return to standing.'],
    breath: 'Inhale down, exhale up.', posture: 'Flat back; body moves like a seesaw.', mistakes: ['Hips opening/rotating', 'Rounding the back'], safety: ['Touch a wall for balance'],
    sets: '3', reps: '8–12 each', rest: '60 s', alts: {},
  },
  {
    id: 'sliding-leg-curl', name: 'Sliding Leg Curl (Towel)', muscle: 'hamstrings', secondary: ['Glutes'],
    equip: 'none', gear: 'Towel on a smooth floor or socks on tiles', type: 'bodyweight', mech: 'isolation', level: 2,
    start: 'Lie on the back, heels on a towel, knees bent, lift the hips into a bridge.', steps: ['Slide the heels out until legs are nearly straight, hips stay up.', 'Pull the heels back in.'],
    breath: 'Exhale as you curl in.', posture: 'Hips high throughout.', mistakes: ['Hips dropping'], safety: ['Do only the slide-out (eccentric) part if curling in is too hard'],
    sets: '3', reps: '8–12', rest: '60 s', alts: {},
  },
  {
    id: 'band-leg-curl', name: 'Resistance-Band Leg Curl', muscle: 'hamstrings', secondary: [],
    equip: 'bands', gear: 'Loop band anchored low', type: 'strength', mech: 'isolation', level: 1,
    start: 'Lie face-down with the band anchored low in front of you and looped around the ankles.', steps: ['Curl the heels toward the glutes.', 'Return slowly.'], breath: 'Exhale as you curl.',
    posture: 'Hips pressed into the floor.', mistakes: ['Lifting the hips'], safety: ['Secure anchor'], sets: '3', reps: '15–20', rest: '45 s', alts: { none: 'sliding-leg-curl' },
  },

  // ───────────── GLUTES ─────────────
  {
    id: 'hip-thrust', name: 'Barbell Hip Thrust', muscle: 'glutes', secondary: ['Hamstrings', 'Quads'],
    equip: 'homegym', gear: 'Barbell, bench, bar pad', type: 'strength', mech: 'compound', level: 2,
    start: 'Upper back against the bench edge, bar padded over the hip crease, feet flat about hip-width.', steps: ['Drive through the heels to lift the hips until the torso is parallel to the floor.', 'Squeeze the glutes hard at the top with chin tucked.', 'Lower under control.'],
    breath: 'Brace and exhale at the top.', posture: 'Ribs down, shins vertical at the top.', mistakes: ['Over-arching the lower back at the top', 'Feet too far forward (hamstring dominant)'], safety: ['Use a thick bar pad'],
    sets: '3–4', reps: '8–12', rest: '90 s', alts: { none: 'single-leg-glute-bridge', bands: 'band-lateral-walk', dumbbells: 'glute-bridge' },
  },
  {
    id: 'cable-kickback', name: 'Cable Glute Kickback', muscle: 'glutes', secondary: ['Hamstrings'],
    equip: 'gym', gear: 'Low cable with ankle strap', type: 'strength', mech: 'isolation', level: 1,
    start: 'Strap on the ankle, face the machine, slight forward lean holding the frame.', steps: ['Kick the leg back and slightly up, squeezing the glute.', 'Return slowly.'],
    breath: 'Exhale as you kick.', posture: 'No lower-back arching.', mistakes: ['Swinging', 'Arching the back to get height'], safety: ['Light weight'],
    sets: '3', reps: '12–15 each', rest: '45 s', alts: { none: 'single-leg-glute-bridge', bands: 'band-lateral-walk' },
  },
  {
    id: 'hip-abduction', name: 'Hip Abduction Machine', muscle: 'glutes', secondary: ['Glute medius'],
    equip: 'gym', gear: 'Abductor machine', type: 'strength', mech: 'isolation', level: 1,
    start: 'Sit with pads on the outside of the knees.', steps: ['Push the knees out.', 'Return slowly.'], breath: 'Exhale out.', posture: 'Tall or slight forward lean.',
    mistakes: ['Letting the stack slam'], safety: ['Control the return'], sets: '3', reps: '15–20', rest: '45 s', alts: { none: 'side-plank', bands: 'band-lateral-walk' },
  },
  {
    id: 'glute-bridge', name: 'Glute Bridge', muscle: 'glutes', secondary: ['Hamstrings'],
    equip: 'none', gear: 'Mat (dumbbell on hips to progress)', type: 'bodyweight', mech: 'isolation', level: 1,
    start: 'Lie on your back, knees bent, feet flat hip-width, arms by the sides.', steps: ['Drive through the heels to lift the hips.', 'Squeeze the glutes for 2 s at the top.', 'Lower slowly.'],
    breath: 'Exhale as you lift.', posture: 'Ribs down; straight line shoulders-hips-knees at the top.', mistakes: ['Arching the lower back', 'Pushing through the toes'], safety: ['Very joint-friendly'],
    sets: '3', reps: '15–20', rest: '45 s', alts: {},
  },
  {
    id: 'single-leg-glute-bridge', name: 'Single-Leg Glute Bridge', muscle: 'glutes', secondary: ['Hamstrings', 'Core'],
    equip: 'none', gear: 'Mat', type: 'bodyweight', mech: 'isolation', level: 2,
    start: 'Bridge position with one leg extended or knee pulled to the chest.', steps: ['Drive the hips up through the planted heel.', 'Keep the hips level.', 'Lower slowly.'],
    breath: 'Exhale as you lift.', posture: 'Hips square.', mistakes: ['Hip dropping on one side'], safety: ['Progress from the two-leg version'],
    sets: '3', reps: '10–15 each', rest: '45 s', alts: {},
  },
  {
    id: 'band-lateral-walk', name: 'Band Lateral Walk', muscle: 'glutes', secondary: ['Glute medius'],
    equip: 'bands', gear: 'Mini loop band', type: 'strength', mech: 'isolation', level: 1,
    start: 'Band above the knees or around the ankles, half-squat stance.', steps: ['Step sideways keeping tension on the band.', 'Do not let the feet come fully together.', 'Walk back the other way.'],
    breath: 'Breathe normally.', posture: 'Chest up, knees pushing out.', mistakes: ['Standing up tall', 'Knees caving'], safety: ['Great warm-up before squats'],
    sets: '3', reps: '12–15 steps each way', rest: '45 s', alts: { none: 'glute-bridge' },
  },

  // ───────────── CALVES ─────────────
  {
    id: 'standing-calf-raise', name: 'Standing Calf Raise (Machine)', muscle: 'calves', secondary: ['Soleus'],
    equip: 'gym', gear: 'Standing calf machine or Smith machine with step', type: 'strength', mech: 'isolation', level: 1,
    start: 'Balls of the feet on the platform edge, shoulders under the pads, knees straight but not locked.', steps: ['Lower the heels into a deep stretch and pause 1 s.', 'Rise as high as possible onto the toes, pause 1 s.'],
    breath: 'Exhale as you rise.', posture: 'Body tall and still.', mistakes: ['Bouncing', 'Tiny range'], safety: ['Pause at the bottom to protect the Achilles'],
    sets: '3–4', reps: '10–15', rest: '60 s', alts: { none: 'single-leg-calf-raise', bands: 'bodyweight-calf-raise', dumbbells: 'single-leg-calf-raise' },
  },
  {
    id: 'seated-calf-raise', name: 'Seated Calf Raise', muscle: 'calves', secondary: ['Soleus emphasis'],
    equip: 'gym', gear: 'Seated calf machine', type: 'strength', mech: 'isolation', level: 1,
    start: 'Sit with the pad on the lower thighs and the balls of the feet on the platform.', steps: ['Lower the heels fully.', 'Raise as high as possible.'], breath: 'Exhale up.',
    posture: 'Sit tall.', mistakes: ['Bouncing'], safety: ['Controlled tempo'], sets: '3', reps: '12–20', rest: '45–60 s',
    alts: { none: 'bodyweight-calf-raise', dumbbells: 'bodyweight-calf-raise' },
  },
  {
    id: 'bodyweight-calf-raise', name: 'Bodyweight Calf Raise', muscle: 'calves', secondary: [],
    equip: 'none', gear: 'Step or stair', type: 'bodyweight', mech: 'isolation', level: 1,
    start: 'Balls of both feet on a step, heels hanging off, hold a rail.', steps: ['Lower the heels below the step.', 'Rise up as high as possible and hold 1 s.'], breath: 'Exhale up.',
    posture: 'Tall, knees straight.', mistakes: ['Rushing'], safety: ['Hold the rail'], sets: '3', reps: '15–25', rest: '45 s', alts: {},
  },
  {
    id: 'single-leg-calf-raise', name: 'Single-Leg Calf Raise', muscle: 'calves', secondary: [],
    equip: 'none', gear: 'Step (dumbbell optional)', type: 'bodyweight', mech: 'isolation', level: 2,
    start: 'Ball of one foot on a step, other foot hooked behind.', steps: ['Lower into a deep stretch.', 'Rise as high as possible.'], breath: 'Exhale up.',
    posture: 'Tall; light hand support only.', mistakes: ['Bending the knee to cheat'], safety: ['Hold a rail'], sets: '3', reps: '10–15 each', rest: '45 s', alts: {},
  },

  // ───────────── FULL BODY ─────────────
  {
    id: 'burpee', name: 'Burpee', muscle: 'fullbody', secondary: ['Chest', 'Quads', 'Shoulders', 'Cardio'],
    equip: 'none', gear: 'None', type: 'plyometric', mech: 'compound', level: 2,
    start: 'Stand tall, feet shoulder-width.', steps: ['Squat down and place hands on the floor.', 'Jump or step the feet back into a plank.', 'Optional push-up.', 'Jump or step the feet back in, then jump up with arms overhead.'],
    breath: 'Breathe rhythmically; exhale on the jump.', posture: 'Solid plank with no sagging hips.', mistakes: ['Sagging plank', 'Landing stiff-legged'], safety: ['Step instead of jump for low-impact version'],
    sets: '3–5', reps: '8–15', rest: '60 s', alts: {},
  },
  {
    id: 'kettlebell-swing', name: 'Dumbbell / Kettlebell Swing', muscle: 'fullbody', secondary: ['Glutes', 'Hamstrings', 'Core', 'Shoulders'],
    equip: 'dumbbells', gear: 'Kettlebell or one dumbbell', type: 'strength', mech: 'compound', level: 2,
    start: 'Feet a little wider than hips, weight on the floor slightly in front.', steps: ['Hinge and hike the weight back between the legs.', 'Snap the hips forward to float the weight to chest height.', 'Let it fall back and hinge again.'],
    breath: 'Sharp exhale at the top of each swing.', posture: 'It is a hip hinge, not a squat; arms are just ropes.', mistakes: ['Squatting', 'Lifting with the arms', 'Leaning back at the top'], safety: ['Clear space around you', 'Learn the hinge first'],
    sets: '3–5', reps: '12–20', rest: '60–90 s', alts: { none: 'burpee' },
  },
  {
    id: 'db-thruster', name: 'Dumbbell Thruster', muscle: 'fullbody', secondary: ['Quads', 'Shoulders', 'Triceps', 'Glutes'],
    equip: 'dumbbells', gear: 'Dumbbells', type: 'strength', mech: 'compound', level: 2,
    start: 'Dumbbells at the shoulders, feet shoulder-width.', steps: ['Squat down.', 'Drive up and use the momentum to press the dumbbells overhead.', 'Lower back to the shoulders as you descend into the next squat.'],
    breath: 'Exhale on the press.', posture: 'Chest up, elbows forward in the squat.', mistakes: ['Pressing before the legs finish'], safety: ['Moderate weight'],
    sets: '3–4', reps: '10–12', rest: '90 s', alts: { none: 'burpee' },
  },
  {
    id: 'mountain-climber', name: 'Mountain Climber', muscle: 'fullbody', secondary: ['Core', 'Shoulders', 'Hip flexors', 'Cardio'],
    equip: 'none', gear: 'None', type: 'cardio', mech: 'compound', level: 1,
    start: 'High plank, hands under the shoulders.', steps: ['Drive one knee toward the chest.', 'Switch legs quickly, like running in place.'],
    breath: 'Rhythmic breathing.', posture: 'Hips level with shoulders.', mistakes: ['Hips bouncing high'], safety: ['Slow it down to keep good form'],
    sets: '3', reps: '20–40 s', rest: '30–45 s', alts: {},
  },
  {
    id: 'jumping-jack', name: 'Jumping Jack', muscle: 'fullbody', secondary: ['Calves', 'Shoulders', 'Cardio'],
    equip: 'none', gear: 'None', type: 'cardio', mech: 'compound', level: 1,
    start: 'Stand tall, feet together, arms at sides.', steps: ['Jump the feet out while raising the arms overhead.', 'Jump back to start.'], breath: 'Rhythmic.',
    posture: 'Light on the balls of the feet.', mistakes: ['Landing flat-footed'], safety: ['Step-jacks for low impact'], sets: '3', reps: '30–60 s', rest: '30 s', alts: {},
  },
  {
    id: 'rowing-machine', name: 'Rowing Machine (Erg)', muscle: 'fullbody', secondary: ['Back', 'Legs', 'Cardio'],
    equip: 'gym', gear: 'Rowing ergometer', type: 'cardio', mech: 'compound', level: 1,
    start: 'Strap feet in, sit tall, arms straight holding the handle, shins vertical.', steps: ['Drive with the legs first.', 'Then swing the torso back slightly.', 'Then pull the handle to the lower ribs.', 'Reverse: arms, body, legs.'],
    breath: 'Exhale on the drive, inhale on the recovery.', posture: 'Tall spine; do not hunch.', mistakes: ['Pulling with the arms first', 'Knees bending before the arms extend on the recovery'], safety: ['Damper setting 3–5 for most people'],
    sets: '1', reps: '10–20 min', rest: '—', alts: { none: 'burpee', dumbbells: 'kettlebell-swing' },
  },
];

export const EX_BY_ID: Record<string, Exercise> = Object.fromEntries(EXERCISES.map((e) => [e.id, e]));

/** Best home/alternative version for a given equipment level. */
export function alternativeFor(ex: Exercise, level: Equip): Exercise | null {
  if (EQUIP_RANK[ex.equip] <= EQUIP_RANK[level]) return null; // user can already do it
  const order: Equip[] = ['gym', 'homegym', 'dumbbells', 'bands', 'none'];
  for (const k of order) {
    if (EQUIP_RANK[k] > EQUIP_RANK[level]) continue;
    const id = ex.alts[k];
    if (id && EX_BY_ID[id]) return EX_BY_ID[id];
  }
  // fall back to any bodyweight option
  const id = ex.alts.none;
  return id ? EX_BY_ID[id] : null;
}
