# Hifz Academy

Quran Hifz & Recitation Academy for Android and iOS. Flutter app + Supabase backend, offline-first.
Plan: "Hifz Academy — Architecture & MVP Plan" doc. Task status: `docs/ROADMAP.md`.

## What works now (v0.5)
- Verified Quran text (Tanzil Uthmani 1.1) bundled and re-checked at every start: 6,236 Ayahs, 112 Basmalas.
- Learning assessment and personal plan; English, Malayalam, Arabic (RTL).
- Quran reader by Surah, with memorisation status per Ayah.
- 7-step memorisation lesson (listen, understand, repeat, visual memory, recall, connect, mastery test).
- Spaced-repetition revision queue with backlog throttling.
- XP, streaks with freeze days, levels by memorised Ayahs, daily missions.
- 7 of 8 challenges (Continue Reciting needs licensed audio).
- Email-code sign-in, sync between phones, account deletion and data export (Supabase).

## Run it on your Mac
```
cd app
flutter create --org com.salil --project-name hifz_academy --platforms android,ios .
flutter pub get
flutter gen-l10n
flutter test
flutter run                                   # offline only
flutter run --dart-define-from-file=env.json  # with sign-in and sync
```
`env.json` (copy `env.example.json`, never commit it): your Supabase Project URL and anon key.

## Set up Supabase (once)
1. In the Supabase dashboard → SQL Editor, run `supabase/migrations/0001_init.sql`.
2. Run the files in `supabase/seed/` in order (01.sql … 33.sql). They load the verified Quran text and
   77,433 words; each file stops with an error if anything doesn't match its checksum.
3. Authentication → Email: keep "Confirm email" on. In Email Templates → Magic Link, include `{{ .Token }}`
   so the email contains the 6-digit code the app asks for.
4. Deploy the functions (needs the Supabase CLI): `supabase functions deploy delete-account export-data`.

## Folders
| Path | What |
| --- | --- |
| `app/` | Flutter app |
| `app/assets/quran/` | Verified Quran text produced by the import tool (do not edit) |
| `supabase/migrations/` | Postgres schema: immutability triggers, row-level security |
| `supabase/seed/` | Quran import split for the SQL editor |
| `supabase/functions/` | Account deletion and data export |
| `supabase/tests/` | Schema tests (`run.sh`), real-data checks (`02_real_import.sh`, `03_chunks.sh`) |
| `tools/quran_import/` | Verifies the Tanzil file and produces the assets and SQL |

## Updating the Quran text
Download Uthmani XML from https://tanzil.net/download and `quran-data.xml` from https://tanzil.net/docs/quran_metadata, then:
```
python3 -I tools/quran_import/import_tanzil.py --quran quran-uthmani.xml --meta quran-data.xml \
  --version "<version, date>" --pin-sha256 <sha256 of the file> --out build/quran
```
Copy `manifest.json`, `quran_text.json`, `surahs.json` to `app/assets/quran/` and record the hashes in `docs/DECISIONS.md`.

## Fonts
Quran: KFGQPC Uthmanic Script Hafs (King Fahd Complex; confirm licence for a paid app).
Malayalam: Noto Sans Malayalam (OFL). Put the `.ttf` files in `app/assets/fonts/` and uncomment `fonts:` in `app/pubspec.yaml`.
Until then the phone's own Arabic font is used; the text is still the verified text.

## Rules the code enforces
- Quran text enters only through the import tool; `QuranText` renders only `VerifiedAyah`.
- No AI generates or alters Quran text. Recall checks are self-reported until speech checking ships.
- Screens not built yet say so and name their phase.

## Attribution
Quran text: Tanzil Project, https://tanzil.net — CC BY 3.0, verbatim copies only.
