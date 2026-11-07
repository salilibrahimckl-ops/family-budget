// AI Fitness Coach.
// 1) On-device coach: deterministic, uses the user's own data and the app's databases. Always available, offline.
// 2) Cloud LLM coach (optional): calls the Supabase Edge Function `coach`, which holds the AI API key server-side.
import { State, today } from './store';
import { targets, bmi, GOALS } from './calc';
import { EXERCISES, EX_BY_ID, alternativeFor, MUSCLES } from '../data/exercises';
import { PROGRAMS } from '../data/programs';
import { FOODS } from '../data/foods';

const RED_FLAGS = /(chest pain|faint|fainted|passing out|shortness of breath|numb|tingling|blood|pregnan|diabet|heart|blood pressure|kidney|eating disorder|starv|vomit|purg|steroid|sarm|dizz|injur|torn|fracture|sprain|surgery|sharp pain)/i;
const EXTREME = /(500 ?kcal|600 ?kcal|800 ?kcal|water fast|dry fast|only water|crash diet|lose \d+ ?kg in (a|one|1|2) week)/i;

export function dayTotals(s: State, date = today()) {
  const m = s.meals.filter((x) => x.date === date);
  return {
    kcal: m.reduce((a, x) => a + x.kcal, 0), p: m.reduce((a, x) => a + x.p, 0), c: m.reduce((a, x) => a + x.c, 0),
    f: m.reduce((a, x) => a + x.f, 0), fib: m.reduce((a, x) => a + x.fib, 0),
    water: s.water.filter((x) => x.date === date).reduce((a, x) => a + x.ml, 0),
  };
}

export function userTargets(s: State) {
  const p = s.profile!;
  return targets({ sex: p.sex, weight: p.weight, height: p.height, age: p.age, activity: p.activity, goal: p.goal, trainingDays: p.days, hotClimate: s.settings.hotClimate, custom: s.custom });
}

export function todaysPlan(s: State) {
  if (!s.plan) return null;
  const prog = PROGRAMS.find((x) => x.id === s.plan!.programId) || null;
  const idx = s.plan.schedule[new Date().getDay()];
  if (!prog || idx === null || idx === undefined) return { prog, day: null };
  return { prog, day: prog.days[idx % prog.days.length] };
}

const r = (n: number) => Math.round(n);

