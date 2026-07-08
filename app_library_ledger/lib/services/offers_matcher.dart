import '../models/app_model.dart';
import '../models/offer.dart';
import 'analytics_service.dart';

class OffersMatcher {
  final AnalyticsService _analytics;

  OffersMatcher(this._analytics);

  /// Returns matched offers sorted by savingsOverPromo descending.
  /// Each offer must: category spend > 0, meet minCurrentSpend if set,
  /// and promoPrice < the category's average per-entry monthly cost.
  List<MatchedOffer> match(List<AppEntry> apps, List<SavingsOffer> offers) {
    final categoryCosts = _analytics.getCategoryMonthlyCosts(apps);
    final categoryCounts = <String, int>{};
    for (final a in apps.where((a) => a.isActiveSubscription)) {
      categoryCounts[a.category] = (categoryCounts[a.category] ?? 0) + 1;
    }

    final matched = <MatchedOffer>[];
    for (final o in offers) {
      final catSpend = categoryCosts[o.category] ?? 0;
      if (catSpend <= 0) continue;
      if (o.minCurrentSpend != null && catSpend < o.minCurrentSpend!) continue;

      final count = categoryCounts[o.category] ?? 1;
      final avgEntryCost = catSpend / count;
      if (o.promoPrice >= avgEntryCost) continue;

      final savings = (avgEntryCost - o.promoPrice) * o.promoMonths;
      matched.add(MatchedOffer(offer: o, savingsOverPromo: savings));
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
