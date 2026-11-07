-- FITVERSE database schema for Supabase (PostgreSQL).
-- Run in Supabase → SQL Editor. Creates tables, indexes, Row Level Security, storage buckets and triggers.
-- Users can only modify their own private records. Health data is never readable by other users.

create extension if not exists "pgcrypto";

-- ───────── Users & profiles ─────────
-- auth.users is managed by Supabase Auth ("Users" table).
create table if not exists public.profiles (               -- public social identity
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (username ~ '^[a-z0-9_.]{2,20}$'),
  display_name text, bio text check (char_length(bio) <= 160), avatar_path text,
  is_private boolean not null default false, show_stats boolean not null default false,
  is_admin boolean not null default false, is_creator boolean not null default false, suspended boolean not null default false,
  plan text not null default 'free' check (plan in ('free','premium')),
  created_at timestamptz not null default now()
);
create table if not exists public.user_profiles (          -- private fitness profile
  user_id uuid primary key references auth.users(id) on delete cascade,
  age int check (age between 13 and 100), sex text check (sex in ('male','female')),
  height_cm numeric(5,1), weight_kg numeric(5,1), target_weight_kg numeric(5,1),
  experience text, activity_level text, training_days int, session_minutes int, goal text, equipment text,
  diet text, allergies text[] default '{}', updated_at timestamptz default now()
);

-- ───────── Exercise library ─────────
create table if not exists public.muscle_groups (id text primary key, name text not null, sort int);
create table if not exists public.exercises (
  id text primary key, name text not null, muscle_group_id text references public.muscle_groups(id),
  secondary_muscles text[] default '{}', equipment text not null, gear text, type text, mechanic text check (mechanic in ('compound','isolation')),
  difficulty int check (difficulty between 1 and 3), starting_position text, steps text[], breathing text, posture text,
  mistakes text[], safety text[], sets text, reps text, rest text, tempo text,
  video_path text, video_license text, is_premium boolean default false, published boolean default true, updated_at timestamptz default now()
);
create table if not exists public.exercise_alternatives (
  exercise_id text references public.exercises(id) on delete cascade, equipment_level text not null,
  alternative_id text references public.exercises(id) on delete cascade, primary key (exercise_id, equipment_level)
);

-- ───────── Workouts ─────────
create table if not exists public.workout_programmes (
  id text primary key, name text not null, level text, goal text, per_week int, description text, days jsonb not null, is_premium boolean default false, published boolean default true
);
create table if not exists public.workout_sessions (
  id text primary key, user_id uuid not null references auth.users(id) on delete cascade, name text, program_ref text,
  started_at timestamptz, ended_at timestamptz, volume_kg numeric(10,1), created_at timestamptz default now()
);
create table if not exists public.workout_logs (
  id text primary key, session_id text not null references public.workout_sessions(id) on delete cascade, user_id uuid not null references auth.users(id) on delete cascade,
  exercise_ref text not null, set_no int, weight_kg numeric(6,2), reps int, completed boolean default true
);

-- ───────── Nutrition ─────────
create table if not exists public.food_database (
  id text primary key, name text not null, category text, kcal numeric(6,1), protein_g numeric(5,1), carbs_g numeric(5,1), fat_g numeric(5,1), fibre_g numeric(5,1),
  unit text default 'g', servings jsonb default '[]', aliases text[] default '{}', is_estimate boolean default false, source text, created_by uuid references auth.users(id) on delete set null
);
create table if not exists public.meal_logs (
  id text primary key, user_id uuid not null references auth.users(id) on delete cascade, date date not null, meal text check (meal in ('breakfast','lunch','dinner','snacks')),
  food_ref text, food_name text, grams numeric(7,1), kcal numeric(7,1), protein_g numeric(6,1), carbs_g numeric(6,1), fat_g numeric(6,1), fibre_g numeric(6,1), is_estimate boolean default false, created_at timestamptz default now()
);
create table if not exists public.water_intake_logs (id text primary key, user_id uuid not null references auth.users(id) on delete cascade, date date not null, ml int check (ml between 1 and 5000), logged_at timestamptz default now());
create table if not exists public.weight_history (user_id uuid not null references auth.users(id) on delete cascade, date date not null, weight_kg numeric(5,1) not null, primary key (user_id, date));
create table if not exists public.body_measurements (
  user_id uuid not null references auth.users(id) on delete cascade, date date not null, waist_cm numeric(5,1), hip_cm numeric(5,1), body_fat_pct numeric(4,1), muscle_kg numeric(5,1),
  chest_cm numeric(5,1), arm_cm numeric(5,1), thigh_cm numeric(5,1), primary key (user_id, date)
);
create or replace view public.daily_nutrition_summaries with (security_invoker = true) as
  select user_id, date, sum(kcal) kcal, sum(protein_g) protein_g, sum(carbs_g) carbs_g, sum(fat_g) fat_g, sum(fibre_g) fibre_g from public.meal_logs group by user_id, date;