export function localCoach(s: State, q: string): string {
  const p = s.profile!; const t = userTargets(s); const tot = dayTotals(s); const ql = q.toLowerCase();
  const safety = RED_FLAGS.test(q) ? '\n\n⚠️ Because you mentioned symptoms, an injury or a medical condition: I can\'t diagnose anything. Please check with a doctor or physiotherapist before training through it. If you have chest pain, fainting or severe breathlessness, stop exercising and seek urgent medical care.' : '';
  if (EXTREME.test(q)) return `I won't recommend extreme or crash diets. Very low intakes cause muscle loss, fatigue, nutrient deficiencies and rebound weight gain. A sustainable target for you is about ${t.kcal} kcal/day with ${t.protein} g protein, losing roughly 0.5–1% of body weight per week. If you need faster medical weight loss, that should be supervised by a doctor or registered dietitian.`;

  // exercise alternative
  const altM = ql.match(/alternative (?:to|for) (.+?)[?.!]*$/) || ql.match(/(?:replace|instead of|substitute(?: for)?) (.+?)[?.!]*$/);
  if (altM) {
    const name = altM[1].trim();
    const ex = EXERCISES.find((e) => e.name.toLowerCase().includes(name) || e.id.replace(/-/g, ' ').includes(name));
    if (ex) {
      const opts = (['none', 'bands', 'dumbbells', 'homegym'] as const).map((k) => ex.alts[k] && EX_BY_ID[ex.alts[k]!] ? `• ${labelEq(k)}: ${EX_BY_ID[ex.alts[k]!].name}` : '').filter(Boolean);
      const mine = alternativeFor(ex, p.equipment);
      return `Alternatives to ${ex.name} (targets ${MUSCLES.find((m) => m.key === ex.muscle)?.name.toLowerCase()}):\n${opts.join('\n') || '• It already needs no special equipment.'}${mine ? `\n\nWith your equipment (${labelEq(p.equipment)}), I'd use **${mine.name}** — ${mine.sets} sets × ${mine.reps}.` : ''}` + safety;
    }
  }
  if (/upper chest/.test(ql)) return `Upper chest (clavicular pectoralis) responds best to incline pressing and low-to-high flys:\n• Incline Dumbbell Press (30–45°) — 3–4 × 8–12\n• Decline Push-Up (feet elevated) — home option\n• Low-to-high cable fly — 3 × 12–15\nKeep the bench at 30–45°; steeper turns it into a shoulder press.` + safety;
  if (/what should i (train|do)|train today|workout today|today'?s workout/.test(ql)) {
    const tp = todaysPlan(s);
    if (tp?.day) return `Today is **${tp.day.name}** (${tp.day.focus}) from your ${tp.prog!.name} plan:\n${tp.day.items.map((i) => `• ${EX_BY_ID[i.id]?.name} — ${i.sets} × ${i.reps}`).join('\n')}\n\nOpen Train → Start today's workout to log it.` + safety;
    const last = s.workouts[0];
    const recent = new Set(s.workouts.slice(0, 2).flatMap((w) => w.entries.map((e) => EX_BY_ID[e.exId]?.muscle)));
    const fresh = MUSCLES.filter((m) => m.key !== 'fullbody' && !recent.has(m.key)).slice(0, 3).map((m) => m.name);
    return `${tp ? 'Your plan has today as a rest day. Light walking or mobility is perfect.' : 'You have no weekly plan yet — pick one in Train → Programmes.'}\n\n${last ? `Your last session was "${last.name}". ` : ''}Muscles that are rested: ${fresh.join(', ')}. A good choice is a ${fresh.includes('Quadriceps') ? 'lower-body' : 'upper-body'} session of 4–6 exercises, 3 sets each, stopping 1–3 reps short of failure.` + safety;
  }
  if (/protein/.test(ql) && /(how much|need|enough|target)/.test(ql)) {
    return `Your protein target is **${t.protein} g/day** (${GOALS[p.goal].protein} g/kg${bmi(p.weight, p.height) >= 30 ? ' of reference weight' : ''} for ${GOALS[p.goal].label.toLowerCase()}). Today you've logged ${r(tot.p)} g — ${tot.p >= t.protein ? 'target reached 🎉' : `${r(t.protein - tot.p)} g to go`}.\nSpread it over 3–5 meals of 25–40 g. Easy Kerala-friendly sources: eggs, fish, chicken, curd/Greek yoghurt, paneer, kadala/cherupayar, soya chunks.` + safety;
  }
  if (/(calorie|kcal|eating enough|enough food|am i eating)/.test(ql)) {
    const diff = t.kcal - tot.kcal;
    return `Estimated BMR ${r(t.bmr)} kcal, TDEE ${r(t.tdee)} kcal (Mifflin-St Jeor). Your ${GOALS[p.goal].label.toLowerCase()} target is **${t.kcal} kcal**.\nLogged today: ${r(tot.kcal)} kcal (${diff > 0 ? `${r(diff)} kcal remaining` : `${r(-diff)} kcal over`}).\n${tot.kcal < t.bmr * 0.8 && new Date().getHours() > 19 ? 'You are well under target — eating too little repeatedly can cost muscle and energy.' : 'Judge by your weekly average weight trend, not a single day.'}` + safety;
  }
  if (/(body fat|lose fat|reduce fat|belly|tummy).*(muscle|keep|maintain)|(keep|maintain).*muscle/.test(ql) || /reduce body fat/.test(ql)) {
    return `To lose fat while keeping muscle:\n1. Moderate deficit — about ${userTargetsFor(s, 'fatloss').kcal} kcal/day for you (≈20% under maintenance).\n2. High protein — ~${userTargetsFor(s, 'fatloss').protein} g/day.\n3. Keep lifting heavy 3–4×/week; don't switch to only cardio.\n4. 7,000–10,000 steps daily.\n5. Sleep 7–9 h.\nAim to lose 0.5–1% of body weight per week. Spot reduction (e.g. only belly fat) isn't possible — fat comes off overall.` + safety;
  }
  if (/(dinner|lunch|breakfast|meal|snack).*(protein|healthy)|(protein|healthy).*(dinner|lunch|breakfast|meal|snack)/.test(ql)) {
    const veg = p.diet === 'vegetarian' || p.diet === 'vegan';
    const ideas = veg
      ? ['Paneer bhurji (150 g paneer) + 2 chapati + cucumber salad ≈ 35 g protein', 'Kadala curry + cherupayar thoran + matta rice (1 cup) ≈ 22 g protein', 'Soya chunk curry (40 g dry) + 2 chapati + curd ≈ 32 g protein']
      : p.diet === 'eggetarian' ? ['3-egg omelette with spinach + 2 chapati + curd ≈ 30 g protein', 'Egg roast (2 eggs) + appam (2) + green gram thoran ≈ 24 g protein', 'Paneer + egg bhurji wrap ≈ 32 g protein']
        : ['Grilled fish (150 g) + matta rice (1 cup) + cabbage thoran ≈ 40 g protein', 'Chicken breast curry (150 g chicken) + 2 chapati + salad ≈ 45 g protein', '3 egg-white + 1 egg omelette + puttu (½ piece) + kadala ≈ 30 g protein'];
    const remP = Math.max(0, t.protein - tot.p);
    return `High-protein ideas for you (${dietLabel(p.diet)}):\n${ideas.map((x) => '• ' + x).join('\n')}\n\nYou still need about ${r(remP)} g protein and ${r(Math.max(0, t.kcal - tot.kcal))} kcal today.${p.allergies.length ? `\nRemember to avoid: ${p.allergies.join(', ')}.` : ''}` + safety;
  }
  if (/(weekly|week) (plan|programme|program|workout|routine)|make (me )?a plan|plan for me/.test(ql)) return weeklyPlanText(s) + safety;
  if (/water|hydrat/.test(ql)) return `Your suggested water target is ${(t.water / 1000).toFixed(1)} L/day (≈35 ml/kg plus extra for training${s.settings.hotClimate ? ' and hot weather' : ''}). Logged today: ${(tot.water / 1000).toFixed(2)} L. This is a guide, not a medical requirement — thirst and pale-yellow urine are good practical checks. People with heart or kidney conditions should follow their doctor's fluid advice.`;
  if (/bmi/.test(ql)) { const b = bmi(p.weight, p.height); return `Your BMI is ${b.toFixed(1)}. BMI is a screening tool based only on height and weight — it doesn't measure body fat or muscle, so muscular people can read "overweight". Waist circumference and progress photos add useful context.`; }
  // exercise lookup
  const ex = EXERCISES.find((e) => ql.includes(e.name.toLowerCase().replace(/\(.+\)/, '').trim()));
  if (ex) return `**${ex.name}** — ${ex.mech}, ${['', 'beginner', 'intermediate', 'advanced'][ex.level]}.\nPrimary: ${MUSCLES.find((m) => m.key === ex.muscle)?.name}. Secondary: ${ex.secondary.join(', ') || '—'}.\nKey cues: ${ex.steps.slice(0, 2).join(' ')}\nAvoid: ${ex.mistakes.slice(0, 2).join('; ')}.\nPrescription: ${ex.sets} × ${ex.reps}, rest ${ex.rest}.` + safety;
  const food = FOODS.find((f) => (f.aliases || []).some((a) => a.length > 3 && ql.includes(a)));
  if (food) return `${food.name}: per 100 ${food.unit || 'g'} ≈ ${food.kcal} kcal, ${food.p} g protein, ${food.c} g carbs, ${food.f} g fat${food.estimate ? ' (home recipes vary — treat as an estimate)' : ''}. A typical serving (${food.servings[0].label}, ${food.servings[0].g} ${food.unit || 'g'}) ≈ ${r(food.kcal * food.servings[0].g / 100)} kcal.`;
  return `I can help with training, nutrition and progress using your data. Try:\n• What should I train today?\n• How much protein do I need?\n• Am I eating enough calories?\n• What is the alternative to leg press?\n• Make me a weekly plan\n• Suggest a healthy high-protein dinner` + safety;
}

