import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useStore, update, uid, today, dayOffset, MealSlot, MealEntry, State } from '../lib/store';
import { dayTotals, userTargets } from '../lib/coach';
import { Food, macrosFor, FOOD_CATS } from '../data/foods';
import { parseMeal, searchFoods, ParsedItem } from '../lib/nlp';
import { Header, BackBtn, Card, Btn, Chip, Seg, Icon, Pill, Sheet, Empty, go, back, useRoute, Ring, Bar, Bars, LineChart, Field, NumIn, fmt, Toggle } from '../ui';
import { allFoods, useUnits } from './common';
import { bmi, bmiClass, healthyRange, GOALS, ACTIVITY } from '../lib/calc';
import { toast, haptic, checkAchievements, streak, scheduleWaterReminders } from '../lib/extras';

const SLOTS: { k: MealSlot; l: string; e: string }[] = [{ k: 'breakfast', l: 'Breakfast', e: '🌅' }, { k: 'lunch', l: 'Lunch', e: '🍛' }, { k: 'dinner', l: 'Dinner', e: '🌙' }, { k: 'snacks', l: 'Snacks', e: '🍌' }];
const defaultSlot = (): MealSlot => { const h = new Date().getHours(); return h < 11 ? 'breakfast' : h < 16 ? 'lunch' : h < 18 ? 'snacks' : 'dinner'; };

export function logFood(food: Food, grams: number, slot: MealSlot, date = today(), estimated = false) {
  const m = macrosFor(food, grams);
  update((d) => { d.meals.push({ id: uid(), date, slot, foodId: food.id, name: food.name, grams, unit: food.unit || 'g', kcal: m.kcal, p: m.p, c: m.c, f: m.f, fib: m.fib, estimated: estimated || !!food.estimate }); });
  checkAchievements();
}