-- ───────── Social ─────────
create table if not exists public.social_posts (
  id text primary key, user_id uuid not null references auth.users(id) on delete cascade, kind text not null, body text check (char_length(body) <= 2200),
  like_count int not null default 0, comment_count int not null default 0, removed boolean not null default false, created_at timestamptz not null default now()
);
create table if not exists public.post_media (id uuid primary key default gen_random_uuid(), post_id text not null references public.social_posts(id) on delete cascade, user_id uuid not null references auth.users(id) on delete cascade, storage_path text not null, media_type text check (media_type in ('image','video')));
create table if not exists public.likes (post_id text references public.social_posts(id) on delete cascade, user_id uuid references auth.users(id) on delete cascade, created_at timestamptz default now(), primary key (post_id, user_id));
create table if not exists public.comments (id text primary key, post_id text not null references public.social_posts(id) on delete cascade, user_id uuid not null references auth.users(id) on delete cascade, parent_id text references public.comments(id) on delete cascade, body text not null check (char_length(body) between 1 and 1000), created_at timestamptz default now());
create table if not exists public.bookmarks (post_id text references public.social_posts(id) on delete cascade, user_id uuid references auth.users(id) on delete cascade, primary key (post_id, user_id));
create table if not exists public.followers (follower_id uuid references auth.users(id) on delete cascade, following_id uuid references auth.users(id) on delete cascade, status text not null default 'accepted' check (status in ('pending','accepted')), created_at timestamptz default now(), primary key (follower_id, following_id), check (follower_id <> following_id));
create table if not exists public.blocks (blocker_id uuid references auth.users(id) on delete cascade, blocked_id uuid references auth.users(id) on delete cascade, primary key (blocker_id, blocked_id));
create table if not exists public.reports (id uuid primary key default gen_random_uuid(), post_id text references public.social_posts(id) on delete cascade, reporter_id uuid references auth.users(id) on delete cascade, reason text, status text default 'open' check (status in ('open','removed','dismissed')), created_at timestamptz default now());
create table if not exists public.notifications (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, actor_id uuid references auth.users(id) on delete cascade, type text not null, post_id text, body text, read boolean default false, created_at timestamptz default now());

-- ───────── Challenges & achievements ─────────
create table if not exists public.fitness_challenges (id text primary key, name text not null, description text, days int, unit text, daily_target numeric, emoji text, starts_at date, created_by uuid references auth.users(id), published boolean default true);
create table if not exists public.challenge_participation (challenge_id text references public.fitness_challenges(id) on delete cascade, user_id uuid references auth.users(id) on delete cascade, joined_at timestamptz default now(), log jsonb default '{}', show_on_leaderboard boolean default true, primary key (challenge_id, user_id));
create table if not exists public.user_achievements (user_id uuid references auth.users(id) on delete cascade, achievement_id text, earned_at timestamptz default now(), primary key (user_id, achievement_id));

