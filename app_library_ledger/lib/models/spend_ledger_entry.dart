import 'package:uuid/uuid.dart';

enum LedgerEventKind { billed, priceChanged }

/// A real, observed spending event — logged going forward from whenever
/// the app started tracking it. Never backfilled for time before this
/// feature existed; the Calendar's `projectedPastBilling` estimates cover
/// that gap instead, clearly marked as estimates, not fact.
class SpendLedgerEntry {
  final String id;
  final String entryId; // AppEntry.id
  final String appName;
  final DateTime date; // date-only
  final double amount; // actual charge (billed) or new price (priceChanged)
  final double? previousAmount; // only for priceChanged
  final LedgerEventKind kind;
  final String? category; // AppEntry.category at the time

  SpendLedgerEntry({
    String? id,
    required this.entryId,
    required this.appName,
    required this.date,
    required this.amount,
    this.previousAmount,
    required this.kind,
    this.category,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'entryId': entryId,
    'appName': appName,
    'date': date.toIso8601String(),
    'amount': amount,
    'previousAmount': previousAmount,
    'kind': kind.name,
    'category': category,
  };

  factory SpendLedgerEntry.fromJson(Map<String, dynamic> json) => SpendLedgerEntry(
    id: json['id'] as String?,
    entryId: json['entryId'] as String,
    appName: json['appName'] as String,
    date: DateTime.parse(json['date'] as String),
    amount: (json['amount'] as num).toDouble(),
    previousAmount: (json['previousAmount'] as num?)?.toDouble(),
    kind: LedgerEventKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => LedgerEventKind.billed,
    ),
    category: json['category'] as String?,
  );
}
