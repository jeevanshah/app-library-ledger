# offers.json — hosting & maintenance

This folder is NOT part of the app build. Push `offers.json` to a separate
public GitHub repo with Pages enabled, then set `offersUrl` in
`lib/services/offers_service.dart` to:

    https://<username>.github.io/<repo>/offers.json

## Weekly maintenance checklist

1. Open each offer's `url` and confirm the promo price, duration, and
   post-promo price are still correct on the provider's own page.
2. Update or remove anything that changed. Never leave a stale price —
   the app hides expired offers automatically, but a wrong live price is
   worse than a missing offer.
3. `validUntil` rules:
   - Provider states an end date → use it exactly.
   - No stated end date → set ~30 days out and re-verify weekly.
4. `_source` is maintainer-only (the app ignores unknown fields) — note
   where you verified the offer and the date.
5. Validate before pushing: `python -m json.tool offers.json` must pass.

## Schema (must match lib/models/offer.dart)

id, provider, title, category (one of the app's 10 category names),
description, promoPrice, regularPrice (post-promo, required),
promoMonths, validUntil (ISO date, required), url,
minCurrentSpend (number or null).