-- ───────── Indexes ─────────
create index if not exists idx_posts_created on public.social_posts (created_at desc) where not removed;
create index if not exists idx_posts_user on public.social_posts (user_id, created_at desc);
create index if not exists idx_comments_post on public.comments (post_id, created_at);
create index if not exists idx_followers_following on public.followers (following_id, status);
create index if not exists idx_meals_user_date on public.meal_logs (user_id, date);
create index if not exists idx_water_user_date on public.water_intake_logs (user_id, date);
create index if not exists idx_sessions_user on public.workout_sessions (user_id, started_at desc);
create index if not exists idx_logs_session on public.workout_logs (session_id);
create index if not exists idx_notif_user on public.notifications (user_id, created_at desc);
create index if not exists idx_exercises_muscle on public.exercises (muscle_group_id);
create index if not exists idx_food_name on public.food_database using gin (to_tsvector('simple', name));

-- ───────── Helpers ─────────
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as
$$ select coalesce((select is_admin from public.profiles where id = auth.uid()), false) $$;
create or replace function public.can_see_user(target uuid) returns boolean language sql stable security definer set search_path = public as $$
  select target = auth.uid() or (
    not exists (select 1 from blocks where (blocker_id = target and blocked_id = auth.uid()) or (blocker_id = auth.uid() and blocked_id = target))
    and (not (select is_private from profiles where id = target)
         or exists (select 1 from followers where follower_id = auth.uid() and following_id = target and status = 'accepted')))
$$;

-- ───────── Row Level Security ─────────
do $$ declare t text; begin
  foreach t in array array['profiles','user_profiles','muscle_groups','exercises','exercise_alternatives','workout_programmes','workout_sessions','workout_logs','food_database','meal_logs','water_intake_logs','weight_history','body_measurements','social_posts','post_media','likes','comments','bookmarks','followers','blocks','reports','notifications','fitness_challenges','challenge_participation','user_achievements']
  loop execute format('alter table public.%I enable row level security', t); end loop;
end $$;

-- private, owner-only tables (health data)
do $$ declare t text; begin
  foreach t in array array['user_profiles','workout_sessions','workout_logs','meal_logs','water_intake_logs','weight_history','body_measurements','bookmarks','user_achievements']
  loop
    execute format('drop policy if exists own_all on public.%I', t);
    execute format('create policy own_all on public.%I for all using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;

-- public content tables: read for everyone signed in, write for admins
do $$ declare t text; begin
  foreach t in array array['muscle_groups','exercises','exercise_alternatives','workout_programmes','fitness_challenges']
  loop
    execute format('drop policy if exists read_all on public.%I', t);
    execute format('create policy read_all on public.%I for select using (auth.role() = ''authenticated'')', t);
    execute format('drop policy if exists admin_write on public.%I', t);
    execute format('create policy admin_write on public.%I for all using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;
drop policy if exists food_read on public.food_database; create policy food_read on public.food_database for select using (auth.role() = 'authenticated');
drop policy if exists food_admin on public.food_database; create policy food_admin on public.food_database for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists p_read on public.profiles; create policy p_read on public.profiles for select using (auth.role() = 'authenticated' and not suspended or id = auth.uid() or public.is_admin());
drop policy if exists p_ins on public.profiles; create policy p_ins on public.profiles for insert with check (id = auth.uid() and is_admin = false);
drop policy if exists p_upd on public.profiles; create policy p_upd on public.profiles for update using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());
-- prevent users from promoting themselves
create or replace function public.guard_profile() returns trigger language plpgsql as $$ begin
  if not public.is_admin() then new.is_admin := old.is_admin; new.is_creator := old.is_creator; new.suspended := old.suspended; new.plan := old.plan; end if; return new; end $$;
drop trigger if exists trg_guard_profile on public.profiles; create trigger trg_guard_profile before update on public.profiles for each row execute function public.guard_profile();

drop policy if exists posts_read on public.social_posts; create policy posts_read on public.social_posts for select using ((not removed and public.can_see_user(user_id)) or public.is_admin());
drop policy if exists posts_ins on public.social_posts; create policy posts_ins on public.social_posts for insert with check (user_id = auth.uid() and not (select suspended from profiles where id = auth.uid()));
drop policy if exists posts_upd on public.social_posts; create policy posts_upd on public.social_posts for update using (user_id = auth.uid() or public.is_admin());
drop policy if exists posts_del on public.social_posts; create policy posts_del on public.social_posts for delete using (user_id = auth.uid() or public.is_admin());
drop policy if exists media_read on public.post_media; create policy media_read on public.post_media for select using (exists (select 1 from social_posts p where p.id = post_id));
drop policy if exists media_write on public.post_media; create policy media_write on public.post_media for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists likes_read on public.likes; create policy likes_read on public.likes for select using (exists (select 1 from social_posts p where p.id = post_id));
drop policy if exists likes_write on public.likes; create policy likes_write on public.likes for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists cm_read on public.comments; create policy cm_read on public.comments for select using (exists (select 1 from social_posts p where p.id = post_id));
drop policy if exists cm_write on public.comments; create policy cm_write on public.comments for insert with check (user_id = auth.uid());
drop policy if exists cm_del on public.comments; create policy cm_del on public.comments for delete using (user_id = auth.uid() or public.is_admin());
drop policy if exists f_read on public.followers; create policy f_read on public.followers for select using (auth.role() = 'authenticated');
drop policy if exists f_ins on public.followers; create policy f_ins on public.followers for insert with check (follower_id = auth.uid());
drop policy if exists f_upd on public.followers; create policy f_upd on public.followers for update using (following_id = auth.uid());  -- approve requests
drop policy if exists f_del on public.followers; create policy f_del on public.followers for delete using (follower_id = auth.uid() or following_id = auth.uid());
drop policy if exists b_all on public.blocks; create policy b_all on public.blocks for all using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());
drop policy if exists r_ins on public.reports; create policy r_ins on public.reports for insert with check (reporter_id = auth.uid());
drop policy if exists r_admin on public.reports; create policy r_admin on public.reports for all using (public.is_admin());
drop policy if exists n_own on public.notifications; create policy n_own on public.notifications for select using (user_id = auth.uid());
drop policy if exists n_upd on public.notifications; create policy n_upd on public.notifications for update using (user_id = auth.uid());
drop policy if exists cp_own on public.challenge_participation; create policy cp_own on public.challenge_participation for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists cp_board on public.challenge_participation; create policy cp_board on public.challenge_participation for select using (show_on_leaderboard);