export function Nutrition() {
  const s = useStore((x) => x);
  const [date, setDate] = useState(today());
  const tg = userTargets(s); const tot = dayTotals(s, date);
  const meals = s.meals.filter((m) => m.date === date);
  const [edit, setEdit] = useState<MealEntry | null>(null);
  const week = Array.from({ length: 7 }, (_, i) => { const d = dayOffset(i - 6); return { x: new Date(d + 'T00:00').toLocaleDateString('en-IN', { weekday: 'narrow' }), y: dayTotals(s, d).kcal }; });
  return (
    <div className="page">
      <Header big title="Nutrition" right={<button className="icon-btn" onClick={() => go('/targets')} aria-label="Targets"><Icon n="gear" /></button>} />
      <div className="date-nav">
        <button onClick={() => setDate(shift(date, -1))}><Icon n="back" s={18} /></button>
        <b>{date === today() ? 'Today' : date === dayOffset(-1) ? 'Yesterday' : fmt.date(date)}</b>
        <button disabled={date >= today()} onClick={() => setDate(shift(date, 1))}><Icon n="chev" s={18} /></button>
      </div>
      <Card className="nut-rings">
        <Ring value={tot.kcal} max={tg.kcal} size={132} stroke={13}><b className="ring-big">{fmt.n(tot.kcal)}</b><small>of {fmt.n(tg.kcal)} kcal</small></Ring>
        <div className="mini-rings">
          <MiniRing l="Protein" v={tot.p} m={tg.protein} c="var(--lime)" />
          <MiniRing l="Carbs" v={tot.c} m={tg.carbs} c="var(--sky)" />
          <MiniRing l="Fat" v={tot.f} m={tg.fat} c="var(--amber)" />
          <MiniRing l="Fibre" v={tot.fib} m={tg.fibre} c="var(--violet)" />
        </div>
      </Card>
      <Card className="nl-card" onClick={() => go(`/food/add?slot=${defaultSlot()}&date=${date}&mode=text`)}>
        <Icon n="spark" /><div><b>Describe what you ate</b><small>"3 eggs, 150 g chicken and 200 g rice"</small></div><Icon n="chev" s={18} />
      </Card>
      {SLOTS.map((sl) => { const items = meals.filter((m) => m.slot === sl.k); const kc = items.reduce((a, x) => a + x.kcal, 0);
        return (
          <Card key={sl.k} className="meal">
            <div className="row-b"><b>{sl.e} {sl.l}</b><span className="muted small">{fmt.n(kc)} kcal</span></div>
            {items.map((m) => (
              <button key={m.id} className="meal-item" onClick={() => setEdit(m)}>
                <div><span>{m.name}{m.estimated && <em className="est">est.</em>}</span><small>{fmt.n(m.grams)} {m.unit} · P {fmt.n(m.p)} · C {fmt.n(m.c)} · F {fmt.n(m.f)}</small></div><b>{fmt.n(m.kcal)}</b>
              </button>
            ))}
            <button className="add-food" onClick={() => go(`/food/add?slot=${sl.k}&date=${date}`)}><Icon n="plus" s={16} /> Add food</button>
          </Card>
        ); })}
      <Card>
        <div className="row-b"><span className="lbl">Calories — last 7 days</span><span className="muted small">target {fmt.n(tg.kcal)}</span></div>
        <Bars data={week} goal={tg.kcal} height={110} fmt={(v) => (v / 1000).toFixed(1) + 'k'} />
      </Card>
      <div className="grid2">
        <Card onClick={() => go('/water')} className="coach-card"><Icon n="drop" /><b>Water</b><small>{(tot.water / 1000).toFixed(2)} / {(tg.water / 1000).toFixed(1)} L</small></Card>
        <Card onClick={() => go('/body')} className="chal-card"><Icon n="scale" /><b>Body & BMI</b><small>Weight, BMI, measurements</small></Card>
      </div>
      <p className="muted small pad">Nutrition values are estimates from IFCT 2017 (NIN) and USDA averages. Home-cooked dishes marked "est." vary with recipe and oil.</p>
      <EditMeal m={edit} onClose={() => setEdit(null)} />
    </div>
  );
}
const shift = (d: string, n: number) => { const x = new Date(d + 'T00:00'); x.setDate(x.getDate() + n); return today(x); };
function MiniRing({ l, v, m, c }: { l: string; v: number; m: number; c: string }) {
  return <div className="mr"><Ring value={v} max={m} size={58} stroke={7} color={c}><b>{Math.round(v)}</b></Ring><small>{l}</small><em>/{m} g</em></div>;
}
function EditMeal({ m, onClose }: { m: MealEntry | null; onClose: () => void }) {
  const st = useStore((s) => s); const foods = allFoods(st);
  const [g, setG] = useState(m?.grams || 100);
  const [slot, setSlot] = useState<MealSlot>(m?.slot || 'lunch');
  useEffect(() => { if (m) { setG(m.grams); setSlot(m.slot); } }, [m]);
  if (!m) return null;
  const food = foods.find((f) => f.id === m.foodId);
  const mm = food ? macrosFor(food, g) : { kcal: m.kcal, p: m.p, c: m.c, f: m.f, fib: m.fib };
  return <Sheet open onClose={onClose} title={m.name}>
    <Field label={`Amount (${m.unit})`}><NumIn value={g} step={10} onChange={setG} suffix={m.unit} /></Field>
    <Seg value={slot} onChange={setSlot} options={SLOTS.map((x) => ({ v: x.k, l: x.l }))} />
    <MacroRow m={mm} />
    <div className="row"><Btn kind="danger" onClick={() => { update((d) => { d.meals = d.meals.filter((x) => x.id !== m.id); }); onClose(); }}>Delete</Btn>
      <Btn full onClick={() => { update((d) => { const x = d.meals.find((q) => q.id === m.id)!; Object.assign(x, { grams: g, slot, kcal: mm.kcal, p: mm.p, c: mm.c, f: mm.f, fib: mm.fib }); }); onClose(); }}>Save</Btn></div>
  </Sheet>;
}
function MacroRow({ m }: { m: { kcal: number; p: number; c: number; f: number; fib: number } }) {
  return <div className="macro-row"><div><b>{fmt.n(m.kcal)}</b><small>kcal</small></div><div><b>{fmt.n(m.p, 1)}</b><small>protein g</small></div><div><b>{fmt.n(m.c, 1)}</b><small>carbs g</small></div><div><b>{fmt.n(m.f, 1)}</b><small>fat g</small></div><div><b>{fmt.n(m.fib, 1)}</b><small>fibre g</small></div></div>;
}

