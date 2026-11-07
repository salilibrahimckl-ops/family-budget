# FITVERSE

Premium AI-powered fitness, nutrition and social community app for **Android** (APK) and **iPhone** (installable web app).

## What's inside
| Area | Status |
|---|---|
| Onboarding, email sign-up/sign-in, password reset | ✅ Works on-device; email recovery + Google/Apple via Supabase (needs your keys) |
| Dashboard (calorie/macro rings, water, weight, today's workout, week chart, community) | ✅ |
| Exercise library — 100 exercises, 13 muscle groups, full coaching cues, muscle map, gym ⇄ home switch by equipment level, filters | ✅ (no videos bundled — admin can attach licensed video URLs) |
| Programmes (Beginner, PPL, Upper/Lower, Full body, Home, Fat-loss, Muscle-building) + weekly calendar | ✅ |
| Workout logger — sets/reps/weight, rest timer, workout timer, PR detection (Epley 1RM), history, custom routines | ✅ |
| BMI (WHO + Asian-Indian cut-offs), healthy range, weight graph, body measurements | ✅ |
| Mifflin-St Jeor BMR → TDEE → goal-adjusted calories, protein, carbs, fat, fibre, water | ✅ |
| Food tracker — 113 foods incl. Kerala dishes, servings/grams, favourites, custom foods, natural-language entry with clarification, barcode (Open Food Facts) | ✅ |
| Water tracker — one-tap amounts, custom, weekly/monthly stats, streak, reminders | ✅ |
| AI coach — on-device coach using your data; optional cloud LLM via Supabase Edge Function | ✅ / needs API key |
| Community — posts (photo/video/workout/transformation/tip), likes, comments + replies, mentions, share, bookmarks, follow, private accounts & requests, report, block, notifications | ✅ on-device; real multi-user needs Supabase |
| Challenges, optional leaderboards, badges | ✅ |
| Admin dashboard — exercises, videos, alternatives, foods, moderation, users, challenges, analytics | ✅ |
| Premium architecture (free preview; billing not connected) | ✅ |
| Dark/light theme, metric/imperial, i18n with Malayalam beta | ✅ |

## Run / build
```bash
npm install
npm run build            # bundles src/ → www/index.html
npx cap add android      # first time only
npx cap sync android && python3 scripts/patch-android.py
cd android && ./gradlew assembleDebug   # → app/build/outputs/apk/debug/app-debug.apk
```
CI: pushing to the `fitverse` branch runs `.github/workflows/fitverse-android.yml` and publishes `FITVERSE.apk` to the `fitverse-builds` branch.

## Cloud setup (optional — multi-device sync, real social network, Google/Apple sign-in, email reset, cloud AI)
1. Create a project at supabase.com → SQL Editor → run `supabase/schema.sql`.
2. Deploy functions: `supabase functions deploy coach` and `supabase functions deploy delete-account`; set `supabase secrets set ANTHROPIC_API_KEY=...`.
3. Authentication → Providers: enable Google (Google Cloud OAuth client) / Apple (Apple Developer account). Add redirect URL `com.fitverse.app://auth-callback` and your web URL.
4. In the app: Profile → Settings → Cloud → paste Project URL + **anon** key. Sign out, then create a cloud account.
5. Make yourself admin: `update profiles set is_admin = true where username = 'you';`

Only the anon key goes in the app. Service-role and AI keys live only in Supabase secrets.

## Paid / external services
- Supabase (free tier is enough to start) · Anthropic API for cloud coach (pay per use) · Google Play Console ($25 one-time) · Apple Developer Program ($99/yr, needed for an iPhone App Store build and Apple sign-in) · Open Food Facts (free).

## Known limits
- On-device mode stores one profile per phone; social features are local until Supabase is connected.
- No exercise videos are bundled: only licensed media should be attached (Admin → Exercises → video URL).
- The APK is debug-signed for side-loading. For Play Store, create an upload keystore and run `./gradlew bundleRelease`.
