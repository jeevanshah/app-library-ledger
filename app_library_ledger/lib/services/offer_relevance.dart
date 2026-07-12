import 'package:intl/intl.dart';
import '../models/app_model.dart';
import '../models/offer.dart';
import 'analytics_service.dart';

/// Counts offers matching [app]'s tagged service type/tier that are
/// cheaper than [comparePrice] (a monthly amount).
int countCheaperOffers(
  AppEntry app,
  List<SavingsOffer> offers,
  double comparePrice,
) {
  if (app.serviceType == null) return 0;
  final sameService = offers.where((o) => o.serviceType == app.serviceType);
  final tier = app.serviceTier;
  final tiered = tier != null
      ? sameService.where((o) => o.tierBucket == tier)
      : sameService;
  final pool = tiered.isNotEmpty ? tiered : sameService;
  return pool.where((o) => o.promoPrice < comparePrice).length;
}

String serviceLabel(String serviceType) =>
    serviceType == 'mobile' ? 'mobile' : 'NBN';

final _offerInsightFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

/// Builds a Dashboard insight per tagged NBN/mobile anchor subscription
/// that has cheaper matching offers available. Neutral wording only —
/// states a count, never "best"/"recommended" (see CLAUDE.md offers
/// neutrality rule).
List<SubscriptionInsight> buildOfferSavingsInsights(
  List<AppEntry> apps,
  List<SavingsOffer> offers,
  Map<String, int> dismissed,
) {
  if (offers.isEmpty) return const [];
  final result = <SubscriptionInsight>[];
  for (final a in apps.where(
    (a) =>
        a.isActiveSubscription &&
        a.serviceType != null &&
        a.subscriptionCost != null,
  )) {
    final count = countCheaperOffers(a, offers, a.subscriptionCost!);
    if (count == 0) continue;
    final id = 'offer_savings_${a.id}';
    final ts = dismissed[id];
    if (ts != null &&
        (DateTime.now().millisecondsSinceEpoch - ts) < (30 * 86400 * 1000)) {
      continue;
    }
    result.add(
      SubscriptionInsight(
        id: id,
        title: '$count ${serviceLabel(a.serviceType!)} offer(s) beat what you pay',
        message:
            'You pay ${_offerInsightFmt.format(a.subscriptionCost)}/mo for ${a.name} — check Offers to compare',
        type: InsightType.info,
        impactPerMonth: a.subscriptionCost!,
        entryId: a.id,
      ),
    );
  }
  return result;
}