// ─────────── Add food ───────────
export function AddFood() {
  const { q } = useRoute();
  const slot0 = (q.get('slot') as MealSlot) || defaultSlot(); const date = q.get('date') || today();
  const s = useStore((x) => x); const foods = allFoods(s);
  const [mode, setMode] = useState<'search' | 'text' | 'fav' | 'custom' | 'scan'>((q.get('mode') as any) || 'search');
  const [slot, setSlot] = useState<MealSlot>(slot0);
  const [qq, setQq] = useState(''); const [cat, setCat] = useState('');
  const [sel, setSel] = useState<Food | null>(null);
  const recent = useMemo(() => { const ids: string[] = []; for (let i = s.meals.length - 1; i >= 0 && ids.length < 8; i--) if (!ids.includes(s.meals[i].foodId)) ids.push(s.meals[i].foodId); return ids.map((id) => foods.find((f) => f.id === id)).filter(Boolean) as Food[]; }, [s.meals]);
  const results = qq ? searchFoods(foods, qq, 40) : cat ? foods.filter((f) => f.cat === cat) : [];
  return (
    <div className="page">
      <Header left={<BackBtn />} title="Add food" sub={fmt.date(date)} />
      <Seg value={slot} onChange={setSlot} options={SLOTS.map((x) => ({ v: x.k, l: x.l }))} />
      <div className="chips scroll" style={{ marginTop: 10 }}>
        <Chip on={mode === 'search'} onClick={() => setMode('search')}>🔎 Search</Chip><Chip on={mode === 'text'} onClick={() => setMode('text')}>✨ Describe</Chip>
        <Chip on={mode === 'scan'} onClick={() => setMode('scan')}>▥ Barcode</Chip><Chip on={mode === 'fav'} onClick={() => setMode('fav')}>★ Saved meals</Chip><Chip on={mode === 'custom'} onClick={() => setMode('custom')}>+ Custom food</Chip>
      </div>
      {mode === 'search' && <>
        <div className="search"><Icon n="search" s={18} /><input autoFocus placeholder="Search rice, puttu, chicken, dosa…" value={qq} onChange={(e) => setQq(e.target.value)} /></div>
        {!qq && <div className="chips scroll">{FOOD_CATS.map((c) => <Chip key={c} on={cat === c} onClick={() => setCat(cat === c ? '' : c)}>{c}</Chip>)}</div>}
        {!qq && !cat && recent.length > 0 && <><h4 className="sec-h">Recent</h4>{recent.map((f) => <FoodRow key={f.id} f={f} onClick={() => setSel(f)} />)}</>}
        {results.map((f) => <FoodRow key={f.id} f={f} onClick={() => setSel(f)} />)}
        {qq && !results.length && <Empty icon="food" title={`No match for "${qq}"`} action={<Btn kind="soft" onClick={() => setMode('custom')}>Create custom food</Btn>} />}
        {!qq && !cat && !recent.length && <p className="muted small pad">Pick a category above or type to search {foods.length} foods, including Kerala dishes.</p>}
      </>}
      {mode === 'text' && <TextEntry foods={foods} slot={slot} date={date} />}
      {mode === 'fav' && <Favourites slot={slot} date={date} />}
      {mode === 'custom' && <CustomFood onSaved={(f) => { setSel(f); setMode('search'); }} />}
      {mode === 'scan' && <BarcodeScan onFound={(f) => setSel(f)} />}
      <FoodSheet food={sel} slot={slot} date={date} onClose={() => setSel(null)} />
    </div>
  );
}
function FoodRow({ f, onClick }: { f: Food; onClick: () => void }) {
  return <Card className="food-row" onClick={onClick}><div><b>{f.name}{f.estimate && <em className="est">est.</em>}{f.custom && <em className="est">custom</em>}</b><small>{f.servings[0].label} · {Math.round(f.kcal * f.servings[0].g / 100)} kcal · P {Math.round(f.p * f.servings[0].g / 10) / 10} g</small></div><Icon n="plus" s={18} /></Card>;
}
function FoodSheet({ food, slot, date, onClose }: { food: Food | null; slot: MealSlot; date: string; onClose: () => void }) {
  const [g, setG] = useState(100); const [sv, setSv] = useState(0); const [count, setCount] = useState(1);
  const [byGrams, setByGrams] = useState(false);
  useEffect(() => { if (food) { setSv(0); setCount(1); setG(food.servings[0].g); setByGrams(false); } }, [food]);
  if (!food) return null;
  const grams = byGrams ? g : food.servings[sv].g * count;
  const m = macrosFor(food, grams);
  return <Sheet open onClose={onClose} title={food.name}>
    <Seg value={byGrams ? 'g' : 's'} onChange={(v) => setByGrams(v === 'g')} options={[{ v: 's', l: 'Servings' }, { v: 'g', l: food.unit === 'ml' ? 'Millilitres' : 'Grams' }]} />
    {byGrams ? <Field label={`Amount (${food.unit || 'g'})`}><NumIn value={g} step={10} onChange={setG} suffix={food.unit || 'g'} /></Field>
      : <><div className="chips">{food.servings.map((x, i) => <Chip key={i} on={sv === i} onClick={() => setSv(i)}>{x.label} ({x.g} {food.unit || 'g'})</Chip>)}</div>
        <Field label="Number of servings"><NumIn value={count} step={0.5} onChange={setCount} /></Field></>}
    <MacroRow m={m} />
    <div className="per100">Per 100 {food.unit || 'g'}: {food.kcal} kcal · P {food.p} · C {food.c} · F {food.f} · Fibre {food.fib}</div>
    {food.estimate && <p className="muted small">⚠️ Estimated value — recipes vary (oil, coconut, portion).</p>}
    <Btn full onClick={() => { logFood(food, grams, slot, date); haptic(); toast(`Added ${food.name}`); onClose(); }}>Add to {slot}</Btn>
  </Sheet>;
}