-- ───────── Triggers: counters, private-account follows, notifications, spam limits ─────────
create or replace function public.on_like() returns trigger language plpgsql security definer set search_path = public as $$ begin
  if tg_op = 'INSERT' then
    update social_posts set like_count = like_count + 1 where id = new.post_id;
    insert into notifications (user_id, actor_id, type, post_id, body) select p.user_id, new.user_id, 'like', p.id, 'liked your post' from social_posts p where p.id = new.post_id and p.user_id <> new.user_id;
    return new;
  else update social_posts set like_count = greatest(like_count - 1, 0) where id = old.post_id; return old; end if; end $$;
drop trigger if exists trg_like on public.likes; create trigger trg_like after insert or delete on public.likes for each row execute function public.on_like();

create or replace function public.on_comment() returns trigger language plpgsql security definer set search_path = public as $$
declare m text; begin
  if (select count(*) from comments where user_id = new.user_id and created_at > now() - interval '1 minute') > 5 then raise exception 'Too many comments, slow down'; end if;
  update social_posts set comment_count = comment_count + 1 where id = new.post_id;
  insert into notifications (user_id, actor_id, type, post_id, body) select p.user_id, new.user_id, 'comment', p.id, left(new.body, 120) from social_posts p where p.id = new.post_id and p.user_id <> new.user_id;
  for m in select (regexp_matches(new.body, '@([a-z0-9_.]+)', 'g'))[1] loop
    insert into notifications (user_id, actor_id, type, post_id, body) select id, new.user_id, 'mention', new.post_id, left(new.body, 120) from profiles where username = m and id <> new.user_id;
  end loop; return new; end $$;
drop trigger if exists trg_comment on public.comments; create trigger trg_comment before insert on public.comments for each row execute function public.on_comment();

