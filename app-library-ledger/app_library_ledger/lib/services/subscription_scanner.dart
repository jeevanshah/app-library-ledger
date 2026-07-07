import 'package:flutter/services.dart';
import '../models/catalog_entry.dart';
import 'catalog_service.dart';

/// Shared channel — used by [SubscriptionScanner] and [AppIconService].
const packageScannerChannel = MethodChannel(
  'com.applibraryledger/package_scanner',
);

class SubscriptionScanner {
  static const _channel = packageScannerChannel;

  /// Scans the device for installed apps matching the catalog.
  /// Returns matched [CatalogEntry]s that were found on the device.
  /// On non-Android platforms (or if the channel is missing), returns empty.
  static Future<List<CatalogEntry>> scanDevice() async {
    final catalog = CatalogService();
    await catalog.loadCatalog();

    final appScanEntries = catalog.appScanEntries;
    if (appScanEntries.isEmpty) return const [];

    final packageNames = appScanEntries.map((e) => e.packageName!).toList();

    try {
      final installed = await _channel.invokeMethod<List<dynamic>>(
        'checkPackagesSurgically',
        packageNames,
      );

      if (installed == null || installed.isEmpty) return const [];

      final matched = <CatalogEntry>[];
      for (final pkg in installed) {
        final entry = catalog.findByPackageName(pkg as String);
        if (entry != null) matched.add(entry);
      }
      return matched;
    } on MissingPluginException {
      // Non-Android platform (e.g., iOS simulator) — return empty gracefully
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}
