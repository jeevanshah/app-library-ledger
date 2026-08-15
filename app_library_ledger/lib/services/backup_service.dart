import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'storage_service.dart';

class LocalBackupInfo {
  final File file;
  final String fileName;
  final DateTime createdAt;
  final int byteSize;
  final int appCount;
  final int ledgerCount;

  LocalBackupInfo({
    required this.file,
    required this.fileName,
    required this.createdAt,
    required this.byteSize,
    required this.appCount,
    required this.ledgerCount,
  });

  String get formattedSize {
    if (byteSize < 1024) return '$byteSize B';
    if (byteSize < 1024 * 1024) return '${(byteSize / 1024).toStringAsFixed(1)} KB';
    return '${(byteSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    return DateFormat('MMM d, yyyy · h:mm a').format(createdAt);
  }
}

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  Future<Directory> _getBackupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${docs.path}/backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Creates a timestamped local backup file on device and returns info.
  Future<LocalBackupInfo> createLocalBackup() async {
    final jsonStr = await StorageService().exportAllJson();
    final backupDir = await _getBackupDir();
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(now);
    final fileName = 'priceminder_backup_$stamp.json';
    final file = File('${backupDir.path}/$fileName');
    await file.writeAsString(jsonStr, flush: true);

    int appCount = 0;
    int ledgerCount = 0;
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (decoded['apps'] is List) appCount = (decoded['apps'] as List).length;
      if (decoded['ledger'] is List) ledgerCount = (decoded['ledger'] as List).length;
    } catch (_) {}

    final stat = await file.stat();
    return LocalBackupInfo(
      file: file,
      fileName: fileName,
      createdAt: now,
      byteSize: stat.size,
      appCount: appCount,
      ledgerCount: ledgerCount,
    );
  }

  /// Lists all local backup files sorted newest first.
  Future<List<LocalBackupInfo>> listLocalBackups() async {
    final backupDir = await _getBackupDir();
    final files = backupDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    final result = <LocalBackupInfo>[];
    for (final file in files) {
      try {
        final stat = await file.stat();
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        int appCount = 0;
        int ledgerCount = 0;
        if (decoded['apps'] is List) appCount = (decoded['apps'] as List).length;
        if (decoded['ledger'] is List) ledgerCount = (decoded['ledger'] as List).length;

        DateTime createdAt = stat.modified;
        if (decoded['exportedAt'] is String) {
          final parsed = DateTime.tryParse(decoded['exportedAt']);
          if (parsed != null) createdAt = parsed;
        }

        final name = file.path.split(Platform.pathSeparator).last;
        result.add(
          LocalBackupInfo(
            file: file,
            fileName: name,
            createdAt: createdAt,
            byteSize: stat.size,
            appCount: appCount,
            ledgerCount: ledgerCount,
          ),
        );
      } catch (e) {
        debugPrint('Error reading backup file ${file.path}: $e');
      }
    }

    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// Restores from a specific local backup file.
  Future<bool> restoreBackup(File file) async {
    try {
      final raw = await file.readAsString();
      return await StorageService().importAllJson(raw);
    } catch (e) {
      debugPrint('Error restoring backup file ${file.path}: $e');
      return false;
    }
  }

  /// Deletes a local backup file.
  Future<void> deleteBackup(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Shares a local backup file with external apps (Downloads, Drive, Files, Email, etc.).
  Future<void> shareBackup(File file) async {
    final name = file.path.split(Platform.pathSeparator).last;
    await Share.shareXFiles(
      [XFile(file.path, name: name, mimeType: 'application/json')],
      subject: 'PriceMinder Data Backup',
      text: 'Here is my PriceMinder subscription & ledger backup file ($name).',
    );
  }
}
