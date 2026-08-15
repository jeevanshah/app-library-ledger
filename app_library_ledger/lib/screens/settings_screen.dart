import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late NotificationSettings _s;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _s = await SettingsService().load();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _update(NotificationSettings updated) async {
    await SettingsService().save(updated);
    setState(() => _s = updated);
    final apps = await StorageService().getApps();
    await NotificationService().rescheduleAll(apps);
  }

  Future<void> _pickTime() async {
    HapticFeedback.selectionClick();
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _s.hour, minute: _s.minute),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppTokens.brandStart,
            surface: AppTokens.cardBg,
          ),
          dialogTheme: DialogThemeData(backgroundColor: AppTokens.cardBg),
        ),
        child: child!,
      ),
    );
    if (t != null) {
      await _update(_s.copyWith(hour: t.hour, minute: t.minute));
    }
  }

  void _toggleOffset(int day) {
    HapticFeedback.selectionClick();
    final list = _s.offsets.toList();
    if (list.contains(day)) {
      if (list.length == 1) return;
      list.remove(day);
    } else {
      list.add(day);
      list.sort();
    }
    _update(_s.copyWith(offsets: list));
  }

  String _timeLabel() {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, _s.hour, _s.minute);
    return TimeOfDay.fromDateTime(dt).format(context);
  }

  void _showPrivacySheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTokens.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTokens.brandStart.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: flatIcon(
                      'shield_lock_dark',
                      color: AppTokens.brandStart,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'On-Device Privacy',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.textStrong,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _privacyBullet(
                icon: Icons.cloud_off_rounded,
                title: '100% Offline & Device-Local',
                desc: 'Your subscription data, costs, and renewal dates never leave this phone.',
              ),
              const SizedBox(height: 12),
              _privacyBullet(
                icon: Icons.person_off_rounded,
                title: 'No Accounts or Sign-ins',
                desc: 'PriceMinder does not require an account, email, or personal identity.',
              ),
              const SizedBox(height: 12),
              _privacyBullet(
                icon: Icons.track_changes_rounded,
                title: 'Zero Tracking & Zero Telemetry',
                desc: 'No ad networks, behavioral trackers, or analytics scripts are embedded.',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.fieldBg,
                    foregroundColor: AppTokens.textPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rPill),
                      side: BorderSide(color: AppTokens.hairline),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Got It',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _privacyBullet({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: AppTokens.fieldBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTokens.hairline),
          ),
          child: Icon(icon, size: 16, color: AppTokens.brandStart),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Local Device Backup Operations ──────────────────────────────

  Future<void> _createDeviceLocalBackup() async {
    HapticFeedback.selectionClick();
    try {
      final b = await BackupService().createLocalBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTokens.cardBg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppTokens.hairline),
          ),
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppTokens.brandStart, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Backup saved to device (${b.formattedSize}, ${b.appCount} apps)',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'View',
            textColor: AppTokens.brandStart,
            onPressed: _showLocalBackupsSheet,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create backup: $e')),
      );
    }
  }

  Future<void> _showLocalBackupsSheet() async {
    HapticFeedback.selectionClick();
    var backups = await BackupService().listLocalBackups();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTokens.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Device Backups',
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTokens.textStrong,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${backups.length} file${backups.length == 1 ? '' : 's'} stored on this phone',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _createDeviceLocalBackup();
                        final updated = await BackupService().listLocalBackups();
                        setSheetState(() => backups = updated);
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('New Backup'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTokens.brandStart,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.rPill),
                        ),
                        textStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (backups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          flatIcon(
                            'cloud_sync_dark',
                            color: AppTokens.textMuted,
                            size: 38,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No local backups on device yet',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap "New Backup" above to create one.',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.textFaint,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: backups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final b = backups[i];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTokens.fieldBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTokens.hairline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: AppTokens.brandStart.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.inventory_2_rounded,
                                      size: 15,
                                      color: AppTokens.brandStart,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      b.formattedDate,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: AppTokens.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTokens.cardBg,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: AppTokens.hairline,
                                      ),
                                    ),
                                    child: Text(
                                      b.formattedSize,
                                      style: GoogleFonts.spaceGrotesk(
                                        color: AppTokens.textFaint,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${b.appCount} subscriptions · ${b.ledgerCount} ledger records',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppTokens.textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.share_outlined,
                                      size: 18,
                                    ),
                                    color: AppTokens.textMuted,
                                    tooltip: 'Share / Save to Files',
                                    onPressed: () =>
                                        BackupService().shareBackup(b.file),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                    ),
                                    color: AppTokens.warning,
                                    tooltip: 'Delete Backup',
                                    onPressed: () async {
                                      await BackupService().deleteBackup(b.file);
                                      final updated = await BackupService()
                                          .listLocalBackups();
                                      setSheetState(() => backups = updated);
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton(
                                    onPressed: () async {
                                      Navigator.pop(ctx);
                                      final ok = await BackupService()
                                          .restoreBackup(b.file);
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            ok
                                                ? 'Restored from ${b.formattedDate}'
                                                : 'Failed to restore backup.',
                                          ),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTokens.brandStart,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppTokens.rSmallPill,
                                        ),
                                      ),
                                      textStyle: GoogleFonts.plusJakartaSans(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    child: const Text('Restore'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportBackupToClipboard() async {
    HapticFeedback.selectionClick();
    final json = await StorageService().exportAllJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTokens.cardBg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppTokens.hairline),
        ),
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppTokens.brandStart, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Complete backup copied to clipboard!',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportSheet() {
    HapticFeedback.selectionClick();
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 16,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTokens.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Import Backup',
                style: GoogleFonts.spaceGrotesk(
                  color: AppTokens.textStrong,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Paste your exported JSON backup to restore subscriptions, categories, and ledger entries.',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                maxLines: 6,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  color: AppTokens.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: '{\n  "version": 1,\n  "apps": [...]\n}',
                  hintStyle: GoogleFonts.spaceGrotesk(
                    color: AppTokens.textFaint,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: AppTokens.fieldBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppTokens.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: AppTokens.brandStart,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTokens.hairline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.rPill),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final raw = controller.text.trim();
                        if (raw.isEmpty) return;
                        final ok = await StorageService().importAllJson(raw);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Backup restored successfully!'
                                  : 'Invalid JSON backup format.',
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTokens.brandStart,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.rPill),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Restore',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearData() {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTokens.hairline),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTokens.warning, size: 24),
            const SizedBox(width: 10),
            Text(
              'Reset Database?',
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textStrong,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'This will wipe all tracked subscriptions, categories, and spending records from this device. This cannot be undone.',
          style: GoogleFonts.plusJakartaSans(
            color: AppTokens.textMuted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService().clearAllData();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Database reset.')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTokens.warning,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.rPill),
              ),
            ),
            child: Text(
              'Reset Everything',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Developer Diagnostics Operations ────────────────────────────

  Future<void> _sendRealReminderNow() async {
    final apps = await StorageService().getApps();
    final name = await NotificationService().sendRealReminderNow(apps);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          name != null
              ? 'Sent a real reminder for $name'
              : 'No subscription has enough data to build one',
        ),
      ),
    );
  }

  Future<void> _sendImmediateTestReminder() async {
    await NotificationService().sendTestNotificationNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Immediate test notification fired! 🔔')),
    );
  }

  Future<void> _runBillingReconciliation() async {
    await StorageService().reconcileBilling();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Billing reconciliation completed. Stale dates caught up.'),
      ),
    );
  }

  Future<void> _seedSampleData() async {
    await StorageService().seedSampleData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sample data seeded! (5 active subscriptions + 4 months of ledger history)',
        ),
      ),
    );
  }

  void _showDatabaseDumpSheet() {
    final dump = StorageService().getRawDatabaseDump();
    final pretty = const JsonEncoder.withIndent('  ').convert(dump);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.8,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTokens.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Raw Database Dump',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.textStrong,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: pretty));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Database dump copied!')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTokens.fieldBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTokens.hairline),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      pretty,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestExactAlarm() async {
    await NotificationService().requestExactAlarmPermission();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exact alarm settings opened')),
      );
    }
  }

  Future<void> _listPending() async {
    final list = await NotificationService().listPending();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTokens.cardBg,
        title: Text(
          'Pending Notifications (${list.length})',
          style: GoogleFonts.spaceGrotesk(
            color: AppTokens.textStrong,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: list.isEmpty
              ? Text(
                  'No alarms scheduled',
                  style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted),
                )
              : ListView(
                  shrinkWrap: true,
                  children: list
                      .map(
                        (p) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#${p['id']} ${p['title']}',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppTokens.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                p['body'] ?? '',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppTokens.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.screenBg,
      body: SafeArea(
        child: _loading
            ? Center(
                child: CircularProgressIndicator(color: AppTokens.brandStart),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
                children: [
                  // Hero Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SETTINGS',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.textFaint,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Preferences',
                            style: GoogleFonts.playfairDisplay(
                              color: AppTokens.textStrong,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTokens.brandStart.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(
                            AppTokens.rSmallPill,
                          ),
                          border: Border.all(
                            color: AppTokens.brandStart.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            flatIcon(
                              'shield_lock_dark',
                              color: AppTokens.brandStart,
                              size: 11,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'ON-DEVICE',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTokens.brandStart,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ── Group 1: Notifications & Renewal Reminders ──
                  _groupCard(
                    title: 'Renewal Reminders & Alerts',
                    icon: flatIcon(
                      'bell_orange',
                      color: AppTokens.brandStart,
                      size: 17,
                    ),
                    children: [
                      _toggleTile(
                        title: 'Renewal Notifications',
                        subtitle: 'Receive timely notifications before renewal charges',
                        value: _s.enabled,
                        onChanged: (v) => _update(_s.copyWith(enabled: v)),
                      ),
                      if (_s.enabled) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Notify before renewal',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final d in const [1, 3, 7, 14])
                              _offsetPill(d),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _toggleTile(
                          title: 'Promo Cliff Alerts',
                          subtitle: 'Alert a few days before promotional pricing resets to regular rate',
                          value: _s.promoAlerts,
                          onChanged: (v) => _update(_s.copyWith(promoAlerts: v)),
                        ),
                        const SizedBox(height: 14),
                        GestureDetector(
                          onTap: _pickTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: AppTokens.fieldBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTokens.hairline),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppTokens.brandStart.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: flatIcon(
                                    'clock_alarm_orange',
                                    color: AppTokens.brandStart,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Daily Alert Time',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppTokens.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        'Reminders fire at this hour',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppTokens.textMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTokens.brandStart.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
                                    border: Border.all(
                                      color: AppTokens.brandStart.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Text(
                                    _timeLabel(),
                                    style: GoogleFonts.spaceGrotesk(
                                      color: AppTokens.brandStart,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _actionTile(
                          title: 'Precise Alarm Permission',
                          subtitle: 'Android 12+ settings for exact-minute alerts',
                          icon: Icons.alarm_on_rounded,
                          onTap: _requestExactAlarm,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Group 2: Appearance ──
                  _groupCard(
                    title: 'Appearance',
                    icon: Icon(
                      Icons.palette_outlined,
                      color: AppTokens.brandStart,
                      size: 18,
                    ),
                    children: [
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: AppTheme.themeModeNotifier,
                        builder: (_, mode, __) => Row(
                          children: [
                            _themePill(
                              label: 'Light',
                              icon: Icons.light_mode_rounded,
                              active: mode == ThemeMode.light,
                              onTap: () => AppTheme.setThemeMode(ThemeMode.light),
                            ),
                            const SizedBox(width: 8),
                            _themePill(
                              label: 'Dark',
                              icon: Icons.dark_mode_rounded,
                              active: mode == ThemeMode.dark,
                              onTap: () => AppTheme.setThemeMode(ThemeMode.dark),
                            ),
                            const SizedBox(width: 8),
                            _themePill(
                              label: 'System',
                              icon: Icons.settings_suggest_rounded,
                              active: mode == ThemeMode.system,
                              onTap: () => AppTheme.setThemeMode(ThemeMode.system),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Group 3: Savings Opportunities ──
                  _groupCard(
                    title: 'Savings & Better Deals',
                    icon: flatIcon(
                      'tag_orange',
                      color: AppTokens.brandEnd,
                      size: 17,
                    ),
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: SettingsService().offersEnabled,
                        builder: (_, enabled, __) => _toggleTile(
                          title: 'Savings Offers',
                          subtitle: 'Download anonymous deal updates for mobile and NBN subscriptions',
                          value: enabled,
                          onChanged: (v) => SettingsService().setOffersEnabled(v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Group 4: Data & Backup ──
                  _groupCard(
                    title: 'Data & Backup',
                    icon: flatIcon(
                      'cloud_sync_orange',
                      color: AppTokens.brandStart,
                      size: 17,
                    ),
                    children: [
                      _actionTile(
                        title: 'Save Backup on Phone',
                        subtitle: 'Create a local timestamped backup file on this device',
                        icon: Icons.save_alt_rounded,
                        onTap: _createDeviceLocalBackup,
                      ),
                      const SizedBox(height: 8),
                      _actionTile(
                        title: 'Manage Local Backups',
                        subtitle: 'View, restore, share, or delete backups on this phone',
                        icon: Icons.folder_zip_rounded,
                        onTap: _showLocalBackupsSheet,
                      ),
                      const SizedBox(height: 8),
                      _actionTile(
                        title: 'Copy Backup to Clipboard',
                        subtitle: 'Export raw JSON backup directly to clipboard',
                        icon: Icons.copy_rounded,
                        onTap: _exportBackupToClipboard,
                      ),
                      const SizedBox(height: 8),
                      _actionTile(
                        title: 'Import & Restore Backup',
                        subtitle: 'Paste and restore subscriptions from JSON',
                        icon: Icons.download_rounded,
                        onTap: _showImportSheet,
                      ),
                      const SizedBox(height: 8),
                      _actionTile(
                        title: 'Reset Local Database',
                        subtitle: 'Wipe all tracked subscriptions and ledger',
                        icon: Icons.delete_forever_rounded,
                        color: AppTokens.warning,
                        onTap: _confirmClearData,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Group 5: About & Privacy ──
                  _groupCard(
                    title: 'About PriceMinder',
                    icon: flatIcon(
                      'shield_lock_dark',
                      color: AppTokens.brandStart,
                      size: 17,
                    ),
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 44,
                              height: 44,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PriceMinder',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTokens.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Version 1.0.0 · On-device Ledger',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTokens.textMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _actionTile(
                        title: 'Privacy Policy & Statement',
                        subtitle: 'Why your data stays 100% on this phone',
                        icon: Icons.security_rounded,
                        onTap: _showPrivacySheet,
                      ),
                    ],
                  ),

                  // Developer Diagnostics (always useful during development & testing)
                  if (kDebugMode) ...[
                    const SizedBox(height: 14),
                    _groupCard(
                      title: 'Developer Diagnostics',
                      icon: Icon(
                        Icons.bug_report_outlined,
                        color: AppTokens.brandStart,
                        size: 18,
                      ),
                      children: [
                        _actionTile(
                          title: 'Fire Immediate Test Notification',
                          subtitle: 'Simulates an alert immediately with sound/vibration',
                          icon: Icons.notifications_active_outlined,
                          onTap: _sendImmediateTestReminder,
                        ),
                        const SizedBox(height: 8),
                        _actionTile(
                          title: 'Fire Real Library Reminder',
                          subtitle: 'Simulates the real scheduled notification',
                          icon: Icons.notification_important_outlined,
                          onTap: _sendRealReminderNow,
                        ),
                        const SizedBox(height: 8),
                        _actionTile(
                          title: 'Seed Sample Subscriptions & History',
                          subtitle: 'Populates 5 popular subscriptions + 4 months of spend ledger',
                          icon: Icons.auto_fix_high_rounded,
                          onTap: _seedSampleData,
                        ),
                        const SizedBox(height: 8),
                        _actionTile(
                          title: 'Run Billing Catch-up Reconciliation',
                          subtitle: 'Executes reconcileBilling() for passed renewal dates',
                          icon: Icons.sync_rounded,
                          onTap: _runBillingReconciliation,
                        ),
                        const SizedBox(height: 8),
                        _actionTile(
                          title: 'Inspect Pending Alarms',
                          subtitle: 'List all scheduled background notifications',
                          icon: Icons.list_alt_rounded,
                          onTap: _listPending,
                        ),
                        const SizedBox(height: 8),
                        _actionTile(
                          title: 'Inspect Raw Database Dump',
                          subtitle: 'View and copy all stored keys in SharedPreferences',
                          icon: Icons.data_object_rounded,
                          onTap: _showDatabaseDumpSheet,
                        ),
                        const SizedBox(height: 8),
                        _actionTile(
                          title: 'Request Exact Alarm Permission',
                          subtitle: 'Android 12+ SCHEDULE_EXACT_ALARM',
                          icon: Icons.alarm_rounded,
                          onTap: _requestExactAlarm,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
      ),
    );
  }

  Widget _groupCard({
    required String title,
    required Widget icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTokens.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: AppTokens.isDark ? 0.25 : 0.04,
            ),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTokens.brandStart.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: icon,
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _offsetPill(int d) {
    final active = _s.offsets.contains(d);
    return GestureDetector(
      onTap: () => _toggleOffset(d),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppTokens.brandStart.withValues(alpha: 0.15)
              : AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(AppTokens.rPill),
          border: Border.all(
            color: active ? AppTokens.brandStart : AppTokens.hairline,
            width: active ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) ...[
              Icon(Icons.check_rounded, size: 14, color: AppTokens.brandStart),
              const SizedBox(width: 5),
            ],
            Text(
              '$d day${d == 1 ? '' : 's'} before',
              style: GoogleFonts.plusJakartaSans(
                color: active ? AppTokens.brandStart : AppTokens.textMuted,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themePill({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: active ? AppTokens.brandGradient : null,
            color: active ? null : AppTokens.fieldBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? Colors.transparent : AppTokens.hairline,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppTokens.brandStart.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? Colors.white : AppTokens.textMuted,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  color: active ? Colors.white : AppTokens.textMuted,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          activeTrackColor: AppTokens.brandStart,
          activeThumbColor: Colors.white,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            onChanged(v);
          },
        ),
      ],
    );
  }

  Widget _actionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    Color? color,
    required VoidCallback onTap,
  }) {
    final c = color ?? AppTokens.brandStart;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTokens.hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppTokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