function TextEntry({ foods, slot, date }: { foods: Food[]; slot: MealSlot; date: string }) {
  const [text, setText] = useState(''); const [items, setItems] = useState<ParsedItem[] | null>(null);
  const [listening, setListening] = useState(false);
  const rec = useRef<any>(null);
  function parse() { setItems(parseMeal(text, foods)); }
  function voice() {
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SR) return toast('Voice input is not available on this device — type instead.');
    const r = new SR(); r.lang = 'en-IN'; r.onresult = (e: any) => { setText(e.results[0][0].transcript); setListening(false); }; r.onerror = () => setListening(false); r.onend = () => setListening(false);
    rec.current = r; r.start(); setListening(true);
  }
  const ready = items?.filter((i) => i.food && i.grams) || [];
  const total = ready.reduce((a, i) => { const m = macrosFor(i.food!, i.grams!); return { kcal: a.kcal + m.kcal, p: a.p + m.p, c: a.c + m.c, f: a.f + m.f, fib: a.fib + m.fib }; }, { kcal: 0, p: 0, c: 0, f: 0, fib: 0 });
  return <>
    <Card>
      <textarea className="nl-input" rows={3} value={text} onChange={(e) => setText(e.target.value)} placeholder="I ate 3 eggs, 150 grams of chicken and 200 grams of rice" />
      <div className="row"><Btn kind="soft" icon="mic" onClick={voice}>{listening ? 'Listening…' : 'Speak'}</Btn><Btn full disabled={!text.trim()} onClick={parse} icon="spark">Estimate nutrition</Btn></div>
    </Card>
    {items && <>
      {items.map((it, i) => (
        <Card key={i} className={'nl-item' + (it.question ? ' ask' : '')}>
          <small className="muted">“{it.text}”</small>
          {it.question && <p className="ask-q">❓ {it.question}</p>}
          {it.options.length > 1 && <div className="chips">{it.options.map((o) => <Chip key={o.id} on={it.food?.id === o.id} onClick={() => setItems(items.map((x, k) => k === i ? { ...x, food: o, grams: x.grams ?? o.servings[0].g, question: undefined } : x))}>{o.name}</Chip>)}</div>}
          {it.food && <div className="row-b"><b>{it.food.name}</b>
            <NumIn value={it.grams || 0} step={10} suffix={it.food.unit || 'g'} onChange={(v) => setItems(items.map((x, k) => k === i ? { ...x, grams: v, question: x.question?.startsWith('How much') ? undefined : x.question } : x))} /></div>}
          {it.food && it.grams ? <small className="muted">≈ {fmt.n(macrosFor(it.food, it.grams).kcal)} kcal · P {fmt.n(macrosFor(it.food, it.grams).p, 1)} g {it.qtyLabel && `(${it.qtyLabel})`}</small> : null}
          <button className="link muted" onClick={() => setItems(items.filter((_, k) => k !== i))}>Remove</button>
        </Card>
      ))}
      {ready.length > 0 && <Card className="nl-total"><span className="lbl">Estimated total</span><MacroRow m={total} /><p className="muted small">These are estimates based on typical values. Adjust amounts above if needed.</p>
        <Btn full onClick={() => { ready.forEach((i) => logFood(i.food!, i.grams!, slot, date, true)); toast(`Logged ${ready.length} item${ready.length > 1 ? 's' : ''} as estimates`); back(); }}>Log {ready.length} item{ready.length > 1 ? 's' : ''} to {slot}</Btn>
        <Btn full kind="ghost" icon="star" onClick={() => { const name = prompt('Name this meal', text.slice(0, 30)); if (!name) return; update((d) => { d.favourites.push({ id: uid(), name, items: ready.map((i) => ({ foodId: i.food!.id, grams: i.grams! })) }); }); toast('Saved to favourites'); }}>Save as favourite meal</Btn></Card>}
    </>}
  </>;
}

function Favourites({ slot, date }: { slot: MealSlot; date: string }) {
  const s = useStore((x) => x); const foods = allFoods(s);
  const todayMeals = s.meals.filter((m) => m.date === date && m.slot === slot);
  return <>
    {s.favourites.map((f) => { const kc = f.items.reduce((a, i) => { const fd = foods.find((x) => x.id === i.foodId); return a + (fd ? fd.kcal * i.grams / 100 : 0); }, 0);
      return <Card key={f.id} className="list-row"><div style={{ flex: 1 }}><b>{f.name}</b><small>{f.items.length} items · {fmt.n(kc)} kcal</small></div>
        <button className="icon-btn" onClick={() => update((d) => { d.favourites = d.favourites.filter((x) => x.id !== f.id); })} aria-label="Delete"><Icon n="trash" s={18} /></button>
        <Btn small onClick={() => { f.items.forEach((i) => { const fd = foods.find((x) => x.id === i.foodId); if (fd) logFood(fd, i.grams, slot, date); }); toast(`Logged ${f.name}`); back(); }}>Log</Btn></Card>; })}
    {!s.favourites.length && <Empty icon="star" title="No saved meals yet" text="Save the meal you just logged, or save one from the Describe tab." />}
    {todayMeals.length > 0 && <Btn full kind="soft" icon="star" onClick={() => { const name = prompt('Name this meal', `My ${slot}`); if (!name) return; update((d) => { d.favourites.push({ id: uid(), name, items: todayMeals.map((m) => ({ foodId: m.foodId, grams: m.grams })) }); }); toast('Saved'); }}>Save this {slot} ({todayMeals.length} items) as a favourite</Btn>}
  </>;
}

