# App Ledger — Flutter Handoff Pack (text-only, no images needed)

This folder is a complete, image-free build spec for the App Ledger redesign.
Every value (color, size, radius, padding, copy, sample data, animation) is written
out so a text-only code model (DeepSeek, etc.) or a developer can build it directly.

## How to use with DeepSeek
1. ALWAYS paste `00_shared_tokens.md` first — it defines colors, type, spacing, the
   shared components, and the canonical sample data every screen reuses.
2. Then paste ONE screen spec and prompt:
   "Build this exact Flutter screen (Flutter 3.9+, Material 3, dark). Match every
    value in the spec. Use the shared tokens I gave you. Return a single
    self-contained widget file."
3. Use each spec's ACCEPTANCE checklist as QA. For any failing line, paste it back
   and ask it to fix only that.

Do screens ONE AT A TIME — text models produce far better Flutter per-screen than
when asked for the whole app at once.

## Files (suggested build order)
- 00_shared_tokens.md ............ tokens + shared components + sample data (READ FIRST)
- splash_screen_flutter_spec.md .. 2s animated splash (purple gradient)
- onboarding_screen_flutter_spec.md 4 swipeable pages, per-page accent
- library_screen_flutter_spec.md . MAIN screen: summary banner + list + chips + FAB
- dashboard_screen_flutter_spec.md metrics grid + donut + health ring + insights
- add_edit_screen_flutter_spec.md  quick-add + conditional form + save
- categories_screen_flutter_spec.md reorderable categories + color picker

## Packages referenced
google_fonts, intl, fl_chart, animations (page transitions), confetti (optional),
plus your existing: shared_preferences, flutter_local_notifications,
google_mobile_ads, in_app_purchase, share_plus, path_provider, url_launcher.

## Consistency notes
- Monthly total is $147.43 across ALL screens (sum of the 8 sample subs). Category
  totals in Dashboard + Categories reconcile to it exactly.
- Two fonts only: Space Grotesk (numbers/titles) + Plus Jakarta Sans (everything else).
- The app is dark-first (screenBg #0B0B11). Splash is the one bright purple screen;
  onboarding is dark with per-page accent glows.

## Reference mock
The interactive Library mock (matches library_screen_flutter_spec.md) lives at
../Library.dc.html — open it in a browser to see the target look in motion.
