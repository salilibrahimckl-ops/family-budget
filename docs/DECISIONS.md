# Decision log

| # | Date | Decision | Why |
| --- | --- | --- | --- |
| 1 | 2026-11-08 | Supabase over Firebase | Relational data, DB-level immutability for Quran text, predictable cost, open source. Offline handled by local Drift DB. |
| 2 | 2026-11-08 | Tanzil Uthmani (Hafs, Medina Mushaf) as the Quran text | Rigorously verified; verbatim redistribution allowed with attribution. |
| 3 | 2026-11-08 | Stable ids: Ayah 1–6236; word = ayah_id × 1000 + position | Same ids on every device and import; never reused. |
| 4 | 2026-11-08 | Attempts and XP are append-only events | Two devices can't overwrite each other; replays are de-duplicated by unique keys. |
| 5 | 2026-11-08 | ASR outputs verified word ids only; it never produces Arabic text for display | Rules out AI-composed or altered verses by construction. |
| 6 | 2026-11-08 | Tajweed assessment off until validated | Requirement: ordinary ASR must not be presented as Tajweed evaluation. |
| 8 | 2026-11-10 | Words = space tokens containing a letter; pause marks are not words (77,433 words) | Same rule in importer, database and app, so word ids match everywhere. |
| 9 | 2026-11-10 | sqflite instead of Drift for the local database | No code generation step, fewer build problems. |
| 10 | 2026-11-10 | Recall is self-checked (learner marks missed words) until speech checking ships | Honest: stored as method 'self_report', never presented as automatic assessment. |
| 7 | 2026-11-08 | "Strong" status requires ≥4 successes and ≥3 consecutive passes (DB constraint) | Never treat an Ayah as memorised after one correct answer. |

## Pinned source hashes
| File | Version / date | SHA-256 |
| --- | --- | --- |
| quran-uthmani.xml | Tanzil Uthmani 1.1, downloaded 2026-11-10 | 8c5aeae20363a98f6963720d29fce040ca8b56a8e75f8b564c257fce7f6d0417 |
| quran-data.xml | Tanzil metadata 1.0, downloaded 2026-11-10 | 8867c1d88191472adec9db694b3cd9f135b1a2ef580574d32cf888dcb22c5c7a |
| Bundled content hash | 6236 Ayahs + 112 Basmalas | 79a6ff354e2ce0c6a63b00c80fd631e330204ad1524b92528eb43864fd8e0083 |
