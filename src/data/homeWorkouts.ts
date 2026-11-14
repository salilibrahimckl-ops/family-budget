// Ready-made workouts that need no equipment. Shown first for anyone who trains at home.
import { EX_BY_ID } from './exercises';

export interface QuickWorkout { id: string; name: string; emoji: string; minutes: number; level: string; focus: string; items: { id: string; sets: number; reps: string }[] }
const w = (id: string, name: string, emoji: string, minutes: number, level: string, focus: string, items: [string, number, string][]): QuickWorkout =>
  ({ id, name, emoji, minutes, level, focus, items: items.filter(([x]) => EX_BY_ID[x]).map(([x, sets, reps]) => ({ id: x, sets, reps })) });

export const QUICK: QuickWorkout[] = [
  w('q10', '10-minute wake-up', '⚡', 10, 'Easy', 'Full body', [['jumping-jack', 2, '40 s'], ['bodyweight-squat', 2, '15'], ['push-up', 2, '8–10'], ['glute-bridge', 2, '15'], ['plank', 2, '30 s']]),
  w('fb20', 'Full body burn', '🔥', 20, 'Medium', 'Full body', [['burpee', 3, '8'], ['bodyweight-squat', 3, '20'], ['push-up', 3, '10–12'], ['walking-lunge', 3, '10 each'], ['mountain-climber', 3, '30 s'], ['plank', 3, '40 s']]),
  w('abs15', 'Abs & core', '🧱', 15, 'Medium', 'Core', [['dead-bug', 3, '10 each'], ['bicycle-crunch', 3, '15 each'], ['reverse-crunch', 3, '12'], ['side-plank', 2, '30 s each'], ['plank', 3, '45 s']]),
  w('up20', 'Chest, shoulders & arms', '💪', 20, 'Medium', 'Upper body', [['push-up', 4, '10–15'], ['pike-push-up', 3, '6–10'], ['bench-dip', 3, '10–15'], ['decline-push-up', 3, '8–12'], ['superman', 3, '12']]),
  w('legs20', 'Legs & glutes', '🦵', 20, 'Medium', 'Lower body', [['bodyweight-squat', 4, '20'], ['walking-lunge', 3, '12 each'], ['bulgarian-split-squat', 3, '10 each'], ['glute-bridge', 3, '20'], ['single-leg-calf-raise', 3, '12 each']]),
  w('hiit15', 'Fat-burn cardio', '🏃', 15, 'Hard', 'Cardio', [['jumping-jack', 4, '45 s'], ['burpee', 4, '10'], ['mountain-climber', 4, '30 s'], ['bodyweight-squat', 4, '20 fast']]),
];

/** Today's suggested home workout (rotates through the week). */
export function homeWorkoutFor(date = new Date()): QuickWorkout {
  const order = ['q10', 'fb20', 'abs15', 'up20', 'legs20', 'fb20', 'hiit15']; // Sun..Sat
  return QUICK.find((q) => q.id === order[date.getDay()])!;
}