function labelEq(k: string) { return ({ none: 'No equipment', bands: 'Bands', dumbbells: 'Dumbbells', homegym: 'Home gym', gym: 'Gym' } as any)[k]; }
function dietLabel(d: string) { return ({ nonveg: 'non-vegetarian', eggetarian: 'eggetarian', vegetarian: 'vegetarian', vegan: 'vegan', pescatarian: 'pescatarian' } as any)[d]; }
function userTargetsFor(s: State, goal: any) { const p = s.profile!; return targets({ sex: p.sex, weight: p.weight, height: p.height, age: p.age, activity: p.activity, goal, trainingDays: p.days }); }

export function recommendProgram(s: State) {
  const p = s.profile!;
  if (p.equipment === 'none' || p.equipment === 'bands') return PROGRAMS.find((x) => x.id === 'home-bw')!;
  if (p.goal === 'fatloss' || p.goal === 'belly') return PROGRAMS.find((x) => x.id === 'fat-loss')!;
  if (p.experience === 'beginner' || p.days <= 3) return PROGRAMS.find((x) => x.id === (p.experience === 'beginner' ? 'beginner-fb' : 'full-body-3'))!;
  if (p.days >= 5) return PROGRAMS.find((x) => x.id === (p.experience === 'advanced' ? 'muscle-building' : 'ppl'))!;
  return PROGRAMS.find((x) => x.id === 'upper-lower')!;
}

