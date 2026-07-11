import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/app_model.dart';
import 'offer_relevance.dart';
import 'offers_service.dart';
import 'settings_service.dart';

/// One app's renewal reminder about to fire at a specific offset/time —
/// used to group same-day fires across apps in [NotificationService.rescheduleAll].
class _RenewalFire {
  final AppEntry app;
  final int id;
  final int offset;
  final DateTime notifyAt;
  _RenewalFire(this.app, this.id, this.offset, this.notifyAt);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static String? pendingDeepLinkAppId;

  final _dateFmt = DateFormat('EEEE, MMM d');

  Future<void> init() async {
    tz_data.initializeTimeZones();
    final androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        pendingDeepLinkAppId = response.payload;
      },
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      pendingDeepLinkAppId = launchDetails?.notificationResponse?.payload;
    }
  }

  /// Schedules with exact alarm; falls back to inexact on PlatformException.
  Future<void> _schedule(
    int id,
    String title,
    String body,
    String payload,
    tz.TZDateTime when,
    String channelId,
    String channelName,
  ) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on PlatformException {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<List<(int, int)>> _idsForApp(
    String appId, {
    bool promo = false,
  }) async {
    final base = (appId.hashCode & 0x3FFFFF) * 16;
    final settings = await SettingsService().load();
    final result = <(int, int)>[];
    final start = promo ? 4 : 0;
    for (var i = 0; i < settings.offsets.length && i < 4; i++) {
      result.add((base + start + i, settings.offsets[i]));
    }
    return result;
  }

  DateTime _notificationDate(
    DateTime targetDay,
    int daysBefore,
    int hour,
    int minute,
  ) {
    final d = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      hour,
      minute,
    );
    return d.subtract(Duration(days: daysBefore));
  }

  String _chargeLabel(AppEntry a) {
    if (a.subscriptionCost == null) return '';
    return a.billingCycle == 'yearly'
        ? '\$${a.subscriptionCost!.toStringAsFixed(2)}/yr'
        : '\$${a.subscriptionCost!.toStringAsFixed(2)}/mo';
  }

  String _oldNew(AppEntry a) {
    final old = '\$${a.subscriptionCost?.toStringAsFixed(2) ?? '?'}';
    final newP = '\$${a.regularPrice?.toStringAsFixed(2) ?? '?'}';
    return a.billingCycle == 'yearly' ? '$old → $newP/yr' : '$old → $newP/mo';
  }

  /// Normalizes a billing-cycle amount to its monthly equivalent, so it can
  /// be fairly compared against offer prices (which are always monthly).
  double _monthlyPrice(AppEntry a, double amount) =>
      a.billingCycle == 'yearly' ? amount / 12 : amount;

  /// One app's renewal reminder about to fire at a specific offset/time.
  /// Used by [rescheduleAll] to group same-day fires across apps before
  /// deciding whether each gets its own notification or a combined one.
  Future<void> _scheduleSingleRenewalFire(_RenewalFire f) async {
    final app = f.app;
    final charge = _chargeLabel(app);
    var cheaperCount = 0;
    double? monthlyCost;
    if (app.serviceType != null && SettingsService().offersEnabled.value) {
      monthlyCost = _monthlyPrice(app, app.subscriptionCost!);
      final offers = await OffersService().fetch(enabled: true, force: false);
      cheaperCount = countCheaperOffers(app, offers, monthlyCost);
    }
    final title = f.offset == 1
        ? '${app.name} renews tomorrow'
        : '${app.name} renews ${_dateFmt.format(app.nextRenewalDate!)}';
    final body = f.offset == 1
        ? '$charge charge coming tomorrow. Cancel today if you don\'t need it.'
        : cheaperCount > 0
        ? '$charge will be charged in ${f.offset} days. $cheaperCount ${serviceLabel(app.serviceType!)} plans are currently under \$${monthlyCost!.toStringAsFixed(2)}/mo.'
        : '$charge will be charged in ${f.offset} days. Still using it?';
    await _schedule(
      f.id,
      title,
      body,
      app.id,
      tz.TZDateTime.from(f.notifyAt, tz.local),
      'renewal_channel',
      'Renewal Reminders',
    );
  }

  /// Two or more apps whose renewal reminders would otherwise fire on the
  /// same calendar day get one combined notification instead.
  Future<void> _scheduleCombinedRenewalFires(List<_RenewalFire> fires) async {
    fires.sort((a, b) => a.app.name.compareTo(b.app.name));
    final parts = fires
        .map((f) => '${f.app.name} (${_chargeLabel(f.app)})')
        .join(', ');
    final total = fires.fold<double>(
      0,
      (sum, f) => sum + _monthlyPrice(f.app, f.app.subscriptionCost ?? 0),
    );
    final title = '${fires.length} renewals coming up';
    final body = '$parts — \$${total.toStringAsFixed(2)}/mo total.';
    await _schedule(
      _combinedIdForDay(fires.first.notifyAt),
      title,
      body,
      '',
      tz.TZDateTime.from(fires.first.notifyAt, tz.local),
      'renewal_channel',
      'Renewal Reminders',
    );
  }

  /// Stable per-calendar-day id for combined renewal notifications, well
  /// outside the range used by per-app ids (max ~67,108,855).
  int _combinedIdForDay(DateTime notifyAt) {
    final day = DateTime(notifyAt.year, notifyAt.month, notifyAt.day);
    return 900000000 + (day.millisecondsSinceEpoch ~/ 86400000);
  }

  /// Cancels any combined renewal notifications scheduled for the next few
  /// weeks, so a day that no longer has 2+ apps clustered on it doesn't
  /// leave a stale combined notification behind.
  Future<void> _cancelCombinedRenewalReminders() async {
    final today = DateTime.now();
    for (var i = 0; i < 20; i++) {
      final day = DateTime(today.year, today.month, today.day + i);
      await _plugin.cancel(_combinedIdForDay(day));
    }
  }

  Future<void> schedulePromoReminder(AppEntry app) async {
    if (!app.isPromotionalPrice ||
        app.promotionEndsDate == null ||
        app.subscriptionCost == null)
      return;
    final settings = await SettingsService().load();
    if (!settings.enabled || !settings.promoAlerts) return;

    final endDate = app.promotionEndsDate!;
    final now = DateTime.now();
    final ids = await _idsForApp(app.id, promo: true);

    var cheaperCount = 0;
    double? monthlyRegular;
    if (app.serviceType != null && SettingsService().offersEnabled.value) {
      monthlyRegular = _monthlyPrice(app, app.regularPrice!);
      final offers = await OffersService().fetch(enabled: true, force: false);
      cheaperCount = countCheaperOffers(app, offers, monthlyRegular);
    }

    for (final (id, offset) in ids) {
      final notifyAt = _notificationDate(
        endDate,
        offset,
        settings.hour,
        settings.minute,
      );
      if (!notifyAt.isAfter(now)) continue;
      final title = offset == 1
          ? 'Last day of your ${app.name} promo'
          : '${app.name} promo ends ${_dateFmt.format(endDate)}';
      final body = offset == 1
          ? 'Tomorrow the price rises ${_oldNew(app)}.'
          : cheaperCount > 0
          ? 'Price jumps ${_oldNew(app)} in $offset days. $cheaperCount ${serviceLabel(app.serviceType!)} plans are currently under \$${monthlyRegular!.toStringAsFixed(2)}/mo.'
          : 'Price jumps ${_oldNew(app)} in $offset days. Decide before you\'re charged the full price.';
      await _schedule(
        id,
        title,
        body,
        app.id,
        tz.TZDateTime.from(notifyAt, tz.local),
        'promo_channel',
        'Promo Expiry Alerts',
      );
    }
  }

  Future<void> cancelReminders(String appId) async {
    final base = (appId.hashCode & 0x3FFFFF) * 16;
    for (var i = 0; i < 8; i++) {
      await _plugin.cancel(base + i);
    }
  }

  Future<void> cancelPromoReminders(String appId) async {
    final base = (appId.hashCode & 0x3FFFFF) * 16;
    for (var i = 4; i < 8; i++) {
      await _plugin.cancel(base + i);
    }
  }

  Future<void> rescheduleAll(List<AppEntry> apps) async {
    final active = apps.where((a) => a.isActiveSubscription).toList();

    for (final a in active) {
      await cancelReminders(a.id);
    }
    await _cancelCombinedRenewalReminders();

    final settings = await SettingsService().load();
    if (settings.enabled) {
      final now = DateTime.now();
      final byDay = <DateTime, List<_RenewalFire>>{};
      for (final a in active) {
        if (a.nextRenewalDate == null || a.subscriptionCost == null) continue;
        final ids = await _idsForApp(a.id);
        for (final (id, offset) in ids) {
          final notifyAt = _notificationDate(
            a.nextRenewalDate!,
            offset,
            settings.hour,
            settings.minute,
          );
          if (!notifyAt.isAfter(now)) continue;
          final day = DateTime(notifyAt.year, notifyAt.month, notifyAt.day);
          byDay
              .putIfAbsent(day, () => [])
              .add(_RenewalFire(a, id, offset, notifyAt));
        }
      }
      for (final fires in byDay.values) {
        if (fires.length == 1) {
          await _scheduleSingleRenewalFire(fires.first);
        } else {
          await _scheduleCombinedRenewalFires(fires);
        }
      }
    }

    for (final a in active) {
      await schedulePromoReminder(a);
    }
  }

  Future<void> scheduleTestPlus2() async {
    final now = DateTime.now().add(const Duration(minutes: 2));
    await _schedule(
      9999,
      'Test',
      '+2 min test',
      '',
      tz.TZDateTime.from(now, tz.local),
      'test',
      'Test',
    );
  }

  Future<void> sendDailySummary({
    required int upcomingCount,
    required double upcomingCost,
    required double monthlyTotal,
  }) async {
    await _plugin.show(
      0,
      'Your Subscription Summary',
      '$upcomingCount renewal(s) this week · \$${upcomingCost.toStringAsFixed(2)}\nMonthly total: \$${monthlyTotal.toStringAsFixed(2)}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_summary',
          'Daily Summary',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: false,
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> listPending() async {
    final raw = await _plugin.pendingNotificationRequests();
    return raw
        .map(
          (r) => <String, dynamic>{
            'id': r.id,
            'title': r.title,
            'body': r.body,
          },
        )
        .toList();
  }

  Future<void> requestExactAlarmPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestExactAlarmsPermission();
  }
}
