import '../models/app_model.dart';
import '../models/offer.dart';

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
      ? sameService.where((o) => o.tier == tier)
      : sameService;
  final pool = tiered.isNotEmpty ? tiered : sameService;
  return pool.where((o) => o.promoPrice < comparePrice).length;
}

String serviceLabel(String serviceType) =>
    serviceType == 'mobile' ? 'mobile' : 'NBN';
