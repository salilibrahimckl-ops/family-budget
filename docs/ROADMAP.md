# Roadmap and task status

Updated 2026-11-10. "Tested" = a test was run here and passed. "Written" = code exists but has not
been compiled yet (the Flutter SDK can't run in the build workspace; run `flutter test` on the Mac).

## Done
| Phase | Item | Status |
| --- | --- | --- |
| 1 | Schema, immutability, RLS, account-deletion cascade | Tested (29 checks) |
| 1 | Tanzil import tool | Tested (10 unit tests) |
| 4 | Real Tanzil Uthmani 1.1 imported: 6,236 Ayahs, 112 Basmalas, 77,433 words | Tested in Postgres; Juz/page boundaries checked |
| 4 | App assets + startup verification (hash of every Ayah and Basmala) | Hash cross-checked in Python; Dart test written |
| 2 | Design system, light/dark, RTL, Malayalam typography, 5-tab navigation | Written |
| 2 | Assessment + plan, settings | Written (3 widget tests) |
| 3 | Email-code sign-in, profile/preferences sync | Written |
| 3 | Sync: append-only events, newest-review-wins per Ayah | Written |
| 3 | Account deletion + data export (Edge Functions) | Written |
| 5 | Quran reader (Surah list, Surah view, Basmala, status per Ayah) | Written |
| 6 | 7-step lesson with mastery threshold (90%) and retry loop | Written |
| 6–7 | Spaced-repetition engine, daily queue, backlog throttle, learning order | Written (13 unit tests) |
| 7 | Revision queue + review session | Written |
| 8 | XP rules (no grinding), streak + freeze days, levels, daily missions | Written (8 unit tests) |
| 8 | Challenges: daily, missing words, complete, random Surah, connect, recovery, full Surah | Written |
| 12 | Offline: everything works without internet; local SQLite | Written |

## Waiting on you
- [ ] `flutter test` on the Mac (send me any errors)
- [ ] Supabase: Project URL + anon key; run migration + 33 seed files (I can do this in your browser)
- [ ] Reciter audio licence (unblocks Listen step, audio player, Continue Reciting challenge)
- [ ] Malayalam + English translation licence (unblocks Understand step)
- [ ] Native review of Malayalam and Arabic interface text
- [ ] Fonts (KFGQPC Hafs licence check; Noto Sans Malayalam)

## Next
| Phase | Scope |
| --- | --- |
| 5 | Audio player (just_audio): Ayah playback, speed, repeat counts, word highlight from QUL timings, offline download |
| 8 | Quran journey map; achievements/badges screen |
| 9 | Recording with consent, upload, word-level checking via Quran-tuned speech model (Edge Function), feedback screen |
| 10 | Tajweed assessment — only after validation with a qualified teacher |
| 11 | Tajweed Academy content (reviewed), full string review |
| 13 | Progress analytics, RevenueCat subscriptions, Premium screen |
| 14 | Release: privacy policy, store listings, device matrix testing |
