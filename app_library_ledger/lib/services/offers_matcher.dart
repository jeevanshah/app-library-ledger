import '../models/app_model.dart';
import '../models/offer.dart';
import 'offer_relevance.dart';

class OffersMatcher {
  /// Returns matched offers sorted by savingsOverPromo descending. Each
  /// match pairs one of the user's real tagged NBN/mobile subscriptions
  /// with an offer relevant to it (same serviceType/tier rule as
  /// [relevantOffers], the one the Offers screen and notifications use)
  /// that's cheaper than what that subscription actually costs — not a
  /// blanket category-spend average, which could count an offer as a
  /// "match" against unrelated bills that merely share a category label.
  List<MatchedOffer> match(List<AppEntry> apps, List<SavingsOffer> offers) {
    final matched = <MatchedOffer>[];
    for (final a in apps.where(
      (a) => a.isActiveSubscription && a.subscriptionCost != null,
    )) {
      final comparePrice = a.subscriptionCost!;
      for (final o in relevantOffers(a, offers)) {
        if (o.promoPrice >= comparePrice) continue;
        final savings = (comparePrice - o.promoPrice) * o.promoMonths;
        matched.add(MatchedOffer(offer: o, savingsOverPromo: savings));
      }
    }
    matched.sort((a, b) => b.savingsOverPromo.compareTo(a.savingsOverPromo));
    return matched;
  }
}

class MatchedOffer {
  final SavingsOffer offer;
  final double savingsOverPromo;

  const MatchedOffer({required this.offer, required this.savingsOverPromo});
}
