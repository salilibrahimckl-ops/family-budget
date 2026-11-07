import { useStore } from '../lib/store';
import { kgToLb, lbToKg, mlToOz, cmToFtIn } from '../lib/calc';
import { EXERCISES, EX_BY_ID, Exercise } from '../data/exercises';
import { FOODS, Food } from '../data/foods';
import { State } from '../lib/store';

export function useUnits() {
  const imp = useStore((s) => s.settings.units === 'imperial');
  return {
    imp,
    w: (kg: number, d = 1) => imp ? `${kgToLb(kg).toFixed(d)} lb` : `${kg.toFixed(d)} kg`,
    wNum: (kg: number) => imp ? +kgToLb(kg).toFixed(1) : +kg.toFixed(1),
    wIn: (v: number) => imp ? lbToKg(v) : v,
    wU: imp ? 'lb' : 'kg',
    h: (cm: number) => { if (!imp) return `${Math.round(cm)} cm`; const { ft, inch } = cmToFtIn(cm); return `${ft}′${inch}″`; },
    len: (cm: number) => imp ? `${(cm / 2.54).toFixed(1)} in` : `${cm.toFixed(1)} cm`,
    lenNum: (cm: number) => imp ? +(cm / 2.54).toFixed(1) : +cm.toFixed(1),
    lenIn: (v: number) => imp ? v * 2.54 : v,
    lenU: imp ? 'in' : 'cm',
    ml: (ml: number) => imp ? `${Math.round(mlToOz(ml))} fl oz` : ml >= 1000 ? `${(ml / 1000).toFixed(2)} L` : `${Math.round(ml)} ml`,
  };
}

/** Exercise library merged with admin edits (no app release needed). */
export function allExercises(s: State): Exercise[] {
  return [...EXERCISES, ...s.extraExercises].map((e) => (s.exOverrides[e.id] ? { ...e, ...s.exOverrides[e.id] } : e));
}
export function exById(s: State, id: string): Exercise | undefined {
  const e = EX_BY_ID[id] || s.extraExercises.find((x) => x.id === id);
  return e && s.exOverrides[id] ? { ...e, ...s.exOverrides[id] } : e;
}
export function allFoods(s: State): Food[] {
  return [...FOODS.map((f) => (s.foodOverrides[f.id] ? { ...f, ...s.foodOverrides[f.id] } : f)), ...s.customFoods];
}
export const LEVEL = ['', 'Beginner', 'Intermediate', 'Advanced'];
