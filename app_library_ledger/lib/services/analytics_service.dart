import 'package:intl/intl.dart';
import '../models/app_model.dart';
import '../models/spend_ledger_entry.dart';

enum InsightType { warning, info, success, danger }

class ScoreFactor {
  final String label;
  final int points;
  const ScoreFactor({required this.label, required this.points});
}

class SubscriptionInsight {
  final String id;
  final String title;
  final String message;
  final InsightType type;
  final double impactPerMonth;
  final String? entryId;
  final List<String> relatedIds;

  SubscriptionInsight({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.impactPerMonth = 0,
    this.entryId,
    this.relatedIds = const [],
  });
}

class _R {
  final AppEntry entry;
  final DateTime date;
  final String label;
  final double amount;
  _R(this.entry, this.date, this.label, this.amount);
}

class PromoCliffEntry {
  final AppEntry app;
  final double oldCost;
  final double newCost;
  PromoCliffEntry(this.app, this.oldCost, this.newCost);
}

enum CalendarEventKind { renewal, promoEnd, projectedPastBilling }

class CalendarEvent {
  final DateTime date; // date-only (no time component)
  final String appName;
  final String label; // 'Renews' | 'Promo ends' | 'Billed · estimated'
  final double amount; // actual per-cycle charge, not monthly-equivalent
  final String entryId;
  final CalendarEventKind kind;
  final bool isProjected;
  final String? note; // disclaimer text, set only when isProjected
  CalendarEvent({
    required this.date,
    required this.appName,
    required this.label,
    required this.amount,
    required this.entryId,
    required this.kind,
    this.isProjected = false,
    this.note,
  });
}

class CalendarMonthEvents {
  final List<CalendarEvent> all;
  final Map<DateTime, List<CalendarEvent>> byDay; // date-only key
  CalendarMonthEvents(this.all, this.byDay);
}

