import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/app_model.dart';
import 'settings_service.dart';

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

  Future<void> scheduleRenewalReminder(AppEntry app) async {
    if (app.nextRenewalDate == null ||
        !app.isActiveSubscription ||
        app.subscriptionCost == null)
      return;
    final settings = await SettingsService().load();
    if (!settings.enabled) return;

    final renewalDate = app.nextRenewalDate!;
    final now = DateTime.now();
    final ids = await _idsForApp(app.id);
    final charge = _chargeLabel(app);

    for (final (id, offset) in ids) {
      final notifyAt = _notificationDate(
        renewalDate,
        offset,
        settings.hour,
        settings.minute,
      );
      if (!notifyAt.isAfter(now)) continue;
      final title = offset == 1
          ? '${app.name} renews tomorrow'
          : '${app.name} renews ${_dateFmt.format(renewalDate)}';
      final body = offset == 1
          ? '$charge charge coming tomorrow. Cancel today if you don\'t need it.'
          : '$charge will be charged in $offset days. Still using it?';
      await _schedule(
        id,
        title,
        body,
        app.id,
        tz.TZDateTime.from(notifyAt, tz.local),
        'renewal_channel',
        'Renewal Reminders',
      );
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
    for (final a in apps.where((a) => a.isActiveSubscription)) {
      await cancelReminders(a.id);
      await scheduleRenewalReminder(a);
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
