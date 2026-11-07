// Pre-designed programmes. Each day lists exercise ids with prescribed sets/reps.
export interface ProgramDay { name: string; focus: string; items: { id: string; sets: number; reps: string }[] }
export interface Program {
  id: string; name: string; level: 'Beginner' | 'Intermediate' | 'Advanced'; days: ProgramDay[];
  perWeek: number; desc: string; goal: string; home?: boolean; premium?: boolean;
}

const d = (name: string, focus: string, items: [string, number, string][]): ProgramDay =>
  ({ name, focus, items: items.map(([id, sets, reps]) => ({ id, sets, reps })) });

export const PROGRAMS: Program[] = [
  {
    id: 'beginner-fb', name: 'Beginner Foundations', level: 'Beginner', perWeek: 3, goal: 'General fitness',
    desc: 'Three full-body sessions a week to learn the main movement patterns: squat, hinge, push, pull and core.',
    days: [
      d('Day A', 'Full body', [['goblet-squat', 3, '10–12'], ['db-floor-press', 3, '8–12'], ['db-row', 3, '10 each'], ['glute-bridge', 3, '15'], ['plank', 3, '30 s']]),
      d('Day B', 'Full body', [['db-rdl', 3, '10–12'], ['incline-push-up', 3, '10–15'], ['lat-pulldown', 3, '10–12'], ['walking-lunge', 2, '10 each'], ['dead-bug', 3, '8 each']]),
      d('Day C', 'Full body', [['leg-press', 3, '12'], ['db-shoulder-press', 3, '10'], ['seated-cable-row', 3, '12'], ['bodyweight-calf-raise', 3, '15'], ['side-plank', 2, '20 s each']]),
    ],
  },
  {
    id: 'ppl', name: 'Push / Pull / Legs', level: 'Intermediate', perWeek: 6, goal: 'Muscle building',
    desc: 'Classic hypertrophy split. Run it 3 days a week (once through) or 6 days (twice through).',
    days: [
      d('Push', 'Chest · Shoulders · Triceps', [['bench-press', 4, '6–8'], ['incline-db-press', 3, '8–12'], ['db-shoulder-press', 3, '8–10'], ['lateral-raise', 3, '12–15'], ['cable-pushdown', 3, '10–12'], ['overhead-db-extension', 2, '12']]),
      d('Pull', 'Back · Biceps · Rear delts', [['pull-up', 4, '6–10'], ['barbell-row', 3, '8'], ['seated-cable-row', 3, '10–12'], ['face-pull', 3, '15'], ['barbell-curl', 3, '10'], ['hammer-curl', 2, '12']]),
      d('Legs', 'Quads · Hamstrings · Glutes · Calves', [['back-squat', 4, '6–8'], ['romanian-deadlift', 3, '8–10'], ['leg-press', 3, '12'], ['lying-leg-curl', 3, '12'], ['hip-thrust', 3, '10'], ['standing-calf-raise', 4, '12']]),
    ],
  },
  {
    id: 'upper-lower', name: 'Upper / Lower Split', level: 'Intermediate', perWeek: 4, goal: 'Strength development',
    desc: 'Four days a week alternating upper and lower body — great balance of strength and size.',
    days: [
      d('Upper A', 'Strength focus', [['bench-press', 4, '5'], ['barbell-row', 4, '6'], ['ohp', 3, '6'], ['lat-pulldown', 3, '10'], ['skull-crusher', 2, '10'], ['barbell-curl', 2, '10']]),
      d('Lower A', 'Strength focus', [['back-squat', 4, '5'], ['romanian-deadlift', 3, '8'], ['walking-lunge', 2, '10 each'], ['standing-calf-raise', 3, '12'], ['hanging-leg-raise', 3, '10']]),
      d('Upper B', 'Volume focus', [['incline-db-press', 4, '10'], ['seated-cable-row', 4, '10'], ['lateral-raise', 3, '15'], ['chin-up', 3, '8'], ['cable-pushdown', 3, '12'], ['hammer-curl', 3, '12']]),
      d('Lower B', 'Volume focus', [['deadlift', 3, '5'], ['leg-press', 3, '12'], ['lying-leg-curl', 3, '12'], ['hip-thrust', 3, '10'], ['seated-calf-raise', 3, '15'], ['cable-crunch', 3, '12']]),
    ],
  },
  {
    id: 'full-body-3', name: 'Full Body Strength', level: 'Intermediate', perWeek: 3, goal: 'Body recomposition',
    desc: 'Three heavy-moderate full-body days. Efficient and ideal for recomposition.',
    days: [
      d('Day 1', 'Squat focus', [['back-squat', 4, '6'], ['bench-press', 3, '8'], ['barbell-row', 3, '8'], ['plank', 3, '45 s']]),
      d('Day 2', 'Hinge focus', [['deadlift', 3, '5'], ['ohp', 3, '8'], ['pull-up', 3, '6–8'], ['bulgarian-split-squat', 2, '10 each']]),
      d('Day 3', 'Volume', [['leg-press', 3, '12'], ['incline-db-press', 3, '10'], ['seated-cable-row', 3, '12'], ['hip-thrust', 3, '10'], ['russian-twist', 3, '12 each']]),
    ],
  },
  {
    id: 'home-bw', name: 'Home Workout — No Equipment', level: 'Beginner', perWeek: 4, goal: 'General fitness', home: true,
    desc: 'Four bodyweight sessions you can do in your living room. Progress by adding reps, slowing tempo or harder variations.',
    days: [
      d('Upper', 'Push & pull', [['push-up', 4, '8–15'], ['inverted-row', 4, '8–12'], ['pike-push-up', 3, '6–10'], ['bench-dip', 3, '10–15'], ['superman', 3, '12']]),
      d('Lower', 'Legs & glutes', [['bodyweight-squat', 4, '20'], ['bulgarian-split-squat', 3, '10 each'], ['single-leg-rdl', 3, '10 each'], ['glute-bridge', 3, '20'], ['single-leg-calf-raise', 3, '12 each']]),
      d('Core & conditioning', 'Core', [['mountain-climber', 4, '30 s'], ['plank', 3, '45 s'], ['side-plank', 3, '30 s each'], ['dead-bug', 3, '10 each'], ['bicycle-crunch', 3, '15 each']]),
      d('Full body circuit', 'Conditioning', [['burpee', 4, '10'], ['walking-lunge', 3, '12 each'], ['decline-push-up', 3, '10'], ['jumping-jack', 3, '45 s'], ['reverse-crunch', 3, '15']]),
    ],
  },
  {
    id: 'fat-loss', name: 'Fat-Loss Programme', level: 'Beginner', perWeek: 4, goal: 'Fat loss',
    desc: 'Strength training to keep muscle plus conditioning finishers. Pair with a moderate calorie deficit and daily steps.',
    days: [
      d('Strength A', 'Lower + push', [['goblet-squat', 4, '10'], ['db-floor-press', 3, '10'], ['walking-lunge', 3, '12 each'], ['kettlebell-swing', 4, '15'], ['plank', 3, '40 s']]),
      d('Strength B', 'Hinge + pull', [['db-rdl', 4, '10'], ['db-row', 3, '10 each'], ['db-shoulder-press', 3, '10'], ['mountain-climber', 4, '30 s'], ['side-plank', 3, '30 s each']]),
      d('Conditioning', 'Cardio circuit', [['burpee', 5, '10'], ['jumping-jack', 5, '40 s'], ['db-thruster', 4, '12'], ['bicycle-crunch', 3, '15 each']]),
      d('Strength C', 'Full body', [['leg-press', 3, '12'], ['lat-pulldown', 3, '12'], ['incline-db-press', 3, '10'], ['hip-thrust', 3, '12'], ['rowing-machine', 1, '10 min']]),
    ],
  },
  {
    id: 'muscle-building', name: 'Muscle-Building Programme', level: 'Advanced', perWeek: 5, goal: 'Muscle building', premium: true,
    desc: 'Five-day body-part emphasis with high volume for experienced lifters. Requires recovery, sleep and a calorie surplus.',
    days: [
      d('Chest & Triceps', 'Push', [['bench-press', 4, '6–8'], ['incline-db-press', 4, '8–10'], ['cable-fly', 3, '12–15'], ['chest-dip', 3, '8–12'], ['skull-crusher', 3, '10'], ['cable-pushdown', 3, '12']]),
      d('Back & Biceps', 'Pull', [['deadlift', 3, '5'], ['pull-up', 4, '8'], ['seated-cable-row', 3, '10'], ['lat-pulldown', 3, '12'], ['incline-db-curl', 3, '10'], ['preacher-curl', 3, '12']]),
      d('Legs', 'Quads focus', [['back-squat', 5, '6'], ['leg-press', 4, '10'], ['leg-extension', 3, '15'], ['walking-lunge', 3, '12 each'], ['standing-calf-raise', 4, '12']]),
      d('Shoulders & Abs', 'Delts', [['ohp', 4, '6–8'], ['lateral-raise', 4, '15'], ['cable-lateral-raise', 3, '15'], ['face-pull', 3, '15'], ['hanging-leg-raise', 3, '10'], ['cable-crunch', 3, '15']]),
      d('Posterior chain', 'Hamstrings & glutes', [['romanian-deadlift', 4, '8'], ['hip-thrust', 4, '10'], ['lying-leg-curl', 3, '12'], ['cable-kickback', 3, '15'], ['seated-calf-raise', 3, '15']]),
    ],
  },
];