class MonthSpend {
  final DateTime month; // first of month
  final double confirmed; // real ledger 'billed' entries
  final double estimated; // projected-past-billing, apps without a confirmed entry that month
  MonthSpend(this.month, this.confirmed, this.estimated);
}

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final NumberFormat _fmt = NumberFormat.currency(
    symbol: '\$',
    decimalDigits: 2,
  );
  final DateFormat _monthFmt = DateFormat('MMM d');
  final DateFormat _yearFmt = DateFormat('MMM yyyy');

  double _monthly(AppEntry a) {
    if (a.subscriptionCost == null) return 0;
    return a.billingCycle == 'yearly'
        ? a.subscriptionCost! / 12
        : a.subscriptionCost!;
  }

  double getMonthlyCost(AppEntry app) => _monthly(app);

  double getTotalMonthlyCost(List<AppEntry> apps) => apps
      .where((a) => a.isActiveSubscription)
      .fold(0.0, (s, a) => s + _monthly(a));

  double getYearlyProjection(List<AppEntry> apps) =>
      getTotalMonthlyCost(apps) * 12;

  Map<String, double> getCategoryMonthlyCosts(List<AppEntry> apps) {
    final c = <String, double>{};
    for (final a in apps.where((a) => a.isActiveSubscription)) {
      c[a.category] = (c[a.category] ?? 0) + _monthly(a);
    }
    return c;
  }

  int getActiveSubscriptionCount(List<AppEntry> apps) =>
      apps.where((a) => a.isActiveSubscription).length;

  // ── D1: Promo cliff ──────────────────────────────────────────

  List<PromoCliffEntry> getPromoCliff(List<AppEntry> apps) {
    final n = DateTime.now(), cut = n.add(const Duration(days: 60));
    final res = <PromoCliffEntry>[];
    for (final a in apps.where((a) => a.isActiveSubscription)) {
      if (!a.isPromotionalPrice ||
          a.regularPrice == null ||
          a.promotionEndsDate == null)
        continue;
      if (a.promotionEndsDate!.isBefore(n) || a.promotionEndsDate!.isAfter(cut))
        continue;
      res.add(
        PromoCliffEntry(
          a,
          _monthly(a),
          a.billingCycle == 'yearly' ? a.regularPrice! / 12 : a.regularPrice!,
        ),
      );
    }
    return res;
  }

  double getPromoCliffTotal(List<AppEntry> apps) =>
      getPromoCliff(apps).fold(0.0, (s, c) => s + (c.newCost - c.oldCost));

  // ── D2: Coming-up timeline (30 days) ──────────────────────────

  List<_R> _rangeEvents(List<AppEntry> apps, DateTime start, DateTime end) {
    final entries = <_R>[];
    for (final a in apps.where((a) => a.isActiveSubscription)) {
      if (a.nextRenewalDate != null &&
          !a.nextRenewalDate!.isBefore(start) &&
          !a.nextRenewalDate!.isAfter(end)) {
        entries.add(_R(a, a.nextRenewalDate!, 'Renews', _monthly(a)));
      }
      if (a.isPromotionalPrice &&
          a.promotionEndsDate != null &&
          !a.promotionEndsDate!.isBefore(start) &&
          !a.promotionEndsDate!.isAfter(end) &&
          a.regularPrice != null) {
        final delta =
            (a.billingCycle == 'yearly'
                ? a.regularPrice! / 12
                : a.regularPrice!) -
            _monthly(a);
        if (delta > 0)
          entries.add(_R(a, a.promotionEndsDate!, 'Promo ends', delta));
      }
    }
    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  List<Map<String, dynamic>> getComingUp(List<AppEntry> apps) {
    final n = DateTime.now(), cut = n.add(const Duration(days: 30));
    return _rangeEvents(apps, n, cut)
        .map(
          (e) => <String, dynamic>{
            'date': e.date,
            'name': e.entry.name,
            'label': e.label,
            'amount': e.amount,
            'entryId': e.entry.id,
          },
        )
        .toList();
  }

  // ── D5: Calendar events (renewals, promo cliffs, projected billing history) ──

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int _daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;

  DateTime _monthsBefore(DateTime anchor, int k) {
    final total = anchor.month - 1 - k;
    final y = anchor.year + (total < 0 ? (total - 11) ~/ 12 : total ~/ 12);
    final m = ((total % 12) + 12) % 12 + 1;
    final day = anchor.day.clamp(1, _daysInMonth(y, m));
    return DateTime(y, m, day);
  }

  DateTime _yearsBefore(DateTime anchor, int k) {
    final y = anchor.year - k;
    final day = anchor.day.clamp(1, _daysInMonth(y, anchor.month));
    return DateTime(y, anchor.month, day);
  }

  List<CalendarEvent> _projectedPastBillings(
    List<AppEntry> apps,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final out = <CalendarEvent>[];
    final now = DateTime.now();
    final oneYearAgo = DateTime(now.year - 1, now.month, now.day);
    for (final a in apps.where((a) => a.isActiveSubscription)) {
      if (a.nextRenewalDate == null || a.billingCycle == null) continue;
      final anchor = a.nextRenewalDate!;
      final cutoff = a.createdAt.isAfter(oneYearAgo)
          ? a.createdAt
          : oneYearAgo;
      for (var k = 1; k <= 12; k++) {
        final d = a.billingCycle == 'yearly'
            ? _yearsBefore(anchor, k)
            : _monthsBefore(anchor, k);
        if (d.isBefore(cutoff)) break;
        if (d.isBefore(rangeStart)) break;
        if (d.isAfter(rangeEnd)) continue;
        out.add(
          CalendarEvent(
            date: _dateOnly(d),
            appName: a.name,
            label: 'Billed · estimated',
            amount: a.subscriptionCost ?? 0,
            entryId: a.id,
            kind: CalendarEventKind.projectedPastBilling,
            isProjected: true,
            note: 'Estimated — assumes current price/cycle applied on this date',
          ),
        );
      }
    }
    return out;
  }

  CalendarMonthEvents getCalendarEvents(
    List<AppEntry> apps, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
    List<SpendLedgerEntry> ledger = const [],
  }) {
    final confirmed = _rangeEvents(apps, rangeStart, rangeEnd).map(
      (e) => CalendarEvent(
        date: _dateOnly(e.date),
        appName: e.entry.name,
        label: e.label,
        amount: e.label == 'Renews' ? (e.entry.subscriptionCost ?? 0) : e.amount,
        entryId: e.entry.id,
        kind: e.label == 'Renews'
            ? CalendarEventKind.renewal
            : CalendarEventKind.promoEnd,
      ),
    );

    // Real ledger billing events upgrade what would otherwise be a
    // hollow/estimated dot into a solid/confirmed one for that date.
    final ledgerConfirmed = ledger
        .where(
          (e) =>
              e.kind == LedgerEventKind.billed &&
              !e.date.isBefore(rangeStart) &&
              !e.date.isAfter(rangeEnd),
        )
        .map(
          (e) => CalendarEvent(
            date: _dateOnly(e.date),
            appName: e.appName,
            label: 'Billed',
            amount: e.amount,
            entryId: e.entryId,
            kind: CalendarEventKind.renewal,
          ),
        );
    final confirmedKeys = {
      for (final e in ledgerConfirmed) '${e.entryId}_${e.date}',
    };
    final projected = _projectedPastBillings(
      apps,
      rangeStart,
      rangeEnd,
    ).where((e) => !confirmedKeys.contains('${e.entryId}_${e.date}'));

    final all = [...confirmed, ...ledgerConfirmed, ...projected]
      ..sort((a, b) => a.date.compareTo(b.date));
    final byDay = <DateTime, List<CalendarEvent>>{};
    for (final ev in all) {
      byDay.putIfAbsent(ev.date, () => []).add(ev);
    }
    return CalendarMonthEvents(all, byDay);
  }

  /// Trailing month-by-month spend, most recent first. `confirmed` comes
  /// only from real ledger 'billed' entries; `estimated` comes from the
  /// calendar's projected-past-billing figures, but only for apps that
  /// don't already have a confirmed entry that month — so a subscription
  /// is never counted as both real and guessed in the same month.
  List<MonthSpend> getMonthlySpendHistory(
    List<AppEntry> apps,
    List<SpendLedgerEntry> ledger, {
    int months = 6,
  }) {
    final now = DateTime.now();
    final result = <MonthSpend>[];
    for (var i = 0; i < months; i++) {
      final m = DateTime(now.year, now.month - i, 1);
      final monthEnd = DateTime(m.year, m.month + 1, 0);
      final confirmedEntries = ledger.where(
        (e) =>
            e.kind == LedgerEventKind.billed &&
            e.date.year == m.year &&
            e.date.month == m.month,
      );
      final confirmed = confirmedEntries.fold(0.0, (s, e) => s + e.amount);
      final confirmedAppIds = confirmedEntries.map((e) => e.entryId).toSet();
      final events = getCalendarEvents(apps, rangeStart: m, rangeEnd: monthEnd);
      final estimated = events.all
          .where(
            (e) =>
                e.kind == CalendarEventKind.projectedPastBilling &&
                !confirmedAppIds.contains(e.entryId),
          )
          .fold(0.0, (s, e) => s + e.amount);
      result.add(MonthSpend(m, confirmed, estimated));
    }
    return result;
  }

  // ── D3: Savings tally ────────────────────────────────────────

  double getActivePromoSavings(List<AppEntry> apps) {
    double s = 0;
    for (final a in apps.where(
      (a) =>
          a.isActiveSubscription &&
          a.isPromotionalPrice &&
          a.regularPrice != null,
    )) {
      final m = _monthly(a);
      final r = a.billingCycle == 'yearly'
          ? a.regularPrice! / 12
          : a.regularPrice!;
      s += (r - m).clamp(0, double.infinity);
    }
    return s;
  }

  int getActivePromoCount(List<AppEntry> apps) => apps
      .where(
        (a) =>
            a.isActiveSubscription &&
            a.isPromotionalPrice &&
            a.regularPrice != null,
      )
      .length;

  // ── D4: Expired promos ───────────────────────────────────────

  List<AppEntry> getExpiredPromos(List<AppEntry> apps) {
    final n = DateTime.now();
    return apps
        .where(
          (a) =>
              a.isActiveSubscription &&
              a.isPromotionalPrice &&
              a.promotionEndsDate != null &&
              a.promotionEndsDate!.isBefore(n),
        )
        .toList();
  }

  // ── I4: Scan-check helper — takes installed set, returns uninstalled but paying ──

  List<AppEntry> getUninstalledButPaying(
    List<AppEntry> apps,
    Set<String> installedPackageNames,
  ) {
    if (installedPackageNames.isEmpty) return const [];
    return apps.where((a) {
      if (!a.isActiveSubscription || a.packageName == null) return false;
      return !installedPackageNames.contains(a.packageName);
    }).toList();
  }

  // ── I1+I2: Insights engine (replaces old) ────────────────────

  List<SubscriptionInsight> generateInsights(
    List<AppEntry> apps, {
    Set<String> installed = const {},
    Map<String, int> dismissed = const {},
  }) {
    final all = <SubscriptionInsight>[];
    final n = DateTime.now();
    final active = apps.where((a) => a.isActiveSubscription).toList();
    if (active.isEmpty) {
      all.add(
        SubscriptionInsight(
          id: 'empty',
          title: 'Get Started',
          message: 'Add your first subscription.',
          type: InsightType.info,
        ),
      );
      return all;
    }

    // a) Uninstalled but paying — one card each, unless there are
    // several, in which case they'd otherwise flood the dashboard.
    final uninstalled = getUninstalledButPaying(apps, installed);
    if (uninstalled.length == 1) {
      final a = uninstalled.first;
      all.add(
        SubscriptionInsight(
          id: 'uninstalled_${a.id}',
          title: 'You\'re paying for ${a.name} but it\'s not on your phone',
          message:
              '${_fmt.format(_monthly(a))}/mo for an app no longer installed',
          type: InsightType.danger,
          impactPerMonth: _monthly(a),
          entryId: a.id,
        ),
      );
    } else if (uninstalled.length > 1) {
      final total = uninstalled.fold(0.0, (s, a) => s + _monthly(a));
      all.add(
        SubscriptionInsight(
          id: 'uninstalled_agg',
          title: '${uninstalled.length} uninstalled apps still billing you',
          message: '${_fmt.format(total)}/mo across ${uninstalled.length} apps',
          type: InsightType.danger,
          impactPerMonth: total,
          relatedIds: uninstalled.map((a) => a.id).toList(),
        ),
      );
    }

    // b) Lifetime spend (highest)
    if (active.isNotEmpty) {
      AppEntry? top;
      double topSpend = 0;
      for (final a in active) {
        final months = ((n.difference(a.createdAt).inDays / 30.44).ceil())
            .clamp(1, 999);
        final life = _monthly(a) * months;
        if (life > topSpend) {
          topSpend = life;
          top = a;
        }
      }
      if (top != null && topSpend > 0) {
        all.add(
          SubscriptionInsight(
            id: 'lifetime_${top!.id}',
            title: 'You\'ve spent ~${_fmt.format(topSpend)} on ${top.name}',
            message: 'Since ${_yearFmt.format(top.createdAt)}',
            type: InsightType.info,
            impactPerMonth: _monthly(top),
            entryId: top.id,
          ),
        );
      }
    }

    // c) Spend concentration
    final cats = getCategoryMonthlyCosts(apps);
    final total = getTotalMonthlyCost(apps);
    if (total > 0) {
      for (final e in cats.entries) {
        final pct = e.value / total;
        if (pct > 0.5 && active.where((a) => a.category == e.key).length >= 3) {
          all.add(
            SubscriptionInsight(
              id: 'concentration_${e.key}',
              title: '${(pct * 100).round()}% of your spend is ${e.key}',
              message: '${_fmt.format(e.value)}/mo in one category',
              type: InsightType.warning,
              impactPerMonth: e.value,
            ),
          );
        }
      }
    }

    // d) Biggest line item
    if (active.length >= 2) {
      AppEntry? big;
      double bigM = 0;
      for (final a in active) {
        final m = _monthly(a);
        if (m > bigM) {
          bigM = m;
          big = a;
        }
      }
      if (big != null && bigM > 0) {
        all.add(
          SubscriptionInsight(
            id: 'biggest_${big!.id}',
            title: '${big.name} is ${_fmt.format(bigM)}/mo',
            message:
                'That\'s ${_fmt.format(bigM * 12)}/yr — your biggest subscription',
            type: InsightType.info,
            impactPerMonth: bigM,
            entryId: big.id,
          ),
        );
      }
    }

    // Note: aggregate/per-promo cliff and renewal-cluster insights were
    // removed here — they duplicated exactly what the dashboard's merged
    // "Coming Up" section already shows chronologically. Insights now
    // focus on spend-pattern analysis, not date-driven reminders.

    // Filter dismissed (30 day TTL)
    all.removeWhere((ins) {
      final ts = dismissed[ins.id];
      if (ts == null) return false;
      return (DateTime.now().millisecondsSinceEpoch - ts) < (30 * 86400 * 1000);
    });

    // Sort: impactPerMonth desc, health last
    all.sort((a, b) => b.impactPerMonth.compareTo(a.impactPerMonth));

    // Health score (always last) — skipped for a single, factor-free
    // subscription: "Excellent, no issues" on one app is chrome, not
    // information. Once there's a real factor or a 2nd subscription,
    // it becomes a meaningful portfolio-level signal again.
    final (score, factors) = getSubHealthScore(
      apps,
      uninstalled: uninstalled,
      promos: getPromoCliff(apps),
    );
    if (factors.isNotEmpty || active.length >= 2) {
      final sortedFactors = [...factors]
        ..sort((a, b) => a.points.compareTo(b.points));
      all.add(
        SubscriptionInsight(
          id: 'health_score',
          title: 'Subscription Health: ${getHealthLabel(score)}',
          message: sortedFactors
              .map((f) => '${f.points} · ${f.label}')
              .join('\n'),
          type: score >= 75
              ? InsightType.success
              : score >= 50
              ? InsightType.warning
              : InsightType.danger,
          impactPerMonth: score.toDouble(),
        ),
      );
    }

    return all;
  }

  // ── I5: Explainable health score ─────────────────────────────

  (double, List<ScoreFactor>) getSubHealthScore(
    List<AppEntry> apps, {
    List<AppEntry> uninstalled = const [],
    List<PromoCliffEntry> promos = const [],
  }) {
    final active = apps.where((a) => a.isActiveSubscription).toList();
    if (active.isEmpty) return (100, const []);
    double score = 100;
    final factors = <ScoreFactor>[];

    final monthly = getTotalMonthlyCost(apps);
    if (monthly > 200) {
      score -= 25;
      factors.add(
        const ScoreFactor(label: 'Monthly spend over \$200', points: -25),
      );
    } else if (monthly > 100) {
      score -= 15;
      factors.add(
        const ScoreFactor(label: 'Monthly spend over \$100', points: -15),
      );
    } else if (monthly > 50) {
      score -= 5;
      factors.add(
        const ScoreFactor(label: 'Monthly spend over \$50', points: -5),
      );
    }

    final uCount = (uninstalled.length).clamp(0, 3);
    if (uCount > 0) {
      score -= uCount * 10;
      factors.add(
        ScoreFactor(
          label: '$uCount uninstalled app(s) still being paid',
          points: -(uCount * 10),
        ),
      );
    }

    if (promos.isNotEmpty) {
      score -= promos.length * 5;
      factors.add(
        ScoreFactor(
          label: '${promos.length} promo(s) expiring within 60 days',
          points: -(promos.length * 5),
        ),
      );
    }

    return (score.clamp(0, 100).toDouble(), factors);
  }

  String getHealthLabel(double score) {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Good';
    if (score >= 50) return 'Fair';
    if (score >= 30) return 'Needs Attention';
    return 'Critical';
  }
}
