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
  });

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
    );
  }
}