/** Spread programme days across the week based on how many days the user trains. */
export function buildSchedule(days: number, progDays: number): (number | null)[] {
  const patterns: Record<number, number[]> = { 1: [3], 2: [1, 4], 3: [1, 3, 5], 4: [1, 2, 4, 5], 5: [1, 2, 3, 5, 6], 6: [1, 2, 3, 4, 5, 6], 7: [0, 1, 2, 3, 4, 5, 6] };
  const sched: (number | null)[] = [null, null, null, null, null, null, null];
  (patterns[Math.min(7, Math.max(1, days))] || patterns[3]).forEach((wd, i) => { sched[wd] = i % progDays; });
  return sched;
}

export function weeklyPlanText(s: State) {
  const prog = recommendProgram(s); const p = s.profile!;
  const sched = buildSchedule(p.days, prog.days.length);
  const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const lines = sched.map((d, i) => `${names[i]}: ${d === null ? 'Rest / walk' : prog.days[d].name + ' — ' + prog.days[d].focus}`);
  return `Based on your goal (${GOALS[p.goal].label}), experience (${p.experience}), ${p.days} days/week and equipment, I recommend **${prog.name}**:\n${lines.join('\n')}\n\nProgression: when you hit the top of the rep range on every set, add 2.5–5% load next session. Deload every 6–8 weeks. Tap "Apply plan" in Train to put this on your calendar.`;
}

export async function cloudCoach(s: State, q: string): Promise<string> {
  const url = s.settings.supabaseUrl.replace(/\/$/, '');
  if (!url || !s.session?.token) throw new Error('Cloud coach needs Supabase configured and you signed in with a cloud account.');
  const p = s.profile!; const t = userTargets(s); const tot = dayTotals(s);
  const context = { goal: p.goal, sex: p.sex, age: p.age, height: p.height, weight: p.weight, target: p.targetWeight, bmi: +bmi(p.weight, p.height).toFixed(1), experience: p.experience, equipment: p.equipment, diet: p.diet, allergies: p.allergies, targets: t, today: tot, lastWorkouts: s.workouts.slice(0, 5).map((w) => ({ name: w.name, date: w.date, volume: w.volume })) };
  const res = await fetch(`${url}/functions/v1/coach`, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: s.settings.supabaseAnon, Authorization: `Bearer ${s.session.token}` }, body: JSON.stringify({ question: q, context, history: s.coach.slice(-8) }) });
  if (!res.ok) throw new Error(`Coach service error (${res.status})`);
  const j = await res.json();
  return j.answer as string;
}
