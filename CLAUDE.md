# PriceMinder (working title) — project memory

App code lives in `app_library_ledger/` (Flutter, Android-first).
Owner: Jeevan (JRS). Claude acts as architect/reviewer; DeepSeek in
VSCode does bulk implementation from prompts Claude writes.

## Vision (Jeevan's own words, paraphrased)

Born from a real habit: "I change my internet or phone plan every 6
months for the promo price, but I forget to track when it ends." This
is NOT a generic subscription tracker — it is a memory for price
rises. Two halves that feed each other:

1. Track what you pay (subscriptions, bills), especially promotional
   prices and when they expire (the "promo cliff" / loyalty tax).
2. Show current market offers (NBN + mobile plans first, Australia
   only) so the user can compare against what they pay and decide
   THEMSELVES. We present data neutrally; we never push or recommend.

The unique position: the user's real spend lives on-device, the offer
catalog comes from the cloud, and the matching happens on the phone.
Nobody else has both sides privately.

## Hard lines (never violate)

- Personal/user data NEVER leaves the device. No accounts, no sync,
  no analytics on user data. Only the public offers catalog is
  fetched (anonymously). If a feature needs user data server-side,
  the feature is wrong.
- No QUERY_ALL_PACKAGES. Package detection uses an explicit <queries>
  allowlist that must stay 1:1 with app_scan entries in
  assets/catalog.json (18 packages as of writing).
- Offers UI stays neutral: no "best deal", no recommendation
  language, no reordering by our opinion, deltas shown as plain data.
  Post-promo price always visible (ACCC representative pricing).
- Every offer needs regularPrice + validUntil; expired offers are
  dropped at parse time. Stale prices are worse than no offers.

## Decisions log

- Brand: locked "PriceMinder" (2026-07). Verified no app/company
  collisions via web search. Still pending: IP Australia classes
  9/36/42, Play in-store search, domain registration
  (priceminder.app, priceminder.com.au). Rename is ONE deliberate
  pre-launch pass: app label, splash wordmark, listing, repo name
  (breaks the raw offersUrl — change together), package id
  com.example.* → e.g. au.com.priceminder.app (required by Play
  anyway). "Kelpie" kept in the drawer as a possible later rebrand.
- Offers focus: NBN + mobile plans ONLY for now. Streaming/gym/energy
  offers parked. Australia only. AUD everywhere.
- Headline comparison metric: first-year average =
  (promo*months + regular*(12-months))/12. Needs its one-time
  explainer in UI.
- AdMob banner: REMOVE (decided, may not be implemented yet).
  Monetization later = affiliate revenue + premium tier of power
  features (watches/alerts, profiles, advanced insights). Data
  export/backup must always be FREE — never charge for data safety.
- Affiliate policy (stance agreed in discussion): listing is
  merit-based; commission never determines inclusion or ordering.
  Affiliate links deferred until after launch + network approval
  (Commission Factory/Awin, Impact — AU).
- Offers hosting: GitHub raw (repo jeevanshah/app-library-ledger,
  branch main, offers.json at repo root) — deliberate choice over
  Supabase free tier (7-day inactivity pause + 5GB egress hard stop
  disqualify it). Revisit Supabase (Pro, not free) when postcode
  filtering / admin panel / offer analytics become real. Jeevan is
  interested in automation/legal scraping for offer freshness later:
  affiliate feeds + CDR public product data (energy) are the legal
  paths; never scrape comparison sites.
