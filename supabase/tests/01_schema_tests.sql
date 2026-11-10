-- Schema tests. Run with: supabase/tests/run.sh
-- MOCK DATA: the "Quran" rows below are Latin placeholders (MOCK-...), not Quranic text.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.expect_error(sql text, label text) returns void
language plpgsql as $$
begin
  begin
    execute sql;
  exception when others then
    raise notice 'PASS  %  (blocked: %)', label, sqlerrm;
    return;
  end;
  raise exception 'FAIL  % — statement succeeded but should have been blocked', label;
end $$;

create or replace function pg_temp.ok(cond boolean, label text) returns void
language plpgsql as $$
begin
  if cond then raise notice 'PASS  %', label; else raise exception 'FAIL  %', label; end if;
end $$;

-- 1. Quran import guard --------------------------------------------------------
select pg_temp.expect_error($$insert into quran.surahs(id,name_arabic,name_transliterated,name_en,revelation_place,ayah_count,source_id) values (1,'x','x','x','makkah',7,1)$$,
  'insert into quran.surahs outside an import session');

begin;
set local app.quran_import = 'on';
insert into quran.sources(id,kind,name,url,version,license,file_sha256)
  values (1,'text','MOCK source','https://example.invalid','test','test only',repeat('a',64));
insert into quran.surahs(id,name_arabic,name_transliterated,name_en,revelation_place,ayah_count,source_id) values (1,'MOCK','Mock','Mock','makkah',3,1);
insert into quran.ayahs(id,surah_id,ayah_number,text_uthmani,text_sha256,juz,page,source_id)
select n, 1, n, 'MOCK-AYAH-'||n, encode(digest('MOCK-AYAH-'||n,'sha256'),'hex'), 1, 1, 1
from generate_series(1,3) n;
insert into quran.words(id,ayah_id,position,text_uthmani,source_id)
select a*1000+p, a, p, 'MOCK-W'||a||'-'||p, 1 from generate_series(1,3) a, generate_series(1,2) p;
commit;
select pg_temp.ok((select count(*) from quran.ayahs) = 3, 'import session inserts 3 mock Ayahs');

begin; set local app.quran_import = 'on';
select pg_temp.expect_error($$insert into quran.ayahs(id,surah_id,ayah_number,text_uthmani,text_sha256,source_id)
  values (4,1,4,'MOCK-AYAH-4',repeat('0',64),1)$$, 'Ayah with wrong SHA-256 rejected even during import');
select pg_temp.expect_error($$insert into quran.words(id,ayah_id,position,text_uthmani,source_id)
  values (9999,1,3,'MOCK',1)$$, 'word id must equal ayah_id*1000+position');
commit;

-- 2. Immutability, even for the database superuser ---------------------------
select pg_temp.expect_error($$update quran.ayahs set text_uthmani = 'changed' where id = 1$$, 'UPDATE Ayah text (superuser)');
select pg_temp.expect_error($$delete from quran.ayahs where id = 1$$, 'DELETE Ayah (superuser)');
select pg_temp.expect_error($$truncate quran.words cascade$$, 'TRUNCATE words (superuser)');
begin; set local app.quran_import = 'on';
select pg_temp.expect_error($$update quran.words set text_uthmani = 'x' where id = 1001$$, 'UPDATE word inside import session');
commit;

-- 3. Users + RLS -------------------------------------------------------------
insert into auth.users(id,email) values
  ('00000000-0000-0000-0000-00000000000a','a@test'),
  ('00000000-0000-0000-0000-00000000000b','b@test'),
  ('00000000-0000-0000-0000-00000000000c','teacher@test');
insert into public.profiles(user_id,display_name,is_teacher) values
  ('00000000-0000-0000-0000-00000000000a','A',false),
  ('00000000-0000-0000-0000-00000000000b','B',false),
  ('00000000-0000-0000-0000-00000000000c','T',true);
insert into public.memorisation_records(user_id,ayah_id,status,due_at) values
  ('00000000-0000-0000-0000-00000000000a',1,'learning',now()),
  ('00000000-0000-0000-0000-00000000000b',1,'learning',now());

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select pg_temp.ok((select count(*) from public.memorisation_records) = 1, 'user A sees only own memorisation rows');
select pg_temp.ok((select count(*) from quran.ayahs) = 3, 'authenticated user can read Quran content');
select pg_temp.expect_error($$insert into public.memorisation_records(user_id,ayah_id)
  values ('00000000-0000-0000-0000-00000000000b',2)$$, 'user A cannot write user B rows');
select pg_temp.expect_error($$insert into quran.ayahs(id,surah_id,ayah_number,text_uthmani,text_sha256,source_id)
  values (5,1,5,'x','x',1)$$, 'client cannot insert Quran content');