function CustomFood({ onSaved }: { onSaved: (f: Food) => void }) {
  const [f, setF] = useState({ name: '', serving: '1 serving', g: 100, kcal: 0, p: 0, c: 0, fat: 0, fib: 0, per: 'serving' as 'serving' | '100' });
  const ok = f.name.trim() && f.kcal > 0 && f.g > 0;
  function save() {
    const k = f.per === 'serving' ? 100 / f.g : 1;
    const food: Food = { id: 'cf-' + uid(), name: f.name.trim(), cat: 'Snacks & sweets', kcal: +(f.kcal * k).toFixed(1), p: +(f.p * k).toFixed(1), c: +(f.c * k).toFixed(1), f: +(f.fat * k).toFixed(1), fib: +(f.fib * k).toFixed(1), servings: [{ label: f.serving, g: f.g }], aliases: [f.name.toLowerCase()], custom: true };
    update((d) => { d.customFoods.push(food); }); toast('Custom food saved'); onSaved(food);
  }
  return <Card>
    <Field label="Food name"><input value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} placeholder="e.g. Mom's chicken curry" /></Field>
    <div className="row"><Field label="Serving name"><input value={f.serving} onChange={(e) => setF({ ...f, serving: e.target.value })} /></Field><Field label="Serving size (g)"><NumIn value={f.g} step={10} onChange={(v) => setF({ ...f, g: v })} w={56} /></Field></div>
    <Seg value={f.per} onChange={(v) => setF({ ...f, per: v })} options={[{ v: 'serving', l: 'Values per serving' }, { v: '100', l: 'Values per 100 g' }]} />
    <div className="grid2">
      <Field label="Calories (kcal)"><NumIn value={f.kcal} step={10} onChange={(v) => setF({ ...f, kcal: v })} w={56} /></Field><Field label="Protein (g)"><NumIn value={f.p} onChange={(v) => setF({ ...f, p: v })} w={56} /></Field>
      <Field label="Carbs (g)"><NumIn value={f.c} onChange={(v) => setF({ ...f, c: v })} w={56} /></Field><Field label="Fat (g)"><NumIn value={f.fat} onChange={(v) => setF({ ...f, fat: v })} w={56} /></Field>
      <Field label="Fibre (g)"><NumIn value={f.fib} onChange={(v) => setF({ ...f, fib: v })} w={56} /></Field>
    </div>
    <Btn full disabled={!ok} onClick={save}>Save custom food</Btn>
  </Card>;
}

function BarcodeScan({ onFound }: { onFound: (f: Food) => void }) {
  const [code, setCode] = useState(''); const [busy, setBusy] = useState(false); const [scanning, setScanning] = useState(false);
  const vid = useRef<HTMLVideoElement>(null); const streamRef = useRef<MediaStream | null>(null);
  const supported = typeof (window as any).BarcodeDetector !== 'undefined';
  async function lookup(c: string) {
    setBusy(true);
    try {
      const r = await fetch(`https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(c)}.json?fields=product_name,brands,nutriments,serving_quantity`);
      const j = await r.json();
      if (j.status !== 1) throw new Error('Product not found in Open Food Facts. Add it as a custom food.');
      const n = j.product.nutriments || {};
      const food: Food = { id: 'bc-' + c, name: [j.product.brands, j.product.product_name].filter(Boolean).join(' — ') || 'Scanned product', cat: 'Snacks & sweets', kcal: +(n['energy-kcal_100g'] ?? (n.energy_100g ? n.energy_100g / 4.184 : 0)).toFixed(0), p: +(n.proteins_100g || 0), c: +(n.carbohydrates_100g || 0), f: +(n.fat_100g || 0), fib: +(n.fiber_100g || 0), servings: [{ label: '1 serving', g: +j.product.serving_quantity || 100 }, { label: '100 g', g: 100 }], custom: true, aliases: [] };
      update((d) => { if (!d.customFoods.find((x) => x.id === food.id)) d.customFoods.push(food); });
      onFound(food);
    } catch (e: any) { toast(e.message || 'Lookup failed — check your internet connection.'); } finally { setBusy(false); }
  }
  async function start() {
    try {
      const st = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } }); streamRef.current = st; setScanning(true);
      requestAnimationFrame(() => { if (vid.current) { vid.current.srcObject = st; vid.current.play(); } });
      const det = new (window as any).BarcodeDetector({ formats: ['ean_13', 'ean_8', 'upc_a', 'upc_e'] });
      const loop = async () => { if (!streamRef.current || !vid.current) return; try { const r = await det.detect(vid.current); if (r[0]) { stop(); setCode(r[0].rawValue); lookup(r[0].rawValue); return; } } catch { /* */ } setTimeout(loop, 300); };
      setTimeout(loop, 600);
    } catch { toast('Camera permission is needed to scan.'); }
  }
  function stop() { streamRef.current?.getTracks().forEach((t) => t.stop()); streamRef.current = null; setScanning(false); }
  useEffect(() => stop, []);
  return <Card>
    <p className="muted small">Barcodes are looked up in Open Food Facts (free, community database — values come from product labels). Needs internet.</p>
    {supported ? (scanning ? <><video ref={vid} className="scan-vid" playsInline muted /><Btn full kind="ghost" onClick={stop}>Stop camera</Btn></> : <Btn full icon="camera" onClick={start}>Scan with camera</Btn>)
      : <p className="muted small">Camera scanning isn't supported on this device's browser engine — type the barcode number instead.</p>}
    <div className="row" style={{ marginTop: 10 }}><input inputMode="numeric" placeholder="Barcode number (EAN/UPC)" value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))} /><Btn disabled={code.length < 8 || busy} onClick={() => lookup(code)}>{busy ? '…' : 'Look up'}</Btn></div>
  </Card>;
}

