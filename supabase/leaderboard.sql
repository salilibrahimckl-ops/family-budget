-- ───────── Friends leaderboard (weekly totals only; users can opt out in Settings → Privacy) ─────────
create table if not exists public.weekly_stats (
  user_id uuid primary key references auth.users(id) on delete cascade,
  week date not null, kcal int not null default 0 check (kcal between 0 and 100000), active_min int not null default 0 check (active_min between 0 and 10080),
  workouts int not null default 0 check (workouts between 0 and 200), streak int not null default 0 check (streak between 0 and 3660),
  updated_at timestamptz not null default now()
);
create index if not exists idx_ws_week on public.weekly_stats (week, kcal desc);
alter table public.weekly_stats enable row level security;
drop policy if exists ws_read on public.weekly_stats; create policy ws_read on public.weekly_stats for select using (auth.role() = 'authenticated');
drop policy if exists ws_own on public.weekly_stats; create policy ws_own on public.weekly_stats for all using (user_id = auth.uid()) with check (user_id = auth.uid());