- Visual rebrand direction (locked 2026-08-13, core implemented same day
  — see status note below):
  moving from the current dark theme to a light UI (85-90% white/
  light surfaces). Text and flat UI icons use black (not navy —
  explicitly rejected). Gold (#C8A96E, existing brand color) is
  reserved for brand/identity moments only (logo, hero illustrations,
  splash) — never reused as a functional UI signal. Orange is the
  single CTA/action color app-wide. Green is strict semantic (savings,
  success, trust/privacy) — never decorative. Yellow is reserved for
  time-pressure states only (promo ending, reminders). Red stays
  expired/error only. Asset hierarchy: glossy 3D illustration reserved
  for hero/feature tier (app icon, onboarding, empty states, promo
  banners); actual in-app UI (nav, buttons, form fields, 20-24px
  icons) stays flat/line-style in the same palette. Logo: multi-color
  hourglass confirmed (orange cart / gold tag / green percent / red
  heart glyphs + gold coin stack) — a brand mark is exempt from the
  strict in-app semantic color rules (same convention as Google/eBay:
  colorful logo, disciplined single-purpose-color product UI), but it
  still needs a simplification pass before use as a launcher icon —
  every ChatGPT-generated render crams in 4 glyphs plus a coin pile,
  too much detail to read at 48-96px. Source mood-board images live in
  `app_library_ledger/newDesignsassets/` (ChatGPT-generated raster
  PNGs — mood-board reference only, not production assets: no vector
  source, inconsistent style/background per image). Both open items
  resolved 2026-08-13: (1) category palette audited against the
  semantic rules — Shopping (#F59E0B) was an exact hex duplicate of
  `warning`; Health/Fitness (#10B981) and Finance (#22C55E) were both
  green, colliding with "green = savings only"; Education (#EAB308)
  was yellow, colliding with "yellow = time-pressure only". All four
  recolored in lib/theme/app_tokens.dart (Shopping to fuchsia
  #C026D3, Health/Fitness to sky #0284C7, Finance to violet #5B21B6,
  Education to deep plum #701A75), validated with the dataviz skill's
  CVD checker (scripts/validate_palette.js). Finding worth
  remembering: 10 simultaneous categorical hues cannot be made
  pairwise colorblind-safe (the validator's all-pairs check caps
  reliably-distinct series at 3 — a hard mathematical ceiling, not a
  hex-picking failure); the pre-existing Notes/Productivity (indigo
  vs purple) and Utilities/Travel (cyan vs teal) pairs already failed
  this before any rebrand work. Mitigation already in place and
  sufficient: category color is never the sole identifier —
  library_screen.dart's spend pie chart and legend always pair the
  color swatch with the app name text (_spendLegendRow), which is
  exactly the relief channel the CVD floor requires. (2) hugeicons
  ^1.1.5 is already a pubspec dependency but was completely unused
  (zero call sites) — verified its free strokeRounded style (one
  consistent line-icon family, matching the "flat 24px" requirement)
  covers all 13 needed concepts (Home01-10, Calendar01-04,
  Search01/02, Settings01/02, Edit01-04/PencilEdit01-02, Add01/02/
  AddCircle, Tag01-02/DiscountTag01-02/SaleTag01-02,
  Notification01-03, Shield01-02/Lock/Security, Camera01-03/QrCode
  for the scan flow, Share01-08/CloudUpload for export,
  CloudSavingDone01-02/CloudUpload for backup) — no custom icon
  commissioning needed, just wire up the existing dependency.
- Rebrand implementation status (2026-08-13): core palette/theme
  swap is DONE. lib/theme/app_tokens.dart rewritten (light surfaces,
  black ink, gold left brand-only, brandStart/brandEnd/brandMid
  repointed to orange so every existing reference — buttons, nav,
  focus rings, chips — repainted without touching those call sites;
  semantic success/warning/danger/info tuned for light-surface
  contrast; shadows softened). lib/theme/app_theme.dart flipped so
  `lightTheme` is the real ThemeData (Brightness.light) and
  `darkTheme` falls back to it until real dark mode is designed;
  main.dart updated to match. Swept ~90 AppTokens.gold/goldLight/
  goldGradient call sites (it had become the de facto functional
  accent — selection states, progress spinners, CTA gradients,
  calendar "today", tier picker, filter chips) to brandStart/
  brandEnd/brandGradient across settings/library/offers/
  spend_history/discovery/calendar/add_app screens; splash_screen.dart
  intentionally left gold (the animated splash ring is a legitimate
  hero moment). Also found and fixed two more reserved-hue
  collisions the first pass missed: a 12-swatch custom-category
  color picker in categories_screen.dart and a 10-swatch one in
  add_app_screen.dart both still offered green/amber/red — and the
  add_app_screen one defaulted new categories to orange, which is
  now the reserved CTA color. And found 5 `showDatePicker`/
  `showTimePicker` call sites (add_app_screen, library_screen,
  settings_screen, calendar_screen, discovery_screen) hardcoding
  `ColorScheme.dark(...)` while passing light-theme color values —
  the brightness flag was wrong, not the colors; all switched to
  `ColorScheme.light(...)`. Verified via IDE diagnostics after every
  edit (no Flutter CLI available in this environment to run
  `flutter analyze`/build — treat that as still owed before shipping).
  Remaining, deliberately deferred: the Icon(Icons.*) → HugeIcon(icon:
  HugeIcons.*) sweep (43 unique icons, ~66 call sites across 11
  files) — Material's "rounded" icons already satisfy the flat/
  line-style UI-tier requirement, so this is a consistency
  nice-to-have, not a rule violation, and its scale warranted a
  separate pass rather than folding it into this one uncompiled.
- Rebrand verified live on Jeevan's physical phone (2026-08-13):
  Flutter SDK found at C:\flutter (not on PATH — invoke via full path
  or add it), Android SDK + a Pixel 3a emulator + the phone itself
  (SM S918B, `RFCW10THS1N`) all available via `flutter devices`.
  `flutter analyze` came back clean (zero errors). Found and fixed
  running live: (1) a RenderFlex overflow in offers_screen.dart's
  `_OfferCard` price row (offers_screen.dart:813) — the delta text
  ("$X more/less than yours") had no Flexible/ellipsis, overflowed
  for a long enough delta value; wrapped in Flexible+ellipsis.
  (2) screenBg tuned twice on feedback: a soft off-white read as
  "grey creamy" and was disliked, landed on pure #FFFFFF (cardBg
  already matched) with fieldBg cooled to a neutral gray #F3F4F6.
  (3) a low-opacity monetization_on_rounded icon watermark added to
  the dashboard's "MONTHLY TOTAL" stat card in library_screen.dart,
  matching an icon-placement idea from the newDesignsassets mood-
  board mockup — deliberately skipped the same treatment on the
  Subscriptions-tab scroll-collapsing spend header since it's
  actively height/padding-animated and riskier to modify blind.
  (4) Biggest find: a THIRD independent hardcoded category-color
  list existed — storage_service.dart's `_defaultCategories()` (the
  seed data for a fresh install) used old Material-palette hex
  values with the exact same reserved-hue collisions (Productivity
  green #4CAF50, Finance amber #FFC107, Health/Fitness red #F44336,
  Shopping orange #FF5722) independently of both AppTokens.categories
  and the two swatch pickers already fixed — this is what was
  actually visible on Jeevan's test device (category filter chips
  showing green/red dots) even though the token-driven row avatars
  already showed correct colors, because filter chips read
  `Category.color` (persisted) not `AppTokens.categoryColor(name)`
  (computed). Fixed by making `_defaultCategories()` hex-for-hex
  identical to AppTokens.categories, so the two paths can never
  disagree again. Caveat: this only fixes fresh installs — a device
  with categories already persisted (like the current test phone)
  keeps its old colors until the app is uninstalled/reinstalled or a
  migration is written; not yet decided which.
- Icon asset library extracted and wired in (2026-08-14): 3 new
  ChatGPT-generated collage images (docs/store-assets/screenshots/icons/)
  turned out to have genuine alpha transparency (not baked-in
  backgrounds like the earlier mood-board batch) — used Python/Pillow +
  scipy connected-component labeling to auto-crop each icon cleanly.
  Kept 30 flat dark/orange icon pairs (home, grid, tag, bell, calendar,
  shield-lock, search, settings, edit, scan-frame, export, cloud-sync,
  documents, chart, clock) in assets/images/icons/flat/, and 14 glossy
  hero illustrations (piggy bank, hourglass+coins, shield+lock+check,
  etc.) in assets/images/icons/illustrations/ — discarded ~25 decorative
  fragments (loose sparkles, single leaves, gradient blobs) as noise.
  Added `flatIcon()`/`heroIllustration()` helpers to app_tokens.dart
  (flatIcon uses ColorFiltered/BlendMode.srcIn so one asset can be tinted
  to any color rather than needing separate files per state). Wired into
  GlassBottomNav (replacing Material icons), onboarding (per-page
  illustration instead of the repeated logo), Settings rows, Add
  Subscription's scan buttons, and empty states. Added one bold bleed
  illustration behind the Library header (document_approved_check,
  Positioned top-right, Clip.none) — a matching one on the Dashboard
  header (piggybank_savings) was tried and reverted per feedback ("so
  random... not good looking") along with a whole decorative-icon
  experiment on the Monthly Total stat card (house → coin icon,
  repositioned twice, ultimately just removed — a plain Material icon
  couldn't match a real illustration's polish, not worth the fight).
- Real Dark Mode shipped (2026-08-14): the old pre-rebrand dark/gold
  design is restored as a genuine, switchable Dark Mode rather than
  deleted — light stays the default. Settings > Appearance has a
  Light/Dark/System picker (defaults to System, persisted via
  SharedPreferences). Architecture: AppTokens' color consts became
  `isDark`-gated getters (call-site-identical to consts, so none of the
  762 existing `AppTokens.x` references needed to change) with
  AppTheme.lightTheme/darkTheme built from literal hex directly (NOT the
  dynamic getters — MaterialApp evaluates both `theme:`/`darkTheme:` in
  the same frame, so routing both through one global flag would make
  whichever builds second win for both). Key decision: dark mode's
  brandStart/brandEnd (the CTA/nav-pill accent) resolve to gold, not the
  historical purple/indigo — gold is what actually painted the ~90
  former-`AppTokens.gold` call sites the rebrand renamed to `brandStart`,
  so gold is what makes dark mode look like the old screenshots again;
  the old purple is retired. Non-obvious bug hit and fixed: setting
  `AppTokens.isDark` in MaterialApp's `builder:` alone did nothing
  visible — already-mounted screens (Settings, Library) don't re-run
  build() just because a bare static flag changed elsewhere, only the
  widget that directly listens to the ValueNotifier (the picker itself)
  updated. Fixed by wrapping `builder`'s child in
  `KeyedSubtree(key: ValueKey(isDark), ...)`, forcing the whole app
  subtree to tear down and rebuild on brightness change. Also had to
  audit every `Colors.white`-on-`brandGradient` spot (nav pill, primary
  buttons, segmented toggles — 11 sites across 6 files) since white text
  is illegible on a light-gold background; fixed by reusing the
  `AppTokens.screenBg` pattern already proven correct elsewhere (white in
  light mode, near-black in dark — same trick, already used in 4 other
  buttons before this pass). Converting the const fields to getters also
  broke ~59 `const Widget(...)` call sites app-wide that captured them at
  compile time (`invalid_constant` errors) — fixed via 5 parallel
  subagents, one per file group, each removing only the specific `const`
  keyword that broke, verified via a clean `flutter analyze` afterward
  (back to the same 28 pre-existing warnings as baseline). Verified live
  on device both directions (Light→Dark and Dark→Light instant-switch,
  checked Library/Dashboard/Offers/Settings tabs in both modes).
  Restart-persistence relies on the same SharedPreferences pattern
  already used for offers sort-mode elsewhere in the app — not
  separately re-verified after a full app-kill this session.
- Native splash follow-up (2026-08-14, same dark-mode pass): the Android
  launch screen now matches the light-default theme.
  res/values/colors.xml `launch_background_color` is #FFFFFF (was
  #0B0B11), with a NEW res/values-night/colors.xml overriding it to
  #0B0B11 in system dark mode. Trap to remember: the native splash
  renders BEFORE the Flutter engine starts, so it only ever sees the
  OS-level system dark setting — the in-app Light/Dark/System override
  (SharedPreferences) is invisible to it. A user who sets Dark in-app on
  a light-OS phone still gets a white native flash at cold start before
  the Flutter dark splash takes over. Also finished the
  bleed-illustration motif on the ONE screen where it's safe:
  splash_screen.dart now has a bottom-right hourglass_coins hero bleed
  plus a smaller top-left one (the corners are empty there, unlike the
  Library/Dashboard header attempts).
- Category icons shipped (2026-08-15, built by DeepSeek, verified +
  completed by Claude after DeepSeek ran out of credits mid-task):
  each of the 10 categories in AppTokens.categories now carries a third
  `_CatDef` field, `icon` (e.g. 'health_fitness', 'notes_journaling'),
  and 10 matching full-colour PNGs live in
  assets/images/icons/categories/category_<icon>.png (registered in
  pubspec.yaml). New `categoryIcon(categoryName, {size})` helper in
  app_tokens.dart resolves name → icon file; unlike `flatIcon()` these
  ship pre-tinted in the category's own colour and are used as-is (no
  ColorFiltered). Wired into 4 spots across library_screen.dart /
  add_app_screen.dart (filter chips, list-row fallback avatar, category
  picker sheet, category chip row), each guarded with
  `AppTokens.categories.containsKey(...)` so an unrecognized/custom
  category name still falls back to the old plain dot — verified this
  fallback path is reachable and correct, not just present.
  Deliberately NOT wired into categories_screen.dart's color swatch
  (the 34x34 square with `onTap: onColorTap`) — that widget's job is
  specifically to preview/pick the raw color, so showing an icon there
  would obscure what tapping it does; this exclusion looks correct, not
  like something DeepSeek simply hadn't reached yet. Verified end to
  end on device: `flutter analyze` clean (same 28 baseline
  warnings, zero new issues), all 10 category icons render in both the
  Library filter-chip row and the Add Subscription category picker
  sheet with no red error-box fallback (categoryIcon's errorBuilder),
  confirming every asset path resolves correctly at runtime — analyze
    alone can't catch a bad asset path, only a real render can.
- Library Spend Card redesign (2026-08-15): redesigned the collapsing
  header price card on LibraryScreen to eliminate excessive whitespace
  and match the premium hero card mockup. The card integrates: (1) Top
  row with a 46x46 soft-tinted wallet/finance icon, "Monthly spend"
  label, gradient hero spend amount in Space Grotesk tabular figures,
  the glossy 3D piggy bank illustration (`piggybank_savings.png`), and
  a "View insights >" action chip linking to the Dashboard tab; (2)
  Bottom row with 3 rounded mini-metric cards (Active Subscriptions,
  Renew Soon in 7 days, and Potential Savings / Projected Annual Spend),
  replacing the previous disconnected floating pills; (3) Smooth
  scroll-collapse animation (174px down to 52px sticky bar) that fades
  out the mini-cards and retains one-tap insights navigation. Analyzed
  clean via `flutter analyze` (0 errors).
- Add/Edit Subscription Screen Redesign (2026-08-15): completely reimagined
  the Add and Edit Subscription experience (`add_app_screen.dart`) with:
  (1) Hero search field with live auto-match badge, logo preview, and clear icon;
  (2) Two prominent visual quick-action cards ("Scan bill" with OCR camera icon
  and "Scan phone" with device app detector icon); (3) "POPULAR SERVICES"
  compact 38px horizontal chip strip with 22px brand logos and quick pre-filling;
  (4) Same-line Billing Cycle (Monthly/Yearly) & Promo Deal toggle;
  (5) Multi-column compact cost grid (3-column common prices, 2-column plan tiers);
  (6) Custom-designed in-app Calendar Bottom Sheet Date Picker (`_CustomDatePickerSheet`)
  replacing generic Material date picker, featuring month navigation, 7-column
  tactile calendar grid with brand gradient active selection, and quick 1-tap presets
  (`Today`, `In 7 Days`, `+1 Month`, `+1 Year`);
  (7) Redesigned section cards with 3D/flat icon badges (Subscription Details,
  Pricing & Billing, Optional Notes); (8) Enhanced Category selector displaying
  authentic full-color category illustrations (`categoryIcon`);
  (9) High-contrast amber Promo Cliff warning card; (10) Floating sticky bottom
  bar with gradient "Save Subscription" CTA and haptic feedback. Verified clean via `flutter analyze`.
- Dashboard (Overview) Screen Redesign (2026-08-15): redesigned `_DashboardView`
  in `library_screen.dart` to elevate analytics, financial clarity, and visual appeal:
  (1) Overview Header with device-local privacy badge (`shield_lock_dark`) and 3D piggy bank;
  (2) Multi-metric Overview Hero Card with Space Grotesk gradient monthly commitment total,
  annualized projection badge, and 3 quick-metric pills (Active Apps, Avg / Sub, Annual Cost);
  (3) Enhanced Renewal Calendar Mini-Card with orange calendar badge, current month title,
  renewal count pill (`$N due`), and clean day-grid with color-coded renewal indicators;
  (4) Spending History Card with trending chart icon, transaction count subtitle, and direct
  drill-down to `SpendHistoryScreen`;
  (5) Modern Donut Chart with monthly total center label, category-colored segments, and
  Top Expense progress cards with visual `LinearProgressIndicator` budget bars and 3D category icons;
  (6) Savings Opportunities card with dynamic savings preview. Hot-restarted and verified clean on device.
- Spending History & Ledger Redesign (2026-08-15): modernized [`spend_history_screen.dart`](file:///c:/Users/Deep/Desktop/mobile-app/app_library_ledger/lib/screens/spend_history_screen.dart):
  (1) Hero Confirmed Spend card with gradient tabular typography and 3D finance icon badge;
  (2) Responsive Monthly Spend History with emerald "Paid" vs blue hollow "Est." legend and stacked horizontal progress bars;
  (3) Interactive Price Trajectory card with cubic bezier smooth curve graph, gradient area fill, glowing nodes, and amber cliff rise markers;
  (4) Price Changes Log with 3D icons, old-to-new price pills, and monthly delta badges;
  (5) Upcoming Charges card with date badges and tabular pricing. Hot-reloaded and verified clean on physical Galaxy S23 Ultra.
- Offers & Savings Overhaul (2026-08-15): redesigned [`offers_screen.dart`](file:///c:/Users/Deep/Desktop/mobile-app/app_library_ledger/lib/screens/offers_screen.dart):
  (1) Unified Full-Height Vertical Scrolling: removed nested `PageView` / `ListView.builder` viewport trap in favor of a unified `CustomScrollView` with `SliverPersistentHeader` sticky filter & sort bar; as user scrolls down, hero card smoothly scrolls away giving 100% of the screen height to browse plans;
  (2) Eliminated all RenderFlex overflows across `_OfferCard` (responsive price & delta pill wrapping, flexible provider titles, compact action button) and wrapped all bottom sheets in `SingleChildScrollView(physics: BouncingScrollPhysics())` with `isScrollControlled: true`;
  (3) Hero Header with verified plan count badge and on-device anonymous sync indicator;
  (4) Hero Savings Match Card featuring `piggybank_savings` 3D illustration, live monthly and annual savings calculation against user's active broadband/mobile plan, and 1-tap anchor config;
  (5) Fixed Mobile Plan Tagging & Tier Migration: segment-specific anchor isolation, invalid tier resetting (e.g. converting NBN tier to Mobile data bucket `<20GB`, `20–60GB`, `60GB+`, `Unlimited`), support for all subscriptions in tagging picker, and 1-tap "Untag Plan" action;
  (6) Modern capsule Segment Control (NBN Broadband vs Mobile SIM);
  (7) Redesigned `_OfferCard` with provider branding, 1st-year average price, emerald savings delta pills, promo breakdown, mini 12-month trajectory timeline, and gradient CTA button;
  (8) Comprehensive detail bottom sheet with full 12-month trajectory comparison table and direct provider link launcher. Hot-restarted and verified clean on Galaxy S23 Ultra.

## Roadmap / parking lot (agreed order)

1. Ship Offers 3.0 (neutral comparison browser: NBN|Mobile segments,
   anchor "you pay $X", tier filter chips, user-chosen sort,
   comparison bars with gold your-price tick, detail bottom sheet).
   STATUS: built (2026-07-09). Also added: inline tier picker card,
   "My tier" gold filter chip, gold CTA in detail sheet, "Ongoing"
   label for flat-price offers, Unicode minus in deltas.
2. Expanded offers.json: 7 NBN plans (tiers 25/50/100/500) + 6 mobile
   plans (data buckets <20GB to Unlimited), live-verified from Canstar
   & Finder (9 Jul 2026), enriched with serviceType/tier/dataGB/
   techType/postedAt. Target was ~20 total; 13 shipped as first batch.
   Streaming offers (Paramount+, Kayo) removed to keep NBN/Mobile focus.
3. Pre-launch: rename pass, AdMob removal, free export/import
   prominent, unit tests (storage, catalog parsing, avgFirstYear) +
   GitHub Actions analyze+test, validation script for offers.json
   (schema + expiry warnings), 15-20 person beta.
4. Post-launch: watches/price-drop alerts (on-device rule matching —
   biggest next feature), decision-moment notifications (promo end +
   offers combined), price history (git history of offers.json is
   already accumulating it), energy vertical via CDR data.

## Working agreements (learned the hard way this project)

- DeepSeek reports are unreliable: it has fabricated package names,
  claimed builds that couldn't compile, marked skipped work as done,
  and truncated large file writes mid-file. EVERY report gets
  verified against the actual files before trusting it. Prompts must
  demand per-item confirmation + "state the last line of <file>".
- Commit to git after every working session. The robocopy-flatten
  incident wiped the manifest/MainActivity and reintroduced bugs;
  git history was the recovery path.
- catalog.json ↔ AndroidManifest <queries> sync must be re-verified
  after ANY catalog change (a wrong package name fails silently
  forever). Verify package ids against real Play Store listings —
  never trust generated ones.
- App theme tokens live in lib/theme/app_tokens.dart as `isDark`-gated
  getters (call-site-identical to the old const fields, so the ~762
  `AppTokens.x` references never needed changing). Light is the default
  (screenBg #FFFFFF, fieldBg #F3F4F6, black ink #24242E, orange CTA
  brandStart #FF5A1F / brandEnd #FF8A50); dark restores the pre-rebrand
  palette (screenBg #0B0B11, cardBg #14141C) with brandStart/brandEnd
  resolving to gold #C8A96E/#DFC896. AppTheme.lightTheme/darkTheme are
  built from LITERAL hex, never the getters — MaterialApp evaluates both
  `theme:` and `darkTheme:` in the same frame, so routing both through
  the single `AppTokens.isDark` flag would make whichever builds second
  win for both. `AppTokens.isDark` is set in MaterialApp's `builder:`,
  and a `KeyedSubtree(key: ValueKey(isDark))` forces the whole subtree
  to rebuild on brightness change (already-mounted screens otherwise
  never re-read the getters). Plus Jakarta Sans body, Space Grotesk
  numbers + tabularFigures, Playfair Display heroes. Plain setState, no
  state-mgmt package, Navigator 1.0 — keep that structure. Gold is
  brand/identity-only (logo, hero illustrations, splash); the one
  functional reuse is dark mode's CTA accent via brandStart/brandEnd.
  Hardest remaining cleanup: onboarding/empty-state screens that
  hardcode Playfair + gold-gradient decisions directly rather than
  through tokens.
- docs/marketing-plan.md predates the rebrand: it still anchors the
  visual identity on "AppTokens.goldGradient" (gold-to-lightgold),
  which the rebrand demoted to brand-only with orange as the functional
  CTA. Re-review before generating store assets/screenshots.
