import 'package:uuid/uuid.dart';

/// Default next-renewal date for a given billing cycle, one cycle out
/// from [from] (or now). Shared by anywhere a renewal date needs a
/// sensible default without the user having picked one yet.
DateTime defaultRenewalDate(String cycle, [DateTime? from]) {
  final now = from ?? DateTime.now();
  return cycle == 'yearly'
      ? DateTime(now.year + 1, now.month, now.day)
      : DateTime(now.year, now.month + 1, now.day);
}

class _Unset {
  const _Unset();
}

const _unset = _Unset();

class AppEntry {
  final String id;
  final String name;
  final String appStoreLink;
  final String category;
  final String? packageName;
  final String? notes;
  final DateTime createdAt;
  final double? subscriptionCost;
  final String? billingCycle; // 'monthly' or 'yearly'
  final DateTime? nextRenewalDate;
  final bool isActiveSubscription;
  final bool isPromotionalPrice;
  final double? regularPrice;
  final DateTime? promotionEndsDate;
  final String? serviceTier; // user's speed/data tier for NBN/mobile comparison
  final String? serviceType; // "nbn", "mobile", or null
  AppEntry({
    String? id,
    required this.name,
    required this.appStoreLink,
    required this.category,
    this.packageName,
    this.notes,
    DateTime? createdAt,
    this.subscriptionCost,
    this.billingCycle,
    this.nextRenewalDate,
    this.isActiveSubscription = false,
    this.isPromotionalPrice = false,
    this.regularPrice,
    this.promotionEndsDate,
    this.serviceTier,
    this.serviceType,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  AppEntry copyWith({
    String? name,
    String? appStoreLink,
    String? category,
    String? packageName,
    String? notes,
    double? subscriptionCost,
    String? billingCycle,
    DateTime? nextRenewalDate,
    bool? isActiveSubscription,
    bool? isPromotionalPrice,
    double? regularPrice,
    DateTime? promotionEndsDate,
    String? serviceTier,
    Object? serviceType = _unset,
  }) => AppEntry(
    id: id,
    name: name ?? this.name,
    appStoreLink: appStoreLink ?? this.appStoreLink,
    category: category ?? this.category,
    packageName: packageName ?? this.packageName,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    subscriptionCost: subscriptionCost ?? this.subscriptionCost,
    billingCycle: billingCycle ?? this.billingCycle,
    nextRenewalDate: nextRenewalDate ?? this.nextRenewalDate,
    isActiveSubscription: isActiveSubscription ?? this.isActiveSubscription,
    isPromotionalPrice: isPromotionalPrice ?? this.isPromotionalPrice,
    regularPrice: regularPrice ?? this.regularPrice,
    promotionEndsDate: promotionEndsDate ?? this.promotionEndsDate,
    serviceTier: serviceTier ?? this.serviceTier,
    serviceType: identical(serviceType, _unset)
        ? this.serviceType
        : serviceType as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'appStoreLink': appStoreLink,
    'category': category,
    'packageName': packageName,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
    'subscriptionCost': subscriptionCost,
    'billingCycle': billingCycle,
    'nextRenewalDate': nextRenewalDate?.toIso8601String(),
    'isActiveSubscription': isActiveSubscription,
    'isPromotionalPrice': isPromotionalPrice,
    'regularPrice': regularPrice,
    'promotionEndsDate': promotionEndsDate?.toIso8601String(),
    'serviceTier': serviceTier,
    'serviceType': serviceType,
  };

  factory AppEntry.fromJson(Map<String, dynamic> json) => AppEntry(
    id: json['id'] as String?,
    name: json['name'] as String? ?? '',
    appStoreLink: json['appStoreLink'] as String? ?? '',
    category: json['category'] as String? ?? '',
    packageName: json['packageName'] as String?,
    notes: json['notes'] as String?,
    createdAt: DateTime.parse(json['createdAt']),
    subscriptionCost: json['subscriptionCost'] as double?,
    billingCycle: json['billingCycle'] as String?,
    nextRenewalDate: json['nextRenewalDate'] != null
        ? DateTime.parse(json['nextRenewalDate'] as String)
        : null,
    isActiveSubscription: json['isActiveSubscription'] as bool? ?? false,
    isPromotionalPrice: json['isPromotionalPrice'] as bool? ?? false,
    regularPrice: json['regularPrice'] as double?,
    promotionEndsDate: json['promotionEndsDate'] != null
        ? DateTime.parse(json['promotionEndsDate'] as String)
        : null,
    serviceTier: json['serviceTier'] as String?,
    serviceType: json['serviceType'] as String?,
  );
}