create or replace function public.on_post() returns trigger language plpgsql as $$ begin
  if (select count(*) from social_posts where user_id = new.user_id and created_at > now() - interval '2 minutes') >= 3 then raise exception 'Posting too quickly'; end if; return new; end $$;
drop trigger if exists trg_post on public.social_posts; create trigger trg_post before insert on public.social_posts for each row execute function public.on_post();

create or replace function public.on_follow() returns trigger language plpgsql security definer set search_path = public as $$ begin
  if tg_op = 'INSERT' then
    new.status := case when (select is_private from profiles where id = new.following_id) then 'pending' else 'accepted' end;
    insert into notifications (user_id, actor_id, type, body) values (new.following_id, new.follower_id, case when new.status = 'pending' then 'request' else 'follow' end, case when new.status = 'pending' then 'requested to follow you' else 'started following you' end);
  end if; return new; end $$;
drop trigger if exists trg_follow on public.followers; create trigger trg_follow before insert on public.followers for each row execute function public.on_follow();

-- ───────── Storage (create buckets) ─────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('post-media', 'post-media', true, 62914560, array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime','video/webm']),
  ('progress-photos', 'progress-photos', false, 15728640, array['image/jpeg','image/png','image/webp']),
  ('avatars', 'avatars', true, 5242880, array['image/jpeg','image/png','image/webp']),
  ('exercise-videos', 'exercise-videos', true, 209715200, array['video/mp4','video/webm'])
on conflict (id) do nothing;
drop policy if exists "own folder write" on storage.objects;
create policy "own folder write" on storage.objects for insert to authenticated with check (bucket_id in ('post-media','progress-photos','avatars') and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "own folder delete" on storage.objects;
create policy "own folder delete" on storage.objects for delete to authenticated using ((storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "progress photos private" on storage.objects;
create policy "progress photos private" on storage.objects for select to authenticated using (bucket_id <> 'progress-photos' or (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "admin exercise videos" on storage.objects;
create policy "admin exercise videos" on storage.objects for all to authenticated using (bucket_id = 'exercise-videos' and public.is_admin()) with check (bucket_id = 'exercise-videos' and public.is_admin());

-- ───────── Admin analytics ─────────
create or replace view public.admin_platform_stats with (security_invoker = true) as
  select (select count(*) from profiles) users, (select count(*) from social_posts) posts, (select count(*) from reports where status = 'open') open_reports,
         (select count(*) from workout_sessions where started_at > now() - interval '7 days') workouts_7d, (select count(*) from meal_logs where date > current_date - 7) meals_7d
  where public.is_admin();

-- Make yourself admin after signing up:  update public.profiles set is_admin = true where username = 'yourname';

-- ───────── Direct messages (1-to-1 chat) ─────────
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (sender_id <> recipient_id)
);
create index if not exists idx_msg_pair on public.messages (sender_id, recipient_id, created_at desc);
create index if not exists idx_msg_inbox on public.messages (recipient_id, read_at, created_at desc);
alter table public.messages enable row level security;
drop policy if exists msg_read on public.messages; create policy msg_read on public.messages for select using (auth.uid() in (sender_id, recipient_id));
drop policy if exists msg_send on public.messages; create policy msg_send on public.messages for insert with check (
  sender_id = auth.uid()
  and not exists (select 1 from public.blocks b where b.blocker_id = recipient_id and b.blocked_id = auth.uid())
  and not coalesce((select suspended from public.profiles where id = auth.uid()), false));
-- recipients may only mark messages as read
drop policy if exists msg_read_mark on public.messages; create policy msg_read_mark on public.messages for update using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());
create or replace function public.guard_message() returns trigger language plpgsql as $$
begin
  if new.body <> old.body or new.sender_id <> old.sender_id or new.recipient_id <> old.recipient_id or new.created_at <> old.created_at then
    raise exception 'messages cannot be edited';
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_message on public.messages; create trigger trg_guard_message before update on public.messages for each row execute function public.guard_message();
drop policy if exists msg_del on public.messages; create policy msg_del on public.messages for delete using (sender_id = auth.uid());

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
