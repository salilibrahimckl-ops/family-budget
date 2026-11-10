-- Hifz Academy — initial schema (Phase 1)
-- Target: Supabase Postgres 15+ (tested locally on Postgres 16 with a test shim for auth.*).
--
-- Design rules enforced here, not just in app code:
--   1. Quran text (schema `quran`) is immutable: no UPDATE/DELETE/TRUNCATE ever,
--      INSERT only inside an explicit import session (SET app.quran_import = 'on').
--   2. Every Ayah row carries the SHA-256 of its text; a CHECK constraint recomputes it.
--   3. Quran text, translations and explanations live in separate tables with source/version.
--   4. Learning events (attempts, XP) are append-only, which makes multi-device sync conflict-free.
--   5. Row-level security on every user table: users see only their own rows; a teacher sees
--      a student's progress only after the student accepts the link.

create extension if not exists pgcrypto;

create schema if not exists quran;

-------------------------------------------------------------------------------
-- QURAN CONTENT (read-only after import)
-------------------------------------------------------------------------------

create table quran.sources (
  id            smallserial primary key,
  kind          text not null check (kind in ('text','words','translation','word_translation','audio','timing','tafsir')),
  name          text not null,              -- e.g. 'Tanzil Uthmani'
  url           text not null,
  version       text not null,              -- e.g. '1.1' or download date
  license       text not null,
  file_sha256   text not null check (file_sha256 ~ '^[0-9a-f]{64}$'),
  reviewed_by   text,                       -- human reviewer for translations/explanations
  imported_at   timestamptz not null default now(),
  unique (kind, name, version)
);

create table quran.surahs (
  id               smallint primary key check (id between 1 and 114),
  name_arabic      text not null,
  name_transliterated text not null,
  name_en          text not null,
  revelation_place text not null check (revelation_place in ('makkah','madinah')),
  ayah_count       smallint not null check (ayah_count between 3 and 286),
  source_id        smallint not null references quran.sources(id),
  bismillah_text   text,                    -- verbatim from source; null for Al-Fatiha (it is Ayah 1) and At-Tawbah
  bismillah_sha256 text,
  constraint bismillah_hash_matches check (
    (bismillah_text is null and bismillah_sha256 is null) or
    bismillah_sha256 = encode(digest(convert_to(bismillah_text, 'UTF8'), 'sha256'), 'hex'))
);

-- Stable global Ayah id 1..6236 (Hafs numbering), plus (surah, ayah) natural key.
create table quran.ayahs (
  id            smallint primary key check (id between 1 and 6236),
  surah_id      smallint not null references quran.surahs(id),
  ayah_number   smallint not null check (ayah_number >= 1),
  text_uthmani  text not null check (length(text_uthmani) > 0),
  text_sha256   text not null,
  juz           smallint check (juz between 1 and 30),
  hizb_quarter  smallint check (hizb_quarter between 1 and 240),
  page          smallint check (page between 1 and 604),
  source_id     smallint not null references quran.sources(id),
  unique (surah_id, ayah_number),
  constraint ayah_hash_matches check (
    text_sha256 = encode(digest(convert_to(text_uthmani, 'UTF8'), 'sha256'), 'hex')
  )
);
create index ayahs_juz_idx  on quran.ayahs (juz);
create index ayahs_page_idx on quran.ayahs (page);

-- Stable word id: ayah_id * 1000 + position (max 128 words per Ayah) — deterministic across imports.
create table quran.words (
  id            integer primary key,
  ayah_id       smallint not null references quran.ayahs(id),
  position      smallint not null check (position between 1 and 999),
  text_uthmani  text not null check (length(text_uthmani) > 0),
  source_id     smallint not null references quran.sources(id),
  unique (ayah_id, position),
  constraint word_id_is_stable check (id = ayah_id::integer * 1000 + position)
);

create table quran.translations (
  id          serial primary key,
  source_id   smallint not null references quran.sources(id),
  language    text not null check (language in ('ml','en','ar')),
  ayah_id     smallint not null references quran.ayahs(id),
  text        text not null,
  unique (source_id, ayah_id)
);
create index translations_lang_idx on quran.translations (language, ayah_id);

create table quran.word_translations (
  id          serial primary key,
  source_id   smallint not null references quran.sources(id),
  language    text not null check (language in ('ml','en')),
  word_id     integer not null references quran.words(id),
  text        text not null,
  unique (source_id, word_id)
);

