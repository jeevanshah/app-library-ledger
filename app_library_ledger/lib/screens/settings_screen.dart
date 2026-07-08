import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../theme/app_tokens.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late NotificationSettings _s;
  bool _offersEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _s = await SettingsService().load();
    final prefs = await SharedPreferences.getInstance();
    _offersEnabled = prefs.getBool('offers_enabled') ?? false;
    setState(() => _loading = false);
  }

  Future<void> _setOffersEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offers_enabled', v);
    setState(() => _offersEnabled = v);
  }

  Future<void> _update(NotificationSettings updated) async {
    await SettingsService().save(updated);
    setState(() => _s = updated);
    final apps = await StorageService().getApps();
    await NotificationService().rescheduleAll(apps);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _s.hour, minute: _s.minute),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTokens.brandEnd),
          dialogTheme: const DialogThemeData(backgroundColor: AppTokens.cardBg),
        ),
        child: child!,
      ),
    );
    if (t != null) await _update(_s.copyWith(hour: t.hour, minute: t.minute));
  }

  void _toggleOffset(int day) {
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
    final h = _s.hour.toString().padLeft(2, '0');
    final m = _s.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _showPrivacySheet() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTokens.cardBg,
        title: Text(
          'Privacy',
          style: GoogleFonts.spaceGrotesk(
            color: AppTokens.textStrong,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Your subscription data never leaves your device. All detection runs entirely on-device. No account, no cloud, no tracking.',
          style: GoogleFonts.plusJakartaSans(
            color: AppTokens.textMuted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.brandEnd,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _fireTestNotification() {
    NotificationService().sendDailySummary(
      upcomingCount: 1,
      upcomingCost: 9.99,
      monthlyTotal: 29.99,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Test notification fired')));
  }

  Future<void> _scheduleTestPlus2() async {
    await NotificationService().scheduleTestPlus2();
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Test scheduled +2 min')));
  }

  Future<void> _requestExactAlarm() async {
    await NotificationService().requestExactAlarmPermission();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exact alarm permission requested')),
      );
  }

  Future<void> _listPending() async {
    final list = await NotificationService().listPending();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTokens.cardBg,
        title: Text(
          'Pending (${list.length})',
          style: GoogleFonts.spaceGrotesk(color: AppTokens.textStrong),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
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
                            fontSize: 12,
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
            ? const Center(
                child: CircularProgressIndicator(color: AppTokens.gold),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                children: [
                  const SizedBox(height: 16),
                  _sectionLabel('SETTINGS'),
                  const SizedBox(height: 4),
                  Text(
                    'Notifications',
                    style: GoogleFonts.playfairDisplay(
                      color: AppTokens.textStrong,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Master toggle
                  _row(
                    'Notifications',
                    trailing: Switch(
                      value: _s.enabled,
                      activeColor: AppTokens.brandEnd,
                      onChanged: (v) => _update(_s.copyWith(enabled: v)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Offsets section
                  Opacity(
                    opacity: _s.enabled ? 1 : 0.4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Renewal reminders',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final d in const [1, 3, 7, 14])
                              GestureDetector(
                                onTap: _s.enabled
                                    ? () => _toggleOffset(d)
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _s.offsets.contains(d)
                                        ? AppTokens.gold.withValues(alpha: 0.12)
                                        : AppTokens.fieldBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _s.offsets.contains(d)
                                          ? AppTokens.gold.withValues(
                                              alpha: 0.3,
                                            )
                                          : AppTokens.hairline,
                                    ),
                                  ),
                                  child: Text(
                                    '$d day${d == 1 ? '' : 's'} before',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: _s.offsets.contains(d)
                                          ? AppTokens.gold
                                          : AppTokens.textMuted,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _row(
                          'Promo ending alerts',
                          trailing: Switch(
                            value: _s.promoAlerts,
                            activeColor: AppTokens.brandEnd,
                            onChanged: _s.enabled
                                ? (v) => _update(_s.copyWith(promoAlerts: v))
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _row(
                          'Reminder time',
                          trailing: GestureDetector(
                            onTap: _s.enabled ? _pickTime : null,
                            child: Text(
                              _timeLabel(),
                              style: GoogleFonts.spaceGrotesk(
                                color: AppTokens.brandEnd,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Savings Offers
                  _sectionLabel('SAVINGS OFFERS'),
                  const SizedBox(height: 12),
                  _row(
                    'Savings offers',
                    trailing: Switch(
                      value: _offersEnabled,
                      activeColor: AppTokens.brandEnd,
                      onChanged: _setOffersEnabled,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      'Offers are downloaded anonymously. What you track never leaves your device. Links may earn us a commission.',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // S4: About
                  _sectionLabel('ABOUT'),
                  const SizedBox(height: 12),
                  _row(
                    'Version',
                    trailing: Text(
                      '1.0.0',
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTokens.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _row(
                    'Privacy',
                    onTap: _showPrivacySheet,
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTokens.textFaint,
                      size: 18,
                    ),
                  ),

                  // S5: Developer (kDebugMode only)
                  if (kDebugMode) ...[
                    const SizedBox(height: 32),
                    _sectionLabel('DEVELOPER'),
                    const SizedBox(height: 12),
                    _row(
                      'Fire test notification now',
                      onTap: _fireTestNotification,
                    ),
                    _row('Schedule test +2 min', onTap: _scheduleTestPlus2),
                    _row(
                      'Request exact alarm permission',
                      onTap: _requestExactAlarm,
                    ),
                    _row('List pending', onTap: _listPending),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: GoogleFonts.plusJakartaSans(
      color: AppTokens.textFaint,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 2.5,
    ),
  );

  Widget _row(String label, {Widget? trailing, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTokens.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
