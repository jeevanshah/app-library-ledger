import 'dart:convert';
import 'dart:io' show HttpClient;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/offer.dart';

class OffersService {
  static final OffersService _instance = OffersService._internal();
  factory OffersService() => _instance;
  OffersService._internal();

  static const String offersUrl =
      'https://raw.githubusercontent.com/jeevanshah/app-library-ledger/main/offers.json';
  static const _cacheKey = 'offers_cache';
  static const _timeKey = 'offers_cache_time';

  List<SavingsOffer>? _cached;
  DateTime? _cacheTime;

  Future<List<SavingsOffer>> fetch({bool enabled = false}) async {
    if (!enabled) return const [];
    // Return cache if fresh (<12h)
    if (_cached != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!).inHours < 12) {
      return _cached!;
    }

    // Try loading from prefs first
    final prefs = await SharedPreferences.getInstance();
    final rawCache = prefs.getString(_cacheKey);
    final cacheTimeStr = prefs.getString(_timeKey);
    if (rawCache != null && cacheTimeStr != null) {
      final cacheTime = DateTime.tryParse(cacheTimeStr);
      if (cacheTime != null &&
          DateTime.now().difference(cacheTime).inHours < 12) {
        try {
          _cached = _parse(jsonDecode(rawCache) as List<dynamic>);
          _cacheTime = cacheTime;
          return _cached!;
        } catch (_) {}
      }
    }

    List<SavingsOffer>? offers;

    // Try remote
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(offersUrl));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body) as List<dynamic>;
        offers = _parse(decoded);
        // Cache
        await prefs.setString(_cacheKey, body);
        await prefs.setString(_timeKey, DateTime.now().toIso8601String());
      }
    } catch (_) {}

    // Fallback: local cache from prefs
    if (offers == null && rawCache != null) {
      try {
        offers = _parse(jsonDecode(rawCache) as List<dynamic>);
      } catch (_) {}
    }

    // kDebugMode fallback: bundled sample
    if (offers == null && kDebugMode) {
      try {
        final sample = await rootBundle.loadString('assets/offers_sample.json');
        offers = _parse(jsonDecode(sample) as List<dynamic>);
      } catch (_) {}
    }

    _cached = offers ?? [];
    _cacheTime = DateTime.now();
    return _cached!;
  }

  List<SavingsOffer> _parse(List<dynamic> raw) {
    final result = <SavingsOffer>[];
    for (final json in raw) {
      try {
        result.add(SavingsOffer.fromJson(json as Map<String, dynamic>));
      } catch (_) {}
    }
    return result;
  }
}