select pg_temp.ok((select count(*) from public.revision_queue) = 1, 'revision_queue respects RLS (security_invoker)');

-- 4. Append-only events + XP de-duplication ---------------------------------
insert into public.recitation_attempts(id,user_id,ayah_from,ayah_to,mode,method,passed,device_id,occurred_at)
values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a',1,1,'lesson_recall','self_report',true,'phone-1',now());
update public.recitation_attempts set passed = false where id = '10000000-0000-0000-0000-000000000001';
select pg_temp.ok((select passed from public.recitation_attempts) , 'client UPDATE of an attempt changes nothing (no policy)');
reset role;
select pg_temp.expect_error($$update public.recitation_attempts set passed = false
  where id = '10000000-0000-0000-0000-000000000001'$$, 'attempts append-only even for superuser (trigger)');
set role authenticated;
delete from public.recitation_attempts where id = '10000000-0000-0000-0000-000000000001';
select pg_temp.ok((select count(*) from public.recitation_attempts) = 1, 'user cannot delete own attempt history');
select pg_temp.expect_error($$insert into public.recitation_attempts(id,user_id,ayah_from,ayah_to,mode,method,passed,device_id,occurred_at)
  values (gen_random_uuid(),'00000000-0000-0000-0000-00000000000a',1,1,'revision','asr_word',true,'p',now())$$,
  'ASR-assessed attempt must carry a confidence value');
insert into public.xp_transactions(id,user_id,amount,reason,ref_attempt,occurred_at)
values (gen_random_uuid(),'00000000-0000-0000-0000-00000000000a',10,'new_ayah','10000000-0000-0000-0000-000000000001',now());
select pg_temp.expect_error($$insert into public.xp_transactions(id,user_id,amount,reason,ref_attempt,occurred_at)
  values (gen_random_uuid(),'00000000-0000-0000-0000-00000000000a',10,'new_ayah','10000000-0000-0000-0000-000000000001',now())$$,
  'same XP award replayed from a second device is rejected');

-- 5. Mastery integrity ---------------------------------------------------------
select pg_temp.expect_error($$update public.memorisation_records set status = 'strong', successes = 1
  where ayah_id = 1$$, 'Ayah cannot be "strong" after one success');
update public.memorisation_records set status='strong', successes=4, consecutive_passes=3 where ayah_id = 1;
select pg_temp.ok((select status from public.memorisation_records where ayah_id=1) = 'strong', 'strong allowed with 4 successes / 3 consecutive');

-- 6. Teacher access only after the student accepts --------------------------
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
insert into public.teacher_students(teacher_id,student_id) values
  ('00000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-00000000000a');
select pg_temp.ok((select count(*) from public.memorisation_records) = 0, 'teacher sees nothing before acceptance');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select pg_temp.expect_error($$insert into public.teacher_students(teacher_id,student_id)
  values ('00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000a')$$, 'non-teacher cannot create teacher link');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
update public.teacher_students set status = 'accepted' where student_id = auth.uid();
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select pg_temp.ok((select count(*) from public.memorisation_records) = 1, 'teacher sees accepted student only (1 row, not B)');

-- 7. Anonymous access ---------------------------------------------------------
reset request.jwt.claim.sub;
set role anon;
select pg_temp.ok((select count(*) from quran.ayahs) = 3, 'anonymous user can read Quran text (free plan)');
select pg_temp.expect_error($$select * from public.memorisation_records$$, 'anonymous user cannot read progress');
reset role;

-- 8. Content review gate -----------------------------------------------------
select pg_temp.expect_error($$insert into public.tajweed_lessons(slug,level,sort_order,title_en,title_ml,body_en,body_ml,is_published)
  values ('ghunnah','beginner',1,'t','t','b','b',true)$$, 'Tajweed lesson cannot be published without a named reviewer');

-- 9. Account deletion removes all personal data ----------------------------
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.ok(
  (select count(*) from public.memorisation_records where user_id='00000000-0000-0000-0000-00000000000a') = 0
  and (select count(*) from public.recitation_attempts where user_id='00000000-0000-0000-0000-00000000000a') = 0
  and (select count(*) from public.xp_transactions where user_id='00000000-0000-0000-0000-00000000000a') = 0
  and (select count(*) from public.teacher_students where student_id='00000000-0000-0000-0000-00000000000a') = 0,
  'deleting the account cascades through progress, attempts, XP and teacher links');
select pg_temp.ok((select count(*) from quran.ayahs) = 3, 'Quran content untouched by account deletion');

\echo ALL SCHEMA TESTS PASSED
