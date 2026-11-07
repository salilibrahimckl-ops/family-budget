// Supabase Edge Function: AI coach proxy. The AI key stays here as a secret — never in the app.
// Deploy:  supabase functions deploy coach   |   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...  (optional: COACH_MODEL)
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SYSTEM = `You are FITVERSE Coach, a certified strength coach and sports nutritionist.
Use the user's context (goal, body stats, targets, today's intake, recent workouts) to give specific, practical answers.
Rules: never diagnose medical conditions; never recommend crash diets, intakes under 1200 kcal (women) / 1500 kcal (men), or unsafe practices;
for pain, injury, pregnancy, eating disorders, heart/kidney/metabolic conditions, advise seeing a doctor or physiotherapist.
Prefer Indian/Kerala food examples when suggesting meals. Keep answers under 180 words, use short bullet lists.`;
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type' };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const auth = req.headers.get('Authorization') ?? '';
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } } });
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return new Response(JSON.stringify({ error: 'Unauthorised' }), { status: 401, headers: cors });
  const { data: prof } = await sb.from('profiles').select('plan').eq('id', user.id).single();
  if (prof?.plan !== 'premium') return new Response(JSON.stringify({ error: 'Premium required' }), { status: 402, headers: cors });
  const { question, context, history } = await req.json();
  if (typeof question !== 'string' || question.length > 1000) return new Response(JSON.stringify({ error: 'Bad request' }), { status: 400, headers: cors });
  const messages = [
    ...((history ?? []) as { role: string; text: string }[]).slice(-8).map((m) => ({ role: m.role === 'user' ? 'user' : 'assistant', content: m.text })),
    { role: 'user', content: `Context: ${JSON.stringify(context).slice(0, 4000)}\n\nQuestion: ${question}` },
  ];
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': Deno.env.get('ANTHROPIC_API_KEY')!, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
    body: JSON.stringify({ model: Deno.env.get('COACH_MODEL') ?? 'claude-sonnet-5-5', max_tokens: 600, system: SYSTEM, messages }),
  });
  if (!r.ok) return new Response(JSON.stringify({ error: 'AI service error' }), { status: 502, headers: cors });
  const j = await r.json();
  return new Response(JSON.stringify({ answer: j.content?.[0]?.text ?? '' }), { headers: { ...cors, 'Content-Type': 'application/json' } });
});
