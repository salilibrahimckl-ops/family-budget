// Evidence-based estimation formulas. These are population estimates, not medical measurements.
export type Sex = 'male' | 'female';
export type Activity = 'sedentary' | 'light' | 'moderate' | 'very' | 'extra';
export type Goal = 'muscle' | 'fatloss' | 'belly' | 'maintain' | 'strength' | 'general' | 'endurance' | 'recomp';

export const ACTIVITY: Record<Activity, { label: string; desc: string; mult: number }> = {
  sedentary: { label: 'Sedentary', desc: 'Desk job, little exercise', mult: 1.2 },
  light: { label: 'Lightly active', desc: 'Exercise 1–3 days/week', mult: 1.375 },
  moderate: { label: 'Moderately active', desc: 'Exercise 3–5 days/week', mult: 1.55 },
  very: { label: 'Very active', desc: 'Hard exercise 6–7 days/week', mult: 1.725 },
  extra: { label: 'Extremely active', desc: 'Physical job + daily training', mult: 1.9 },
};

export const GOALS: Record<Goal, { label: string; emoji: string; adj: number; protein: number; note: string }> = {
  muscle: { label: 'Muscle building', emoji: '💪', adj: 0.10, protein: 1.8, note: 'A modest ~10% surplus supports muscle gain while limiting fat gain.' },
  fatloss: { label: 'Fat loss', emoji: '🔥', adj: -0.20, protein: 2.0, note: 'A moderate ~20% deficit with high protein helps preserve muscle.' },
  belly: { label: 'Belly fat reduction', emoji: '🎯', adj: -0.20, protein: 2.0, note: 'Fat cannot be spot-reduced. Belly fat falls with overall fat loss, so this uses a moderate deficit, strength training and daily steps.' },
  maintain: { label: 'Weight maintenance', emoji: '⚖️', adj: 0, protein: 1.4, note: 'Calories near your estimated maintenance.' },
  strength: { label: 'Strength development', emoji: '🏋️', adj: 0.05, protein: 1.8, note: 'Slight surplus to fuel heavy training and recovery.' },
  general: { label: 'General fitness', emoji: '✨', adj: 0, protein: 1.4, note: 'Balanced intake around maintenance.' },
  endurance: { label: 'Endurance improvement', emoji: '🏃', adj: 0.05, protein: 1.5, note: 'Higher carbohydrate share to fuel longer sessions.' },
  recomp: { label: 'Body recomposition', emoji: '🔄', adj: -0.10, protein: 2.0, note: 'Small deficit, high protein and progressive strength training. Expect slow scale change while measurements improve.' },
};

export function bmi(weightKg: number, heightCm: number) {
  const m = heightCm / 100;
  return weightKg / (m * m);
}

/** WHO classes, plus the lower Asian-Indian cut-offs used in India (normal < 23). */
export function bmiClass(v: number, asian: boolean) {
  if (v < 18.5) return { label: 'Underweight', color: '#4FC3F7' };
  if (asian) {
    if (v < 23) return { label: 'Healthy range', color: '#B4F000' };
    if (v < 25) return { label: 'Overweight', color: '#FFB020' };
    return { label: 'Obese', color: '#FF5A36' };
  }
  if (v < 25) return { label: 'Healthy range', color: '#B4F000' };
  if (v < 30) return { label: 'Overweight', color: '#FFB020' };
  if (v < 35) return { label: 'Obesity class I', color: '#FF7A45' };
  if (v < 40) return { label: 'Obesity class II', color: '#FF5A36' };
  return { label: 'Obesity class III', color: '#E53935' };
}

export function healthyRange(heightCm: number, asian: boolean) {
  const m = heightCm / 100;
  return { min: 18.5 * m * m, max: (asian ? 22.9 : 24.9) * m * m, bmiMax: asian ? 22.9 : 24.9 };
}

/** Mifflin-St Jeor (1990). */
export function bmrMifflin(sex: Sex, kg: number, cm: number, age: number) {
  return 10 * kg + 6.25 * cm - 5 * age + (sex === 'male' ? 5 : -161);
}

export interface Targets {
  bmr: number; tdee: number; kcal: number; protein: number; carbs: number; fat: number; fibre: number; water: number;
  floorApplied: boolean; notes: string[];
}

export function targets(p: {
  sex: Sex; weight: number; height: number; age: number; activity: Activity; goal: Goal; trainingDays: number;
  hotClimate?: boolean; custom?: { kcal?: number; protein?: number; water?: number };
}): Targets {
  const notes: string[] = [];
  const bmr = bmrMifflin(p.sex, p.weight, p.height, p.age);
  const tdee = bmr * ACTIVITY[p.activity].mult;
  const g = GOALS[p.goal];
  let kcal = tdee * (1 + g.adj);
  const floor = p.sex === 'male' ? 1500 : 1200;
  let floorApplied = false;
  if (kcal < floor) { kcal = floor; floorApplied = true; notes.push(`Calories were held at ${floor} kcal — going lower without medical supervision is not recommended.`); }
  if (kcal < bmr && g.adj < 0) notes.push('Your target is close to your BMR. Prioritise protein, sleep and strength training.');

  // Protein on a reference weight if BMI ≥ 30 so targets stay realistic.
  const b = bmi(p.weight, p.height);
  const refWeight = b >= 30 ? 25 * (p.height / 100) ** 2 : p.weight;
  if (b >= 30) notes.push('Protein is based on a reference weight for your height (BMI 25), which is standard practice at higher body weights.');
  let protein = refWeight * g.protein;

  const fatPct = p.goal === 'endurance' ? 0.22 : 0.27;
  let fat = Math.max((kcal * fatPct) / 9, 0.6 * refWeight);

  if (p.custom?.kcal) kcal = p.custom.kcal;
  if (p.custom?.protein) protein = p.custom.protein;
  fat = Math.max((kcal * fatPct) / 9, 0.6 * refWeight);
  const carbs = Math.max(0, (kcal - protein * 4 - fat * 9) / 4);
  const fibre = (kcal / 1000) * 14; // Institute of Medicine: 14 g per 1000 kcal

  // Water: ~35 ml/kg baseline + ~500 ml on training days (averaged) + hot climate allowance. A guide only.
  let water = p.weight * 35 + (p.trainingDays / 7) * 500 + (p.hotClimate ? 500 : 0);
  water = Math.round(water / 50) * 50;
  if (p.custom?.water) water = p.custom.water;

  return { bmr, tdee, kcal: Math.round(kcal), protein: Math.round(protein), carbs: Math.round(carbs), fat: Math.round(fat), fibre: Math.round(fibre), water, floorApplied, notes };
}

/** Epley estimated one-rep max. */
export const e1rm = (w: number, r: number) => (r <= 1 ? w : w * (1 + r / 30));

export const ageFrom = (dob: string) => {
  const d = new Date(dob); const n = new Date();
  let a = n.getFullYear() - d.getFullYear();
  if (n.getMonth() < d.getMonth() || (n.getMonth() === d.getMonth() && n.getDate() < d.getDate())) a--;
  return a;
};

// Units
export const kgToLb = (kg: number) => kg * 2.20462;
export const lbToKg = (lb: number) => lb / 2.20462;
export const cmToFtIn = (cm: number) => { const inch = cm / 2.54; return { ft: Math.floor(inch / 12), inch: Math.round(inch % 12) }; };
export const mlToOz = (ml: number) => ml / 29.5735;