// ─────────── Water ───────────
export function Water() {
  const s = useStore((x) => x); const tg = userTargets(s); const u = useUnits();
  const tot = dayTotals(s).water; const [custom, setCustom] = useState(300); const [range, setRange] = useState<'week' | 'month'>('week');
  const add = (ml: number) => { haptic(); update((d) => { d.water.push({ id: uid(), date: today(), ts: Date.now(), ml }); }); checkAchievements(); };
  const logs = s.water.filter((w) => w.date === today()).sort((a, b) => b.ts - a.ts);
  const n = range === 'week' ? 7 : 30;
  const hist = Array.from({ length: n }, (_, i) => { const d = dayOffset(i - n + 1); return { x: range === 'week' ? new Date(d + 'T00:00').toLocaleDateString('en-IN', { weekday: 'narrow' }) : (i % 5 === 0 ? String(new Date(d + 'T00:00').getDate()) : ''), y: dayTotals(s, d).water }; });
  const avg = hist.reduce((a, h) => a + h.y, 0) / n;
  const st = streak(s, (d) => dayTotals(s, d).water >= tg.water);
  const pct = Math.min(1, tot / tg.water);
  return (
    <div className="page">
      <Header left={<BackBtn />} title="Hydration" />
      <div className="water-hero">
        <div className="glass"><div className="glass-fill" style={{ height: `${pct * 100}%` }}><div className="wave" /></div><div className="glass-t"><b>{u.ml(tot)}</b><small>of {u.ml(tg.water)}</small></div></div>
        <p>{tot >= tg.water ? 'Target reached — nice work! 💧' : `${u.ml(tg.water - tot)} to go`}</p>
      </div>
      <div className="water-quick">{[100, 250, 500].map((ml) => <button key={ml} onClick={() => add(ml)}><Icon n="drop" s={18} /><b>+{ml}</b><small>ml</small></button>)}
        <div className="water-custom"><NumIn value={custom} step={50} onChange={setCustom} w={48} suffix="ml" /><Btn small onClick={() => custom > 0 && add(custom)}>Add</Btn></div></div>
      <Card>
        <div className="row-b"><span className="lbl">History</span><Seg value={range} onChange={setRange} options={[{ v: 'week', l: 'Week' }, { v: 'month', l: 'Month' }]} /></div>
        <Bars data={hist} goal={tg.water} color="var(--sky)" height={120} fmt={(v) => range === 'week' ? (v / 1000).toFixed(1) : ''} />
        <div className="row-b small muted"><span>Average {u.ml(avg)}/day</span><span>🔥 {st}-day streak</span></div>
      </Card>
      <Card>
        <span className="lbl">Today's log</span>
        {logs.map((l) => <div key={l.id} className="log-row"><span>{new Date(l.ts).toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' })}</span><b>{u.ml(l.ml)}</b><button className="icon-btn" onClick={() => update((d) => { d.water = d.water.filter((x) => x.id !== l.id); })} aria-label="Undo"><Icon n="x" s={16} /></button></div>)}
        {!logs.length && <p className="muted small">Nothing logged yet today.</p>}
      </Card>
      <WaterSettings />
      <p className="muted small pad">Target ≈ 35 ml per kg body weight, plus extra for training days{s.settings.hotClimate ? ' and hot weather' : ''}. This is a general guide, not a medical requirement — thirst and urine colour are good practical checks. If you have a heart or kidney condition, follow your doctor's fluid advice.</p>
    </div>
  );
}
function WaterSettings() {
  const s = useStore((x) => x); const r = s.settings.reminders; const tg = userTargets(s);
  const setR = async (patch: Partial<typeof r>) => { update((d) => { Object.assign(d.settings.reminders, patch); }); const res = await scheduleWaterReminders({ ...r, ...patch }); if (res === 'denied') toast('Notifications are blocked. Allow them in your phone settings.'); else if (patch.water) toast(res === 'native' ? 'Reminders scheduled' : 'Reminders on while the app is open'); };
  return <Card>
    <span className="lbl">Target & reminders</span>
    <Field label={`Daily target (${s.custom.water ? 'custom' : 'suggested'})`}><div className="row"><NumIn value={s.custom.water || tg.water} step={100} onChange={(v) => update((d) => { d.custom.water = v; })} suffix="ml" />{s.custom.water && <button className="link" onClick={() => update((d) => { delete d.custom.water; })}>Reset</button>}</div></Field>
    <Toggle on={s.settings.hotClimate} onChange={(v) => update((d) => { d.settings.hotClimate = v; })} label="Hot / humid climate" desc="Adds ~500 ml to the suggestion" />
    <Toggle on={r.water} onChange={(v) => setR({ water: v })} label="Water reminders" desc={r.water ? `Every ${r.every} min, ${r.from}:00–${r.to}:00` : 'Off — you can turn them on anytime'} />
    {r.water && <div className="chips">{[60, 90, 120, 180].map((m) => <Chip key={m} on={r.every === m} onClick={() => setR({ every: m })}>Every {m >= 120 ? m / 60 + ' h' : m + ' min'}</Chip>)}</div>}
  </Card>;
}

// ─────────── Body / BMI ───────────
export function Body() {
  const s = useStore((x) => x); const p = s.profile!; const u = useUnits();
  const cur = s.weights.length ? s.weights[s.weights.length - 1].kg : p.weight;
  const b = bmi(cur, p.height); const asian = s.settings.asianBmi; const bc = bmiClass(b, asian); const hr = healthyRange(p.height, asian);
  const [w, setW] = useState(u.wNum(cur)); const [mOpen, setMOpen] = useState(false); const [metric, setMetric] = useState<'waist' | 'hip' | 'bodyFat' | 'muscle' | 'chest' | 'arm' | 'thigh'>('waist');
  const data = s.weights.slice(-60).map((x) => ({ x: fmt.date(x.date), y: u.wNum(x.kg) }));
  const mData = s.measures.filter((m) => m[metric] !== undefined).map((m) => ({ x: fmt.date(m.date), y: metric === 'bodyFat' ? m[metric]! : metric === 'muscle' ? u.wNum(m[metric]!) : u.lenNum(m[metric]!) }));
  const scalePos = Math.max(0, Math.min(1, (b - 15) / 25));
  const whr = s.measures.slice().reverse().find((m) => m.waist && m.hip);
  return (
    <div className="page">
      <Header left={<BackBtn />} title="Body & BMI" />
      <Card className="bmi-card">
        <div className="row-b"><div><small className="muted">Current BMI</small><b className="bmi-big" style={{ color: bc.color }}>{b.toFixed(1)}</b><Pill>{bc.label}</Pill></div>
          <div className="bmi-side"><small>Healthy weight range</small><b>{u.w(hr.min, 0)} – {u.w(hr.max, 0)}</b><small>for {u.h(p.height)}</small></div></div>
        <div className="bmi-scale"><div className={'bmi-grad' + (asian ? ' asian' : '')} /><i style={{ left: `${scalePos * 100}%` }} /></div>
        <div className="bmi-ticks"><span>15</span><span>18.5</span><span>{asian ? '23' : '25'}</span><span>{asian ? '25' : '30'}</span><span>40</span></div>
        <Toggle on={asian} onChange={(v) => update((d) => { d.settings.asianBmi = v; })} label="Asian-Indian cut-offs" desc="Healthy < 23, overweight 23–24.9, obese ≥ 25 (used in India). Off = WHO international." />
        <p className="muted small">BMI is a screening measure based only on height and weight. It does not directly measure body fat or muscle — muscular people can score "overweight". Use it alongside waist size and how you feel and perform.</p>
      </Card>
      <div className="ex-stats"><div><small>Current</small><b>{u.w(cur)}</b></div><div><small>Target</small><b>{u.w(p.targetWeight)}</b></div><div><small>Difference</small><b>{(cur - p.targetWeight > 0 ? '−' : '+') + u.w(Math.abs(cur - p.targetWeight))}</b></div><div><small>Change</small><b>{s.weights.length > 1 ? ((cur - s.weights[0].kg > 0 ? '+' : '') + u.w(cur - s.weights[0].kg)) : '—'}</b></div></div>
      <Card>
        <span className="lbl">Weight history</span>
        <LineChart data={data} goal={u.wNum(p.targetWeight)} unit={u.wU} />
        <div className="row"><NumIn value={w} step={0.1} onChange={setW} suffix={u.wU} /><Btn full onClick={() => { const kg = +u.wIn(w).toFixed(2); update((d) => { d.weights = d.weights.filter((x) => x.date !== today()); d.weights.push({ date: today(), kg }); d.weights.sort((a, c) => a.date.localeCompare(c.date)); if (d.profile) d.profile.weight = kg; }); checkAchievements(); toast('Weight logged'); }}>Log today's weight</Btn></div>
      </Card>
      <Card>
        <div className="row-b"><span className="lbl">Body measurements</span><button className="link" onClick={() => setMOpen(true)}>+ Add</button></div>
        <div className="chips scroll">{([['waist', 'Waist'], ['hip', 'Hip'], ['bodyFat', 'Body fat %'], ['muscle', 'Muscle mass'], ['chest', 'Chest'], ['arm', 'Arm'], ['thigh', 'Thigh']] as const).map(([k, l]) => <Chip key={k} on={metric === k} onClick={() => setMetric(k)}>{l}</Chip>)}</div>
        <LineChart data={mData} color="var(--violet)" unit={metric === 'bodyFat' ? '%' : metric === 'muscle' ? u.wU : u.lenU} />
        {whr && <p className="small muted">Waist-to-hip ratio {(whr.waist! / whr.hip!).toFixed(2)} · waist-to-height {(whr.waist! / p.height).toFixed(2)} (under 0.5 is a commonly used healthy marker).</p>}
      </Card>
      <MeasureSheet open={mOpen} onClose={() => setMOpen(false)} />
    </div>
  );
}
function MeasureSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const u = useUnits(); const [v, setV] = useState<Record<string, number>>({});
  const fields: [string, string, 'len' | 'pct' | 'w'][] = [['waist', 'Waist (at navel)', 'len'], ['hip', 'Hip (widest)', 'len'], ['chest', 'Chest', 'len'], ['arm', 'Arm (flexed)', 'len'], ['thigh', 'Thigh', 'len'], ['bodyFat', 'Body fat %', 'pct'], ['muscle', 'Muscle mass', 'w']];
  return <Sheet open={open} onClose={onClose} title="Add measurements">
    <p className="muted small">Fill only what you measured. Smart-scale body-fat readings vary a lot with hydration — compare trends, not single numbers.</p>
    <div className="grid2">{fields.map(([k, l, t]) => <Field key={k} label={`${l} (${t === 'len' ? u.lenU : t === 'pct' ? '%' : u.wU})`}><input inputMode="decimal" value={v[k] ?? ''} onChange={(e) => setV({ ...v, [k]: parseFloat(e.target.value) })} /></Field>)}</div>
    <Btn full onClick={() => { const m: any = { date: today() }; for (const [k, , t] of fields) if (Number.isFinite(v[k])) m[k] = t === 'len' ? u.lenIn(v[k]) : t === 'w' ? u.wIn(v[k]) : v[k]; update((d) => { d.measures = d.measures.filter((x) => x.date !== today()); d.measures.push(m); d.measures.sort((a, b) => a.date.localeCompare(b.date)); }); setV({}); onClose(); toast('Measurements saved'); }}>Save</Btn>
  </Sheet>;
}

// ─────────── Targets ───────────
export function Targets() {
  const s = useStore((x) => x); const p = s.profile!; const tg = userTargets(s);
  const [kcal, setKcal] = useState(s.custom.kcal || tg.kcal); const [prot, setProt] = useState(s.custom.protein || tg.protein);
  return (
    <div className="page">
      <Header left={<BackBtn />} title="Nutrition targets" />
      <Card>
        <span className="lbl">How your targets are calculated</span>
        <div className="plan-rows">
          <div><span>BMR — Mifflin-St Jeor</span><b>{Math.round(tg.bmr)} kcal</b></div>
          <div><span>× activity ({ACTIVITY[p.activity].label}, {ACTIVITY[p.activity].mult})</span><b>{Math.round(tg.tdee)} kcal TDEE</b></div>
          <div><span>Goal: {GOALS[p.goal].label} ({GOALS[p.goal].adj > 0 ? '+' : ''}{Math.round(GOALS[p.goal].adj * 100)}%)</span><b>{tg.kcal} kcal</b></div>
          <div><span>Protein</span><b>{tg.protein} g</b></div><div><span>Fat (~25–27% kcal)</span><b>{tg.fat} g</b></div><div><span>Carbs (remainder)</span><b>{tg.carbs} g</b></div>
          <div><span>Fibre (14 g / 1000 kcal)</span><b>{tg.fibre} g</b></div><div><span>Water</span><b>{(tg.water / 1000).toFixed(1)} L</b></div>
        </div>
        <p className="muted small">{GOALS[p.goal].note}</p>
        {tg.notes.map((n, i) => <p key={i} className="muted small">• {n}</p>)}
      </Card>
      <Card>
        <span className="lbl">Customise</span>
        <Field label="Daily calories"><NumIn value={kcal} step={50} onChange={setKcal} suffix="kcal" /></Field>
        <Field label="Daily protein"><NumIn value={prot} step={5} onChange={setProt} suffix="g" /></Field>
        {kcal < (p.sex === 'male' ? 1500 : 1200) && <p className="err">That is very low. Intakes under {p.sex === 'male' ? 1500 : 1200} kcal should be supervised by a doctor or dietitian.</p>}
        <div className="row"><Btn kind="ghost" onClick={() => { update((d) => { delete d.custom.kcal; delete d.custom.protein; }); setKcal(tg.kcal); toast('Reset to recommended'); }}>Use recommended</Btn>
          <Btn full onClick={() => { update((d) => { d.custom.kcal = kcal; d.custom.protein = prot; }); toast('Targets saved'); back(); }}>Save</Btn></div>
      </Card>
    </div>
  );
}
