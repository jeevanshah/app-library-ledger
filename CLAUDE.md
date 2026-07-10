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
- App theme tokens live in lib/theme/app_tokens.dart (screenBg
  #0B0B11, cardBg #14141C, gold #C8A96E, Plus Jakarta Sans body,
  Space Grotesk numbers + tabularFigures, Playfair Display heroes).
  Plain setState, no state-mgmt package, Navigator 1.0. Keep it so.
