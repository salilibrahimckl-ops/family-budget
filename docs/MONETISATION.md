# Monetisation
`settings.plan` ('free' | 'premium') gates: cloud AI coach, Muscle-Building programme, advanced analytics, premium videos.
To add billing: install a billing plugin (e.g. RevenueCat Capacitor SDK, which wraps Google Play Billing and Apple IAP), and on purchase
call a Supabase Edge Function that verifies the receipt and sets `profiles.plan = 'premium'` server-side (users cannot change `plan` themselves — enforced by the `guard_profile` trigger).
