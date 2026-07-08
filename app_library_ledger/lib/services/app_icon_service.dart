import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'subscription_scanner.dart'; // exposes packageScannerChannel

class AppIconService {
  static final AppIconService _instance = AppIconService._internal();
  factory AppIconService() => _instance;
  AppIconService._internal();

  final Map<String, Uint8List> _cache = {};
  Set<String>? _availableAssets;
  bool _manifestLoaded = false;

  /// Loads the AssetManifest to discover which service_icons PNGs exist.
  Future<void> _ensureManifest() async {
    if (_manifestLoaded) return;
    _manifestLoaded = true;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _availableAssets = manifest
          .listAssets()
          .where((path) => path.startsWith('assets/service_icons/'))
          .toSet();
    } catch (_) {
      _availableAssets = {};
    }
  }

  /// Fetches app icons from native side. Packages already in the cache are
  /// skipped. On errors the cache is left unchanged.
  Future<void> loadIcons(List<String> packageNames) async {
    final uncached = packageNames.where((p) => !_cache.containsKey(p)).toList();
    if (uncached.isEmpty) return;

    try {
      final raw = await packageScannerChannel
          .invokeMethod<Map<dynamic, dynamic>>('getAppIcons', uncached);

      if (raw == null) return;
      for (final entry in raw.entries) {
        final key = entry.key as String;
        final value = entry.value;
        if (value is Uint8List) {
          _cache[key] = value;
        }
      }
    } on MissingPluginException {
      // Non-Android — no icons available, cache stays empty
    } on PlatformException {
      // Native failure — cache stays empty
    }
  }

  /// Returns the cached icon PNG bytes for [packageName], or null.
  Uint8List? iconFor(String? packageName) {
    if (packageName == null) return null;
    return _cache[packageName];
  }

  /// Full fallback chain: real installed-app icon (MemoryImage) →
  /// bundled favicon (AssetImage) → null (caller shows letter avatar).
  /// Only returns a provider if the underlying asset is actually present
  /// (manifest check prevents missing-file errors).
  Future<ImageProvider?> providerFor({
    String? packageName,
    String? catalogId,
  }) async {
    // 1. Real installed-app icon
    final cached = iconFor(packageName);
    if (cached != null) {
      return MemoryImage(cached);
    }

    // 2. Bundled favicon
    if (catalogId != null && catalogId.isNotEmpty) {
      await _ensureManifest();
      final assetPath = 'assets/service_icons/$catalogId.png';
      if (_availableAssets != null && _availableAssets!.contains(assetPath)) {
        return AssetImage(assetPath);
      }
    }

    // 3. Not available — caller renders letter avatar
    return null;
  }
}
