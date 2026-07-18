import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _s = await SettingsService().load();
    setState(() => _loading = false);
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

  Future<void> _sendRealReminderNow() async {
    final apps = await StorageService().getApps();
    final name = await NotificationService().sendRealReminderNow(apps);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          name != null
              ? 'Sent a real reminder for $name'
              : 'No subscription has enough data (promo end or renewal date) to build one',
        ),
      ),
    );
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
            ? const Center(
                child: CircularProgressIndicator(color: AppTokens.gold),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.padHeader,
                ),
                children: [
                  const SizedBox(height: AppTokens.gapSection),
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
                  const SizedBox(height: AppTokens.gapSection),

                  // Master toggle
                  _row(
                    'Notifications',
                    trailing: Switch(
                      value: _s.enabled,
                      activeColor: AppTokens.brandEnd,
                      onChanged: (v) => _update(_s.copyWith(enabled: v)),
                    ),
                  ),
                  const SizedBox(height: AppTokens.gapItem),

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
                        const SizedBox(height: AppTokens.gapItem),
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
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _s.offsets.contains(d)
                                        ? AppTokens.gold.withValues(alpha: 0.12)
                                        : AppTokens.fieldBg,
                                    borderRadius: BorderRadius.circular(
                                      AppTokens.rPill,
                                    ),
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
                        const SizedBox(height: 6),
                        Text(
                          "You'll get a notification on each day selected before a subscription renews.",
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: AppTokens.gapItem),
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
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppTokens.gapItem,
                          ),
                          child: Text(
                            "Get notified a few days before a promo price ends, so a plan doesn't quietly jump to the regular rate.",
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
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
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Renewal reminders and promo alerts above fire at this time of day.',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.gapSection),

                  // Savings Offers
                  _sectionLabel('SAVINGS OFFERS'),
                  const SizedBox(height: AppTokens.gapItem),
                  ValueListenableBuilder<bool>(
                    valueListenable: SettingsService().offersEnabled,
                    builder: (_, enabled, __) => _row(
                      'Savings offers',
                      trailing: Switch(
                        value: enabled,
                        activeColor: AppTokens.brandEnd,
                        onChanged: (v) => SettingsService().setOffersEnabled(v),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTokens.gapItem),
                    child: Text(
                      'Offers are downloaded anonymously. What you track never leaves your device. Links may earn us a commission.',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.gapSection),

                  // S4: About
                  _sectionLabel('ABOUT'),
                  const SizedBox(height: AppTokens.gapItem),
                  Center(
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 56,
                      height: 56,
                    ),
                  ),
                  const SizedBox(height: AppTokens.gapItem),
                  _row(
                    'Version',
                    trailing: Text(
                      '1.0.0',
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTokens.textMuted,
                        fontSize: 12.5,
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
                    const SizedBox(height: AppTokens.gapSection),
                    _sectionLabel('DEVELOPER'),
                    const SizedBox(height: AppTokens.gapItem),
                    _row(
                      'Send a real reminder now',
                      onTap: _sendRealReminderNow,
                    ),
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
