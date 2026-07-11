# Offers feed data contract

This is the data contract for `offers.json`, the public NBN/mobile
plan catalog consumed by the PriceMinder Flutter app. Anything
producing this file (scrapers, manual edits, other tooling) must match
this exactly, or entries will be silently dropped or fail to match
correctly inside the app.

## Hosting

- A plain **JSON array** (not wrapped in an object) at the **repo
  root** of `jeevanshah/app-library-ledger`, branch `main`.
- Fetched by the app via GitHub raw:
  `https://raw.githubusercontent.com/jeevanshah/app-library-ledger/main/offers.json`
  (hardcoded in `app_library_ledger/lib/services/offers_service.dart`).
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
| `validUntil` | ISO date string | See hard validation below |
| `url` | string | Link to the offer |

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

- `validUntil` must parse as a valid date **and be in the future**
  relative to when the app fetches the feed. **Never publish an
  already-expired offer.**
- `category` must be in the app's fixed allow-list (currently: `Media
  / Streaming`, `Productivity`, `Utilities`, `Shopping`, `Health /
  Fitness`, `Social`, `Education`, `Gaming`).
- `regularPrice` must be present.
- `id` must be present.

## Exact tier string conventions

These strings drive tier-matching features in the app (a "your tier"
badge, filter chips). A mismatch doesn't error — it just silently
fails to match, which is a hard bug to notice. Use these exact
strings:

- **NBN**: `"NBN 25"`, `"NBN 50"`, `"NBN 100"`, `"NBN 500"`
- **Mobile**: `"<20GB"`, `"20–60GB"` (⚠️ **en dash, U+2013** — not a
  plain ASCII hyphen `-`), `"60GB+"`, `"Unlimited"`

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
