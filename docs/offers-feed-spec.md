# Offers feed data contract

This is the data contract for `offers.json`, the public NBN/mobile
plan catalog consumed by the PriceMinder Flutter app. Anything
producing this file (scrapers, manual edits, other tooling) must match
this exactly, or entries will be silently dropped or fail to match
correctly inside the app.

## Hosting

- A plain **JSON array** (not wrapped in an object).
- Currently fetched from `jeevanshah/au-plans-scraper`'s `data/deals.json`
  via jsDelivr's GitHub CDN:
  `https://cdn.jsdelivr.net/gh/jeevanshah/au-plans-scraper@main/data/deals.json`
  (hardcoded in `app_library_ledger/lib/services/offers_service.dart`).
  Previously hosted as `offers.json` at the root of
  `jeevanshah/app-library-ledger` — kept here for history, no longer live.
- The app caches this for 12 hours; there's no other invalidation
  mechanism, so don't expect same-minute freshness on the client side.

## Scope

- **NBN and mobile plans only.** Nothing else is parsed/displayed.
- **Australia only, AUD only.** There is no currency field — all
  prices are assumed AUD.

## Required fields (per offer object)

| Field | Type | Notes |
|---|---|---|
| `id` | string | Unique slug, e.g. `"flip-nbn25-2026-07"` |
| `provider` | string | e.g. `"Flip"` |
| `title` | string | e.g. `"Premium NBN 25 BYO"` |
| `category` | string | Must be one of the app's fixed category list. **Every current real entry uses `"Utilities"`** — use that unless you have a specific reason not to. |
| `promoPrice` | number | The discounted/current price |
| `regularPrice` | number | The post-promo price the plan reverts to |
| `promoMonths` | integer | How many months the promo price lasts (clamped 0–12 by the app) |
| `url` | string | Link to the offer |

## Optional-but-important fields

| Field | Type | Notes |
|---|---|---|
| `validUntil` | ISO date string, or `null` | Optional as of the current scraper (`au-plans-scraper`) — many real provider pages don't state an explicit calendar end-date for a plan. `null`/omitted means "no known expiry," not "invalid." If a date IS given, it must be parseable **and** in the future — an already-expired `validUntil` still gets the offer dropped silently. |

## Optional fields

| Field | Type | Notes |
|---|---|---|
| `minCurrentSpend` | number | Only surface this offer to users spending at least this much |
| `speedTier` | string | Legacy/free-text speed field |
| `postedAt` | ISO date string | Drives a "New" badge for entries posted within the last 7 days |
| `serviceType` | `"nbn"` \| `"mobile"` | Omit/null if neither |
| `tier` | string | See exact string conventions below — **must match byte-for-byte** |
| `dataGB` | number | Mobile data allowance; not applicable to NBN |
| `techType` | string | e.g. `"Fibre"`, `"Fibre and FTTN"`, `"Optus 5G"`, `"Vodafone 5G"` |
| `_source` | string | Free-text provenance note (e.g. `"Canstar, verified 2026-07-09"`) — the app ignores this field entirely, but keep it for human traceability |

## Hard validation (enforced client-side, entries failing this vanish silently)

`SavingsOffer.fromJson` in `app_library_ledger/lib/models/offer.dart`
throws away any entry that fails these checks — there is no error
surfaced to the user, the offer just doesn't appear:

- `validUntil`, if present, must parse as a valid date **and be in the
  future** relative to when the app fetches the feed. **Never publish
  an already-expired offer.** Omit or send `null` if there's no known
  expiry — don't invent a date.
- `category` must be in the app's fixed allow-list (currently: `Media
  / Streaming`, `Productivity`, `Utilities`, `Shopping`, `Health /
  Fitness`, `Social`, `Education`, `Gaming`).
- `regularPrice` must be present.
- `id` must be present.

## Tier strings — now bucketed client-side, no longer byte-for-byte

Earlier versions of this doc required `tier` to exactly match one of
4 fixed strings per segment (`"NBN 25"`, `"<20GB"`, etc.), matched
byte-for-byte in the app. **That's no longer required.** The current
scraper (`au-plans-scraper`) produces much more granular, realistic
tier strings — e.g. `"NBN 100/20"`, `"NBN 25/8.5"`, `"7GB"`,
`"295GB"` — and the app now buckets these itself via
`SavingsOffer.tierBucket` (`app_library_ledger/lib/models/offer.dart`)
before using them for matching/filtering/grouping. The raw `tier`
value is still shown verbatim in the UI (offer cards, detail sheet)
for precision — only the *matching* logic buckets it.

- Send whatever real tier string the provider actually publishes —
  don't pre-bucket or invent a fake 4-value tier on the scraper side.
- The bucketing rule (NBN): extract the first number in the string
  (the download speed) → ≤37 buckets to `"NBN 25"`, ≤75 to `"NBN 50"`,
  ≤300 to `"NBN 100"`, anything higher (500/700/1000/2000+) buckets to
  `"NBN 500"` (i.e. "500 and up" is one bucket for matching purposes,
  even though the raw tier shown to the user is still precise).
- The bucketing rule (mobile): `"Unlimited"` stays as-is; otherwise
  extract the GB number → `<20` buckets to `"<20GB"`, `20–59` to
  `"20–60GB"`, `60+` to `"60GB+"`.
- If a provider ever publishes a tier string with no parseable number
  in it, `tierBucket` returns `null` for that offer — it still
  displays fine, it just won't participate in tier-filtered
  views/matching. Not a hard validation failure, the offer isn't
  dropped.

## Content tone

The app's UI is built around neutral, non-promotional data display —
no "best deal" badges, no recommendation language, no opinionated
ranking. `title`/`description` text is shown close to verbatim, so
avoid promotional copy ("BEST DEAL!", "Don't miss out!") in scraped
text fields — plain factual plan descriptions only.

## Example entry

```json
{
  "id": "flip-nbn25-2026-07",
  "provider": "Flip",
  "title": "Premium NBN 25 BYO",
  "category": "Utilities",
  "description": "Affordable NBN 25 with a 6-month discount for new customers. Unlimited data, no lock-in, BYO modem.",
  "promoPrice": 48.00,
  "regularPrice": 65.90,
  "promoMonths": 6,
  "validUntil": "2026-08-31",
  "url": "https://www.flip.com.au/nbn",
  "serviceType": "nbn",
  "tier": "NBN 25",
  "techType": "Fibre and FTTN",
  "postedAt": "2026-07-09",
  "_source": "Canstar, verified 2026-07-09"
}
```
