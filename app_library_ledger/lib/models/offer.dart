class SavingsOffer {
  final String id;
  final String provider;
  final String title;
  final String category;
  final String description;
  final double promoPrice;
  final double regularPrice;
  final int promoMonths;
  final DateTime validUntil;
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
    required this.validUntil,
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

  factory SavingsOffer.fromJson(Map<String, dynamic> json) {
    final validUntil = DateTime.tryParse(json['validUntil'] as String? ?? '');
    if (validUntil == null || validUntil.isBefore(DateTime.now())) {
      throw FormatException('Offer expired or missing validUntil');
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
