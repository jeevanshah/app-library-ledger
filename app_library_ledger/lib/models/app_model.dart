import 'package:uuid/uuid.dart';

class AppEntry {
  final String id;
  final String name;
  final String appStoreLink;
  final String category;
  final String? notes;
  final DateTime createdAt;  final double? subscriptionCost;
  final String? billingCycle; // 'monthly' or 'yearly'
  final DateTime? nextRenewalDate;
  final bool isActiveSubscription;
  final bool isPromotionalPrice;
  final double? regularPrice;
  final DateTime? promotionEndsDate;
  AppEntry({
    String? id,
    required this.name,
    required this.appStoreLink,
    required this.category,
    this.notes,
    DateTime? createdAt,    this.subscriptionCost,
    this.billingCycle,
    this.nextRenewalDate,
    this.isActiveSubscription = false,
    this.isPromotionalPrice = false,
    this.regularPrice,
    this.promotionEndsDate,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'appStoreLink': appStoreLink,
        'category': category,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'subscriptionCost': subscriptionCost,
        'billingCycle': billingCycle,
        'nextRenewalDate': nextRenewalDate?.toIso8601String(),
        'isActiveSubscription': isActiveSubscription,
        'isPromotionalPrice': isPromotionalPrice,
        'regularPrice': regularPrice,
        'promotionEndsDate': promotionEndsDate?.toIso8601String(),
      };

  factory AppEntry.fromJson(Map<String, dynamic> json) => AppEntry(
        id: json['id'],
        name: json['name'],
        appStoreLink: json['appStoreLink'],
        category: json['category'],
        notes: json['notes'],
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
      );
}
