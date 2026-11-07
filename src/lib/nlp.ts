// Natural-language food entry parser: "I ate 3 eggs, 150 grams of chicken and 200 grams of rice".
// Runs on-device. Results are ESTIMATES and are shown for confirmation before logging.
import { Food } from '../data/foods';

export interface ParsedItem {
  text: string;
  food: Food | null;
  options: Food[];         // when ambiguous, user picks
  grams: number | null;
  qtyLabel: string;
  question?: string;       // clarification to ask
}

const NUM_WORDS: Record<string, number> = {
  a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  eleven: 11, twelve: 12, half: 0.5, quarter: 0.25, couple: 2, few: 3,
};
const UNITS: [RegExp, string, number | null][] = [
  [/^(kg|kgs|kilo|kilos|kilograms?)$/, 'g', 1000],
  [/^(g|gm|gms|gram|grams|gr)$/, 'g', 1],
  [/^(ml|millilitres?|milliliters?)$/, 'ml', 1],
  [/^(l|litre|litres|liter|liters)$/, 'ml', 1000],
  [/^(tbsp|tablespoons?)$/, 'serving:tbsp', null],
  [/^(tsp|teaspoons?)$/, 'serving:tsp', null],
  [/^(cups?)$/, 'serving:cup', null],
  [/^(bowls?)$/, 'serving:bowl', null],
  [/^(glass|glasses)$/, 'serving:glass', null],
  [/^(plates?)$/, 'serving:plate', null],
  [/^(scoops?)$/, 'serving:scoop', null],
  [/^(slices?)$/, 'serving:slice', null],
  [/^(pieces?|pcs?|nos?)$/, 'count', null],
  [/^(handfuls?)$/, 'serving:handful', null],
];

// Foods where the bare word is ambiguous about preparation.
const AMBIGUOUS: Record<string, string[]> = {
  chicken: ['chicken-breast', 'chicken-curry', 'chicken-thigh', 'chicken-biryani'],
  fish: ['fish-curry', 'fish-fry', 'fish-white', 'sardine'],
  beef: ['beef-fry', 'beef-lean'],
  rice: ['rice-white', 'rice-matta', 'rice-brown', 'rice-basmati'],
  milk: ['milk-toned', 'milk-full', 'milk-skim'],
  egg: ['egg', 'omelette', 'egg-roast'],
  eggs: ['egg', 'omelette', 'egg-roast'],
};
// For counts, which choice we default to without asking.
const COUNT_DEFAULT: Record<string, string> = { eggs: 'egg', egg: 'egg' };

function norm(s: string) { return s.toLowerCase().replace(/[^a-z0-9.,+&\s/-]/g, ' ').replace(/\s+/g, ' ').trim(); }

function score(food: Food, q: string) {
  const names = [food.name.toLowerCase(), ...(food.aliases || [])];
  let best = 0;
  for (const n of names) {
    if (n === q) best = Math.max(best, 100);
    else if (q.includes(n)) best = Math.max(best, 60 + n.length);
    else if (n.includes(q) && q.length > 2) best = Math.max(best, 40 + q.length);
  }
  return best;
}

export function searchFoods(foods: Food[], q: string, limit = 30) {
  const n = norm(q).replace(/[,+&]/g, ' ').trim();
  if (!n) return foods.slice(0, limit);
  return foods.map((f) => ({ f, s: score(f, n) + (f.name.toLowerCase().includes(n) ? 10 : 0) }))
    .filter((x) => x.s > 0).sort((a, b) => b.s - a.s).slice(0, limit).map((x) => x.f);
}

function servingGrams(food: Food, kind: string): number | null {
  const s = food.servings.find((x) => x.label.toLowerCase().includes(kind));
  return s ? s.g : null;
}

export function parseMeal(input: string, foods: Food[]): ParsedItem[] {
  const text = norm(input).replace(/^(i|i've|ive)\s+(had|ate|eaten|drank|have had)\s+/, '').replace(/\b(today|for breakfast|for lunch|for dinner|for snack|for snacks)\b/g, '');
  const parts = text.split(/,|\band\b|\bplus\b|\bwith\b|\+|&/).map((p) => p.trim()).filter(Boolean);
  const out: ParsedItem[] = [];
  for (const raw of parts) {
    const toks = raw.split(' ');
    let qty: number | null = null; let unit: string | null = null; let mult: number | null = null;
    let i = 0;
    // quantity
    const m = toks[0]?.match(/^(\d+(?:\.\d+)?)([a-z]+)?$/);
    if (m) { qty = parseFloat(m[1]); i = 1; if (m[2]) { const u = UNITS.find(([r]) => r.test(m[2])); if (u) { unit = u[1]; mult = u[2]; } } }
    else if (toks[0] && NUM_WORDS[toks[0]] !== undefined) { qty = NUM_WORDS[toks[0]]; i = 1; if (toks[1] === 'a' || toks[1] === 'an') i = 2; }
    if (!unit && toks[i]) { const u = UNITS.find(([r]) => r.test(toks[i])); if (u) { unit = u[1]; mult = u[2]; i++; } }
    if (toks[i] === 'of') i++;
    const name = toks.slice(i).join(' ').replace(/\b(boiled|cooked)\b/g, (w) => w).trim();
    if (!name) continue;

    // match
    const amb = AMBIGUOUS[name];
    let food: Food | null = null; let options: Food[] = [];
    let question: string | undefined;
    if (amb) {
      options = amb.map((id) => foods.find((f) => f.id === id)!).filter(Boolean);
      if (unit === 'count' || (!unit && qty !== null && COUNT_DEFAULT[name])) food = foods.find((f) => f.id === (COUNT_DEFAULT[name] || amb[0])) || null;
      if (!food) { food = options[0] || null; question = `How was the ${name} prepared? (assumed: ${food?.name})`; }
    } else {
      const found = searchFoods(foods, name, 4);
      food = found[0] || null; options = found;
      if (!food) question = `I couldn't find "${name}". Pick a food or add a custom entry.`;
    }

    let grams: number | null = null; let qtyLabel = '';
    if (food) {
      if (unit === 'g' || unit === 'ml') { grams = (qty ?? 1) * (mult ?? 1); qtyLabel = `${grams} ${food.unit || 'g'}`; }
      else if (unit && unit.startsWith('serving:')) {
        const kind = unit.split(':')[1]; const g = servingGrams(food, kind) ?? servingGrams(food, '');
        if (g) { grams = (qty ?? 1) * g; qtyLabel = `${qty ?? 1} ${kind}`; }
      } else if (qty !== null) {
        const g = food.servings[0]?.g; if (g) { grams = qty * g; qtyLabel = `${qty} × ${food.servings[0].label.replace(/^1\s*/, '')}`; }
      }
      if (grams === null && !question) question = `How much ${food.name.toLowerCase()}? (grams or servings)`;
    }
    out.push({ text: raw, food, options, grams, qtyLabel, question });
  }
  return out;
}