create table quran.reciters (
  id            smallserial primary key,
  name_en       text not null,
  name_arabic   text not null,
  style         text not null check (style in ('murattal','mujawwad','muallim')),
  riwayah       text not null default 'hafs',
  license_note  text not null,              -- who authorised distribution, and terms
  is_premium    boolean not null default false,
  source_id     smallint not null references quran.sources(id)
);

create table quran.ayah_audio (
  reciter_id    smallint not null references quran.reciters(id),
  ayah_id       smallint not null references quran.ayahs(id),
  storage_path  text not null,              -- path in Supabase Storage bucket 'recitations'
  duration_ms   integer not null check (duration_ms > 0),
  sha256        text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  primary key (reciter_id, ayah_id)
);

create table quran.word_timings (
  reciter_id    smallint not null,
  ayah_id       smallint not null,
  word_id       integer not null references quran.words(id),
  start_ms      integer not null check (start_ms >= 0),
  end_ms        integer not null,
  primary key (reciter_id, word_id),
  foreign key (reciter_id, ayah_id) references quran.ayah_audio(reciter_id, ayah_id),
  check (end_ms > start_ms)
);

-- Immutability guard for the core Quran tables.
create or replace function quran.guard_immutable() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(current_setting('app.quran_import', true), 'off') <> 'on' then
      raise exception 'Quran content is read-only: inserts only allowed in an import session'
        using errcode = 'insufficient_privilege';
    end if;
    return new;
  end if;
  raise exception 'Quran content is immutable: % on %.% is not allowed', tg_op, tg_table_schema, tg_table_name
    using errcode = 'insufficient_privilege';
end $$;

