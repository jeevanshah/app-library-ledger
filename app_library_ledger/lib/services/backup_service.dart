import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_model.dart';
import '../models/category_model.dart';

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  Future<void> exportData({
    required List<AppEntry> apps,
    required List<Category> categories,
  }) async {
    final data = {
      'version': '1.0',
      'exportDate': DateTime.now().toIso8601String(),
      'apps': apps.map((a) => a.toJson()).toList(),
      'categories': categories.map((c) => c.toJson()).toList(),
    };

    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/subscriptions_backup_${_dateStamp()}.json');
    await file.writeAsString(json);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'PriceMinder Backup',
      text: 'My subscription backup from PriceMinder',
    );
  }

  Future<Map<String, dynamic>?> importData(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    final json = await file.readAsString();
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<void> exportCSV(List<AppEntry> apps) async {
    final buffer = StringBuffer();
    buffer.writeln(
      'Name,Category,Cost,Billing Cycle,Next Renewal,App Store Link,Notes,Is Promo,Regular Price,Promo Ends',
    );

    for (final app in apps) {
      buffer.write('"${app.name}",');
      buffer.write('"${app.category}",');
      buffer.write('${app.subscriptionCost ?? '0'},');
      buffer.write('${app.billingCycle ?? 'N/A'},');
      buffer.write(
        '${app.nextRenewalDate != null ? '${app.nextRenewalDate!.month}/${app.nextRenewalDate!.day}/${app.nextRenewalDate!.year}' : 'N/A'},',
      );
      buffer.write('"${app.appStoreLink}",');
      buffer.write('"${(app.notes ?? '').replaceAll('"', '""')}",');
      buffer.write('${app.isPromotionalPrice ? 'Yes' : 'No'},');
      buffer.write('${app.regularPrice ?? '0'},');
      buffer.writeln(
        app.promotionEndsDate != null
            ? '${app.promotionEndsDate!.month}/${app.promotionEndsDate!.day}/${app.promotionEndsDate!.year}'
            : 'N/A',
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/subscriptions_${_dateStamp()}.csv');
    await file.writeAsString(buffer.toString());

    await Share.shareXFiles([
      XFile(file.path),
    ], subject: 'PriceMinder - CSV Export');
  }

  String _dateStamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
