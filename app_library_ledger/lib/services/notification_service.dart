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

  NotificationDetails _details(String channelId, String channelName) =>
      NotificationDetails(
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
    final details = _details(channelId, channelName);
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

  /// The next time the user's configured notification hour/minute
  /// occurs — today if it hasn't passed yet, otherwise tomorrow. Used
  /// by the "just caught up" backstops so they land at a predictable
  /// time instead of firing the instant the app happens to open.
  DateTime _nextOccurrence(int hour, int minute) {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
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

  /// Builds the title/body a renewal reminder for [app] would show,
  /// [offset] days before its real `nextRenewalDate`. Shared by the real
  /// scheduled reminder ([_scheduleSingleRenewalFire]) and
  /// [sendRealReminderNow], so a manual on-device check always shows
  /// exactly what a real reminder would say.
  Future<(String, String)> _renewalContent(AppEntry app, int offset) async {
    final charge = _chargeLabel(app);
    var cheaperCount = 0;
    double? monthlyCost;
    if (app.serviceType != null && SettingsService().offersEnabled.value) {
      monthlyCost = _monthlyPrice(app, app.subscriptionCost!);
      final offers = await OffersService().fetch(enabled: true, force: false);
      cheaperCount = countCheaperOffers(app, offers, monthlyCost);
    }
    final title = offset <= 1
        ? '${app.name} renews tomorrow'
        : '${app.name} renews ${_dateFmt.format(app.nextRenewalDate!)}';
    final body = offset <= 1
        ? '$charge charge coming tomorrow. Cancel today if you don\'t need it.'
        : cheaperCount > 0
        ? '$charge will be charged in $offset days. $cheaperCount ${serviceLabel(app.serviceType!)} plans are currently under \$${monthlyCost!.toStringAsFixed(2)}/mo.'
        : '$charge will be charged in $offset days. Still using it?';
    return (title, body);
  }

  /// Stable id for the day-of "renewed" notification — the next free
  /// slot in this app's 16-id block (0-3 renewal offsets, 4-7 promo
  /// offsets, 8 promo day-of/backstop, 9 this one). Also used by
  /// [announceRenewalCaughtUp] for its backstop, same replace-in-place
  /// trick as the promo day-of/backstop pair.
  int _renewalDoneId(String appId) => (appId.hashCode & 0x3FFFFF) * 16 + 9;

  /// Builds the title/body for a "you were charged" renewal
  /// confirmation. Unlike promo, a normal renewal's price doesn't
  /// change, so this is one fixed message shared by both the day-of
  /// schedule ([rescheduleAll]) and the backstop ([announceRenewalCaughtUp]).
  Future<(String, String)> _renewalDoneContent(AppEntry app) async =>
      ('${app.name} renewed', '${_chargeLabel(app)} charged.');

  /// One app's renewal reminder about to fire at a specific offset/time.
  /// Used by [rescheduleAll] to group same-day fires across apps before
  /// deciding whether each gets its own notification or a combined one.
  Future<void> _scheduleSingleRenewalFire(_RenewalFire f) async {
    final (title, body) = await _renewalContent(f.app, f.offset);
    await _schedule(
      f.id,
      title,
      body,
      f.app.id,
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

  /// Builds the title/body a promo-expiry reminder for [app] would show,
  /// [offset] days before its real `promotionEndsDate` ([endDate]).
  /// Shared by the real scheduled reminder ([schedulePromoReminder]) and
  /// [sendRealReminderNow].
  Future<(String, String)> _promoContent(
    AppEntry app,
    int offset,
    DateTime endDate,
  ) async {
    var cheaperCount = 0;
    double? monthlyRegular;
    if (app.serviceType != null && SettingsService().offersEnabled.value) {
      monthlyRegular = _monthlyPrice(app, app.regularPrice!);
      final offers = await OffersService().fetch(enabled: true, force: false);
      cheaperCount = countCheaperOffers(app, offers, monthlyRegular);
    }
    final title = offset <= 1
        ? 'Last day of your ${app.name} promo'
        : '${app.name} promo ends ${_dateFmt.format(endDate)}';
    final body = offset <= 1
        ? 'Tomorrow the price rises ${_oldNew(app)}.'
        : cheaperCount > 0
        ? 'Price jumps ${_oldNew(app)} in $offset days. $cheaperCount ${serviceLabel(app.serviceType!)} plans are currently under \$${monthlyRegular!.toStringAsFixed(2)}/mo.'
        : 'Price jumps ${_oldNew(app)} in $offset days. Decide before you\'re charged the full price.';
    return (title, body);
  }

  /// Stable id for the day-of "promo ended" notification — the slot
  /// right after the 4 offset-based promo reminders (base+4..base+7),
  /// still inside this app's 16-id block. Also used by
  /// [announcePromoGraduated] for the reactive backstop, so if the
  /// scheduled one already fired and is sitting in the shade, the
  /// backstop updates it in place instead of stacking a duplicate.
  int _promoEndedId(String appId) => (appId.hashCode & 0x3FFFFF) * 16 + 8;

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
      final (title, body) = await _promoContent(app, offset, endDate);
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

    // Day-of notification: the offsets above are all advance warnings
    // (7 days before, 1 day before, ...) -- nothing previously fired
    // on the actual day the price changes.
    final dayOfAt = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      settings.hour,
      settings.minute,
    );
    if (dayOfAt.isAfter(now)) {
      await _schedule(
        _promoEndedId(app.id),
        '${app.name} promo ends today',
        'Price moves ${_oldNew(app)} today.',
        app.id,
        tz.TZDateTime.from(dayOfAt, tz.local),
        'promo_channel',
        'Promo Expiry Alerts',
      );
    }
  }

  /// Backstop for the Library screen's auto-graduation: if the
  /// scheduled day-of notification above didn't fire (app closed,
  /// exact alarm permission denied, reinstalled, a backdated entry,
  /// etc.), this covers it the next time the app opens and catches an
  /// already-expired promo. Scheduled for the next occurrence of the
  /// user's configured notification time rather than shown instantly,
  /// so it lands predictably instead of at a random app-open moment —
  /// and shares an id with the day-of schedule above, so whichever
  /// fires last simply replaces the pending one.
  Future<void> announcePromoGraduated(AppEntry app) async {
    final settings = await SettingsService().load();
    if (!settings.enabled || !settings.promoAlerts) return;
    final cycleLabel = app.billingCycle == 'yearly' ? '/yr' : '/mo';
    final body = app.subscriptionCost != null
        ? 'Now \$${app.subscriptionCost!.toStringAsFixed(2)}$cycleLabel.'
        : 'Price has moved to the regular rate.';
    await _schedule(
      _promoEndedId(app.id),
      '${app.name} promo ended',
      body,
      app.id,
      tz.TZDateTime.from(
        _nextOccurrence(settings.hour, settings.minute),
        tz.local,
      ),
      'promo_channel',
      'Promo Expiry Alerts',
    );
  }

  /// Backstop for `StorageService.reconcileBilling()`: fires when it
  /// catches an already-overdue `nextRenewalDate` on app launch (app
  /// closed past the renewal day, missed alarm, etc.) and rolls it
  /// forward. Same next-occurrence scheduling and id-sharing trick as
  /// [announcePromoGraduated].
  Future<void> announceRenewalCaughtUp(AppEntry app) async {
    final settings = await SettingsService().load();
    if (!settings.enabled) return;
    final (title, body) = await _renewalDoneContent(app);
    await _schedule(
      _renewalDoneId(app.id),
      title,
      body,
      app.id,
      tz.TZDateTime.from(
        _nextOccurrence(settings.hour, settings.minute),
        tz.local,
      ),
      'renewal_channel',
      'Renewal Reminders',
    );
  }

  Future<void> cancelReminders(String appId) async {
    final base = (appId.hashCode & 0x3FFFFF) * 16;
    for (var i = 0; i < 10; i++) {
      await _plugin.cancel(base + i);
    }
  }

  Future<void> cancelPromoReminders(String appId) async {
    final base = (appId.hashCode & 0x3FFFFF) * 16;
    for (var i = 4; i < 9; i++) {
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

        // Day-of notification: the offsets above are all advance
        // warnings -- nothing previously fired on the actual renewal
        // day. Kept separate from the same-day combine-into-one
        // grouping above, same as promo's day-of.
        final dayOfAt = DateTime(
          a.nextRenewalDate!.year,
          a.nextRenewalDate!.month,
          a.nextRenewalDate!.day,
          settings.hour,
          settings.minute,
        );
        if (dayOfAt.isAfter(now)) {
          final (title, body) = await _renewalDoneContent(a);
          await _schedule(
            _renewalDoneId(a.id),
            title,
            body,
            a.id,
            tz.TZDateTime.from(dayOfAt, tz.local),
            'renewal_channel',
            'Renewal Reminders',
          );
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

  /// Picks a real subscription with enough data to build a genuine
  /// reminder — an active promo ending soonest, or failing that the
  /// soonest renewal — and shows that exact notification right now
  /// (same content-building code as the real scheduled reminders, just
  /// displayed immediately instead of scheduled for its real offset
  /// date). Returns the app name used, or null if nothing in the
  /// library has enough data to build one.
  Future<String?> sendRealReminderNow(List<AppEntry> apps) async {
    final active = apps.where((a) => a.isActiveSubscription).toList();
    final now = DateTime.now();

    final promoCandidates =
        active.where((a) =>
            a.isPromotionalPrice &&
            a.promotionEndsDate != null &&
            a.promotionEndsDate!.isAfter(now) &&
            a.subscriptionCost != null &&
            a.regularPrice != null).toList()
          ..sort(
            (a, b) => a.promotionEndsDate!.compareTo(b.promotionEndsDate!),
          );

    if (promoCandidates.isNotEmpty) {
      final app = promoCandidates.first;
      final endDate = app.promotionEndsDate!;
      final offset = endDate.difference(now).inDays.clamp(1, 999);
      final (title, body) = await _promoContent(app, offset, endDate);
      await _plugin.show(
        888888888,
        title,
        body,
        _details('promo_channel', 'Promo Expiry Alerts'),
      );
      return app.name;
    }

    final renewalCandidates =
        active.where((a) =>
            a.nextRenewalDate != null &&
            a.nextRenewalDate!.isAfter(now) &&
            a.subscriptionCost != null).toList()
          ..sort((a, b) => a.nextRenewalDate!.compareTo(b.nextRenewalDate!));

    if (renewalCandidates.isNotEmpty) {
      final app = renewalCandidates.first;
      final offset = app.nextRenewalDate!.difference(now).inDays.clamp(1, 999);
      final (title, body) = await _renewalContent(app, offset);
      await _plugin.show(
        888888888,
        title,
        body,
        _details('renewal_channel', 'Renewal Reminders'),
      );
      return app.name;
    }

    return null;
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
