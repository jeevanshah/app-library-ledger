import '../models/app_model.dart';

enum DiscoveryType { appScan, webManual }

class PricingTier {
  final String tierName;
  final double monthlyPrice;
  final String currency;

  const PricingTier({
    required this.tierName,
    required this.monthlyPrice,
    this.currency = 'USD',
  });

  factory PricingTier.fromJson(Map<String, dynamic> json) => PricingTier(
    tierName: json['tierName'] as String? ?? '',
    monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 0.0,
    currency: json['currency'] as String? ?? 'USD',
  );
}

class CatalogEntry {
  final String id;
  final String name;
  final String? packageName;
  final String category;
  final DiscoveryType discoveryType;
  final List<PricingTier> pricingTiers;
  final String? domain;

  const CatalogEntry({
    required this.id,
    required this.name,
    this.packageName,
    required this.category,
    required this.discoveryType,
    this.pricingTiers = const [],
    this.domain,
  });

  factory CatalogEntry.fromJson(Map<String, dynamic> json) {
    final rawType = json['discoveryType'] as String? ?? '';
    final discoveryType = rawType == 'app_scan'
        ? DiscoveryType.appScan
        : rawType == 'web_manual'
        ? DiscoveryType.webManual
        : null;

    if (discoveryType == null) {
      throw FormatException('Unknown discoveryType: $rawType');
    }

    return CatalogEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      packageName: json['packageName'] as String?,
      category: json['category'] as String,
      discoveryType: discoveryType,
      pricingTiers:
          (json['pricingTiers'] as List<dynamic>?)
              ?.map((e) => PricingTier.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      domain: json['domain'] as String?,
    );
  }

  /// Creates an [AppEntry] from this catalog entry.
  AppEntry toAppEntry({String? appStoreLink}) => AppEntry(
    name: name,
    appStoreLink: appStoreLink ?? _deriveAppStoreLink(),
    category: category,
    packageName: packageName,
    isActiveSubscription: false,
  );

  String _deriveAppStoreLink() {
    if (packageName != null) {
      return 'https://play.google.com/store/apps/details?id=$packageName';
    }
    return 'https://apps.apple.com/app/${name.toLowerCase().replaceAll(' ', '-')}';
  }
}
