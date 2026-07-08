import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/catalog_entry.dart';

class CatalogService {
  static final CatalogService _instance = CatalogService._internal();
  factory CatalogService() => _instance;
  CatalogService._internal();

  List<CatalogEntry>? _cached;

  Future<List<CatalogEntry>> loadCatalog() async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString('assets/catalog.json');
    final List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      // Malformed asset — return empty rather than crashing
      _cached = const [];
      return const [];
    }
    final entries = <CatalogEntry>[];
    for (final json in decoded) {
      try {
        entries.add(CatalogEntry.fromJson(json as Map<String, dynamic>));
      } catch (_) {
        continue;
      }
    }
    _cached = entries;
    return entries;
  }

  List<CatalogEntry> get appScanEntries {
    if (_cached == null) return [];
    return _cached!
        .where(
          (e) =>
              e.discoveryType == DiscoveryType.appScan && e.packageName != null,
        )
        .toList();
  }

  List<CatalogEntry> get webManualEntries {
    if (_cached == null) return [];
    return _cached!
        .where((e) => e.discoveryType == DiscoveryType.webManual)
        .toList();
  }

  /// Finds a catalog entry by its matched packageName from the scanner.
  CatalogEntry? findByPackageName(String packageName) {
    if (_cached == null) return null;
    for (final entry in _cached!) {
      if (entry.packageName == packageName) return entry;
    }
    return null;
  }
}