do $$
declare t text;
begin
  foreach t in array array['surahs','ayahs','words'] loop
    execute format('create trigger %I_immutable before insert or update or delete on quran.%I
                    for each row execute function quran.guard_immutable()', t, t);
    execute format('create trigger %I_no_truncate before truncate on quran.%I
                    for each statement execute function quran.guard_immutable()', t, t);
  end loop;
end $$;

-------------------------------------------------------------------------------
-- USERS AND PREFERENCES  (auth.users is provided by Supabase Auth)
-------------------------------------------------------------------------------

create type public.learner_level as enum ('beginner','intermediate','hafiz');
create type public.learning_goal as enum ('from_beginning','selected_surahs','complete_quran','strengthen_hifz','tajweed');
create type public.ui_language as enum ('en','ml','ar');

create table public.profiles (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  display_name   text check (char_length(display_name) <= 60),
  is_teacher     boolean not null default false,
  timezone       text not null default 'Asia/Kolkata',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table public.learning_preferences (
  user_id               uuid primary key references auth.users(id) on delete cascade,
  goal                  public.learning_goal not null,
  level                 public.learner_level not null,
  ui_language           public.ui_language not null default 'en',
  translation_language  text not null default 'en' check (translation_language in ('en','ml')),
  daily_minutes         smallint not null check (daily_minutes in (10,20,30,45,60)),
  new_ayahs_per_day     smallint not null default 3 check (new_ayahs_per_day between 0 and 20),
  arabic_reading        smallint check (arabic_reading between 0 and 4),
  tajweed_knowledge     smallint check (tajweed_knowledge between 0 and 4),
  target_surahs         smallint[] not null default '{}',
  preferred_reciter_id  smallint references quran.reciters(id),
  mastery_threshold     numeric(3,2) not null default 0.90 check (mastery_threshold between 0.5 and 1.0),
  recording_consent_at  timestamptz,       -- null = no consent: mic features disabled
  audio_upload_consent_at timestamptz,     -- separate consent for sending audio to the server
  updated_at            timestamptz not null default now()
);

-------------------------------------------------------------------------------
-- MEMORISATION STATE
-------------------------------------------------------------------------------

create type public.memo_status as enum ('new','learning','recently_memorised','stable','strong','needs_revision');
create type public.lesson_step as enum ('listen','understand','repeat','visual','recall','connect','master');

-- One row per (user, Ayah). Derived state; recomputable from events.
create table public.memorisation_records (
  user_id            uuid not null references auth.users(id) on delete cascade,
  ayah_id            smallint not null references quran.ayahs(id),
  status             public.memo_status not null default 'new',
  current_step       public.lesson_step not null default 'listen',
  strength           numeric(4,3) not null default 0 check (strength between 0 and 1),
  ease               numeric(4,2) not null default 2.50 check (ease between 1.30 and 3.50),
  interval_days      numeric(7,2) not null default 0 check (interval_days >= 0),
  due_at             timestamptz,
  successes          integer not null default 0 check (successes >= 0),
  failures           integer not null default 0 check (failures >= 0),
  lapses             integer not null default 0 check (lapses >= 0),
  consecutive_passes smallint not null default 0 check (consecutive_passes >= 0),
  avg_recall_ms      integer,
  user_difficulty    smallint check (user_difficulty between 1 and 5),
  first_mastered_at  timestamptz,
  last_reviewed_at   timestamptz,
  teacher_override_by uuid references auth.users(id),
  updated_at         timestamptz not null default now(),
  primary key (user_id, ayah_id),
  -- 'strong' requires real history: never strong after a single correct answer
  constraint strong_needs_history check (status <> 'strong' or (successes >= 4 and consecutive_passes >= 3))
);
create index memo_due_idx    on public.memorisation_records (user_id, due_at) where due_at is not null;
create index memo_status_idx on public.memorisation_records (user_id, status);

-- Words a user repeatedly forgets (drives Missing Words + Forgotten Ayah Recovery).
create table public.word_weakness (
  user_id     uuid not null references auth.users(id) on delete cascade,
  word_id     integer not null references quran.words(id),
  miss_count  integer not null default 0 check (miss_count >= 0),
  last_missed_at timestamptz,
  primary key (user_id, word_id)
);

-------------------------------------------------------------------------------
-- LEARNING EVENTS (append-only)
-------------------------------------------------------------------------------

create type public.attempt_mode as enum (
  'lesson_repeat','lesson_recall','lesson_connect','lesson_master','revision',
  'challenge_missing_words','challenge_complete_ayah','challenge_continue','challenge_random_surah',
  'challenge_connect','challenge_full_surah','challenge_daily','challenge_recovery');
create type public.assessment_method as enum ('self_report','typed','asr_word','teacher');
create type public.mistake_kind as enum ('missing','substituted','repeated','added','order','pronunciation_possible');

create table public.learning_sessions (
  id            uuid primary key,             -- generated on device (offline-safe)
  user_id       uuid not null references auth.users(id) on delete cascade,
  device_id     text not null,
  planned_minutes smallint check (planned_minutes in (10,20,30,45,60)),
  started_at    timestamptz not null,
  ended_at      timestamptz,
  reciter_id    smallint references quran.reciters(id),  -- one Qari per session
  check (ended_at is null or ended_at >= started_at)
);
create index sessions_user_idx on public.learning_sessions (user_id, started_at desc);

create table public.recitation_attempts (
  id               uuid primary key,          -- generated on device
  user_id          uuid not null references auth.users(id) on delete cascade,
  session_id       uuid references public.learning_sessions(id) on delete set null,
  ayah_from        smallint not null references quran.ayahs(id),
  ayah_to          smallint not null references quran.ayahs(id),
  mode             public.attempt_mode not null,
  method           public.assessment_method not null,
  passed           boolean not null,
  accuracy         numeric(4,3) check (accuracy between 0 and 1),
  confidence       numeric(4,3) check (confidence between 0 and 1),  -- null for self_report
  recall_ms        integer check (recall_ms >= 0),
  hints_used       smallint not null default 0,
  audio_path       text,                      -- only if user consented to upload
  engine_version   text,                      -- ASR model id for audit
  device_id        text not null,
  occurred_at      timestamptz not null,
  received_at      timestamptz not null default now(),
  check (ayah_to >= ayah_from),
  check (method <> 'asr_word' or confidence is not null)
);
create index attempts_user_time_idx on public.recitation_attempts (user_id, occurred_at desc);
create index attempts_user_ayah_idx on public.recitation_attempts (user_id, ayah_from);

create table public.detected_mistakes (
  id           bigserial primary key,
  attempt_id   uuid not null references public.recitation_attempts(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  word_id      integer not null references quran.words(id),   -- always a verified word, never free text
  kind         public.mistake_kind not null,
  confidence   numeric(4,3) not null check (confidence between 0 and 1),
  heard_word_id integer references quran.words(id),           -- for substitutions: which verified word was heard
  created_at   timestamptz not null default now()
);
create index mistakes_user_word_idx on public.detected_mistakes (user_id, word_id);

create type public.xp_reason as enum ('new_ayah','revision_pass','surah_complete','tajweed_lesson','recitation_improved','daily_session','mission','challenge');

create table public.xp_transactions (
  id           uuid primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  amount       integer not null check (amount between -500 and 500 and amount <> 0),
  reason       public.xp_reason not null,
  ref_attempt  uuid references public.recitation_attempts(id) on delete set null,
  ref_ayah     smallint references quran.ayahs(id),
  occurred_at  timestamptz not null,
  -- one award per reason per attempt: replays of the same sync batch can't double-count
  unique (user_id, reason, ref_attempt)
);
create index xp_user_time_idx on public.xp_transactions (user_id, occurred_at);

create table public.streak_days (
  user_id      uuid not null references auth.users(id) on delete cascade,
  day          date not null,
  kind         text not null check (kind in ('learned','freeze_used','grace')),
  primary key (user_id, day)
);

create or replace function public.guard_append_only() returns trigger
language plpgsql as $$
begin
  raise exception '% is append-only; % not allowed', tg_table_name, tg_op
    using errcode = 'insufficient_privilege';
end $$;

create trigger attempts_append_only before update on public.recitation_attempts
  for each row execute function public.guard_append_only();
create trigger mistakes_append_only before update on public.detected_mistakes
  for each row execute function public.guard_append_only();
create trigger xp_append_only before update on public.xp_transactions
  for each row execute function public.guard_append_only();

-------------------------------------------------------------------------------
-- TAJWEED ACADEMY, ACHIEVEMENTS, CHALLENGES
-------------------------------------------------------------------------------

create table public.tajweed_lessons (
  id            smallserial primary key,
  slug          text not null unique,
  level         text not null check (level in ('beginner','intermediate','advanced')),
  sort_order    smallint not null,
  title_en      text not null,
  title_ml      text not null,
  body_en       text not null,
  body_ml       text not null,
  example_ayah_ids smallint[] not null default '{}',  -- examples are references, never retyped Arabic
  reviewed_by   text,                                 -- scholar/teacher who approved it
  is_published  boolean not null default false,
  check (not is_published or reviewed_by is not null)  -- nothing ships unreviewed
);

create table public.tajweed_progress (
  user_id     uuid not null references auth.users(id) on delete cascade,
  lesson_id   smallint not null references public.tajweed_lessons(id),
  quiz_score  numeric(4,3) check (quiz_score between 0 and 1),
  completed_at timestamptz,
  primary key (user_id, lesson_id)
);

create table public.achievements (
  id          text primary key,              -- 'first_ayah', 'first_surah', 'streak_7', ...
  title_en    text not null,
  title_ml    text not null,
  title_ar    text not null,
  rule        jsonb not null                 -- evaluated by the gamification engine
);

create table public.user_achievements (
  user_id        uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null references public.achievements(id),
  earned_at      timestamptz not null,
  primary key (user_id, achievement_id)
);

create table public.daily_challenges (
  user_id     uuid not null references auth.users(id) on delete cascade,
  day         date not null,
  kind        public.attempt_mode not null,
  ayah_ids    smallint[] not null,
  score       numeric(5,2),
  completed_at timestamptz,
  primary key (user_id, day, kind)
);

-------------------------------------------------------------------------------
-- SUBSCRIPTIONS, TEACHERS, CONSENT, DATA RIGHTS
-------------------------------------------------------------------------------

create table public.subscriptions (
  user_id          uuid primary key references auth.users(id) on delete cascade,
  plan             text not null default 'free' check (plan in ('free','premium')),
  store            text check (store in ('play','app_store','promo')),
  revenuecat_id    text unique,
  current_period_end timestamptz,
  updated_at       timestamptz not null default now()
);

create table public.teacher_students (
  teacher_id   uuid not null references auth.users(id) on delete cascade,
  student_id   uuid not null references auth.users(id) on delete cascade,
  status       text not null default 'invited' check (status in ('invited','accepted','revoked')),
  can_override boolean not null default false,  -- student may allow the teacher to mark mastery
  created_at   timestamptz not null default now(),
  primary key (teacher_id, student_id),
  check (teacher_id <> student_id)
);

create table public.data_requests (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('export','delete')),
  status      text not null default 'pending' check (status in ('pending','done','failed')),
  created_at  timestamptz not null default now(),
  finished_at timestamptz
);

-------------------------------------------------------------------------------
-- HELPERS
-------------------------------------------------------------------------------

create or replace function public.is_teacher_of(student uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.teacher_students
                 where teacher_id = auth.uid() and student_id = student and status = 'accepted');
$$;

create or replace function public.is_premium(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.subscriptions
                 where user_id = uid and plan = 'premium'
                   and (current_period_end is null or current_period_end > now()));
$$;

-- Today's revision queue: weakest and most overdue first.
create or replace view public.revision_queue with (security_invoker = true) as
select r.user_id, r.ayah_id, a.surah_id, a.ayah_number, r.status, r.strength, r.due_at,
       (case r.status when 'needs_revision' then 0 when 'recently_memorised' then 1
                      when 'learning' then 2 else 3 end) as priority_band,
       greatest(0, extract(epoch from (now() - r.due_at)) / 86400.0) as days_overdue
from public.memorisation_records r
join quran.ayahs a on a.id = r.ayah_id
where r.due_at is not null and r.due_at <= now() + interval '12 hours'
  and r.status <> 'new';

-------------------------------------------------------------------------------
-- ROW-LEVEL SECURITY
-------------------------------------------------------------------------------

-- Quran content: readable by everyone (also anonymous), writable by nobody through the API.
grant usage on schema quran to anon, authenticated;
grant select on all tables in schema quran to anon, authenticated;
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'quran' loop
    execute format('alter table quran.%I enable row level security', t);
    execute format('create policy read_all on quran.%I for select using (true)', t);
  end loop;
end $$;

-- Owner-only tables: full own-row access (append-only ones get no update policy).
do $$
declare t text;
begin
  foreach t in array array['profiles','learning_preferences','memorisation_records','word_weakness',
                           'learning_sessions','streak_days','tajweed_progress','daily_challenges'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy own_select on public.%I for select using (user_id = auth.uid())', t);
    execute format('create policy own_insert on public.%I for insert with check (user_id = auth.uid())', t);
    execute format('create policy own_update on public.%I for update using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
    execute format('create policy own_delete on public.%I for delete using (user_id = auth.uid())', t);
  end loop;
  foreach t in array array['recitation_attempts','detected_mistakes','xp_transactions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy own_select on public.%I for select using (user_id = auth.uid())', t);
    execute format('create policy own_insert on public.%I for insert with check (user_id = auth.uid())', t);
  end loop;
end $$;

-- Teachers read accepted students' progress and attempts.
create policy teacher_select on public.memorisation_records for select using (public.is_teacher_of(user_id));
create policy teacher_select on public.recitation_attempts  for select using (public.is_teacher_of(user_id));
create policy teacher_select on public.detected_mistakes    for select using (public.is_teacher_of(user_id));

-- Subscriptions: user reads own; only the webhook (service role) writes.
alter table public.subscriptions enable row level security;
create policy own_select on public.subscriptions for select using (user_id = auth.uid());

-- Teacher links: teacher invites, student accepts/revokes.
alter table public.teacher_students enable row level security;
create policy party_select on public.teacher_students for select
  using (teacher_id = auth.uid() or student_id = auth.uid());
create policy teacher_invite on public.teacher_students for insert
  with check (teacher_id = auth.uid() and status = 'invited'
              and exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.is_teacher));
create policy student_respond on public.teacher_students for update
  using (student_id = auth.uid()) with check (student_id = auth.uid());

alter table public.data_requests enable row level security;
create policy own_select on public.data_requests for select using (user_id = auth.uid());
create policy own_insert on public.data_requests for insert with check (user_id = auth.uid());

-- Catalogue tables: read-only for clients.
alter table public.tajweed_lessons enable row level security;
create policy published_read on public.tajweed_lessons for select using (is_published);
alter table public.achievements enable row level security;
create policy read_all on public.achievements for select using (true);
alter table public.user_achievements enable row level security;
create policy own_select on public.user_achievements for select using (user_id = auth.uid());

grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant select on public.tajweed_lessons, public.achievements to anon;
