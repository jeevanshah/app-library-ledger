class SavingsOffer {
  final String id;
  final String provider;
  final String title;
  final String category;
  final String description;
  final double promoPrice;
  final double regularPrice;
  final int promoMonths;
  final DateTime? validUntil;
  final String url;
  final double? minCurrentSpend;
  final String? speedTier;
  final DateTime? postedAt;
  final String? serviceType; // "nbn", "mobile", or null
  final String? tier;        // e.g. "50", "25/10", "Unlimited"
  final num? dataGB;         // mobile data allowance
  final String? techType;    // e.g. "FTTP", "5G"

  const SavingsOffer({
    required this.id,
    required this.provider,
    required this.title,
    required this.category,
    required this.description,
    required this.promoPrice,
    required this.regularPrice,
    required this.promoMonths,
    this.validUntil,
    required this.url,
    this.minCurrentSpend,
    this.speedTier,
    this.postedAt,
    this.serviceType,
    this.tier,
    this.dataGB,
    this.techType,
  });

  /// Average monthly cost over 12 months: (promoMonths * promoPrice +
  /// (12 - promoMonths) * regularPrice) / 12, where promoMonths is
  /// clamped to 0..12.
  double get avgFirstYear {
    final pm = promoMonths.clamp(0, 12);
    final promoTotal = pm * promoPrice;
    final ongoing = (12 - pm) * regularPrice;
    return (promoTotal + ongoing) / 12;
  }

  /// Buckets this offer's raw `tier` into the app's fixed 4-tier-per-
  /// segment convention ("NBN 25/50/100/500", "<20GB/20–60GB/60GB+/
  /// Unlimited") for matching/filtering/grouping. Real-world feeds are
  /// far more granular than that (e.g. "NBN 100/20", "7GB") — `tier`
  /// itself is kept raw for precise display; use this getter anywhere
  /// tiers need to compare equal (tier picker, "your tier" matching,
  /// filter chips, per-tier grouping).
  String? get tierBucket {
    if (tier == null) return null;
    final digits = RegExp(r'\d+').firstMatch(tier!);
    if (serviceType == 'nbn') {
      final down = digits != null ? int.tryParse(digits.group(0)!) : null;
      if (down == null) return null;
      if (down <= 37) return 'NBN 25';
      if (down <= 75) return 'NBN 50';
      if (down <= 300) return 'NBN 100';
      return 'NBN 500';
    }
    if (serviceType == 'mobile') {
      if (tier == 'Unlimited') return 'Unlimited';
      final gb = digits != null ? int.tryParse(digits.group(0)!) : null;
      if (gb == null) return null;
      if (gb < 20) return '<20GB';
      if (gb < 60) return '20–60GB';
      return '60GB+';
    }
    return tier;
  }

  factory SavingsOffer.fromJson(Map<String, dynamic> json) {
    // validUntil is optional: a provider's page may not state an explicit
    // calendar end-date (e.g. a flat plan with no promo). Only reject the
    // offer when a date IS given and it's already in the past -- a missing
    // date means "no known expiry," not "invalid."
    final validUntilRaw = json['validUntil'] as String?;
    DateTime? validUntil;
    if (validUntilRaw != null && validUntilRaw.isNotEmpty) {
      validUntil = DateTime.tryParse(validUntilRaw);
      if (validUntil == null) {
        throw FormatException('Unparseable validUntil: $validUntilRaw');
      }
      if (validUntil.isBefore(DateTime.now())) {
        throw FormatException('Offer expired');
      }
    }
    final category = json['category'] as String? ?? '';
    const validCats = [
      'Media / Streaming',
      'Productivity',
      'Utilities',
      'Shopping',
      'Health / Fitness',
      'Social',
      'Education',
      'Gaming',
    ];
    if (!validCats.contains(category)) {
      throw FormatException('Unknown category: $category');
    }
    final regularPrice = (json['regularPrice'] as num?)?.toDouble();
    if (regularPrice == null) {
      throw FormatException('Missing regularPrice');
    }
    return SavingsOffer(
      id: json['id'] as String,
      provider: json['provider'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: category,
      description: json['description'] as String? ?? '',
      promoPrice: (json['promoPrice'] as num?)?.toDouble() ?? 0,
      regularPrice: regularPrice,
      promoMonths: json['promoMonths'] as int? ?? 1,
      validUntil: validUntil,
      url: json['url'] as String? ?? '',
      minCurrentSpend: (json['minCurrentSpend'] as num?)?.toDouble(),
      speedTier: json['speedTier'] as String?,
      postedAt: DateTime.tryParse(json['postedAt'] as String? ?? ''),
      serviceType: json['serviceType'] as String?,
      tier: json['tier'] as String?,
      dataGB: json['dataGB'] as num?,
      techType: json['techType'] as String?,
    );
  }
}
