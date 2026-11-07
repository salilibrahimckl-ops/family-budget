-- ───────── Friend challenges (challenge friends: most calories / active minutes / sessions in N days) ─────────
create table if not exists public.friend_challenges (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 80),
  metric text not null check (metric in ('kcal','minutes','sessions')),
  starts_on date not null, ends_on date not null check (ends_on >= starts_on and ends_on - starts_on <= 60),
  created_at timestamptz not null default now()
);
create table if not exists public.challenge_members (
  challenge_id uuid not null references public.friend_challenges(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'invited' check (status in ('invited','accepted','declined')),
  progress int not null default 0 check (progress between 0 and 1000000),
  updated_at timestamptz not null default now(),
  primary key (challenge_id, user_id)
);
create index if not exists idx_cm_user on public.challenge_members (user_id);
create or replace function public.is_challenge_member(ch uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from challenge_members where challenge_id = ch and user_id = auth.uid())
      or exists (select 1 from friend_challenges where id = ch and creator_id = auth.uid());
$$;
alter table public.friend_challenges enable row level security;
alter table public.challenge_members enable row level security;
drop policy if exists fc_read on public.friend_challenges; create policy fc_read on public.friend_challenges for select using (public.is_challenge_member(id));
drop policy if exists fc_make on public.friend_challenges; create policy fc_make on public.friend_challenges for insert with check (creator_id = auth.uid());
drop policy if exists fc_del on public.friend_challenges; create policy fc_del on public.friend_challenges for delete using (creator_id = auth.uid());
drop policy if exists cm_read on public.challenge_members; create policy cm_read on public.challenge_members for select using (public.is_challenge_member(challenge_id));
drop policy if exists cm_invite on public.challenge_members; create policy cm_invite on public.challenge_members for insert with check (
  exists (select 1 from public.friend_challenges c where c.id = challenge_id and c.creator_id = auth.uid()));
drop policy if exists cm_self on public.challenge_members; create policy cm_self on public.challenge_members for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists cm_leave on public.challenge_members; create policy cm_leave on public.challenge_members for delete using (user_id = auth.uid());
