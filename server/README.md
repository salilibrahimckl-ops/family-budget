---
title: Hifz Academy Recitation Teacher
emoji: 🕌
colorFrom: green
colorTo: yellow
sdk: docker
app_port: 7860
pinned: false
license: other
short_description: Checks a recited Ayah for word, harakah and Tajweed mistakes
---

# Hifz Academy recitation teacher

The backend for "Recite to me" in Hifz Academy. `POST /check` with an audio file and
`sura`, `aya`; it returns every missed or wrong word and letter, wrong harakat, and Tajweed
mistakes (Madd lengths, Ghunnah, Qalqalah, Idgham), each located on a word of the verified
Uthmani text.

Built on [Quran Muaalem](https://github.com/obadx/quran-muaalem) (model
`obadx/muaalem-model-v3_2`), used under the Quran Muaalem License (QML) 1.0.

**AI advisory notice.** This Quranic Teacher is an artificial-intelligence model that may
make mistakes. It is intended for assistance only and must not be relied upon. It is not a
replacement for a proficient, authorized teacher, because the Quran is only received
through oral transmission (mushafahah).

هذا المعلّم القرآني نموذج ذكاء اصطناعي قد يخطئ؛ فهو للإعانة فقط ولا يُعتمد عليه، وليس بديلاً عن معلّمٍ مُتقِنٍ مُجاز؛ لأنّ القرآن لا يُؤخذ إلا بالمشافهة.

Audio is processed in memory and not stored.
