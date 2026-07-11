import 'package:intl/intl.dart';
import '../models/app_model.dart';

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

  SubscriptionInsight({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.impactPerMonth = 0,
    this.entryId,
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

  List<Map<String, dynamic>> getComingUp(List<AppEntry> apps) {
    final n = DateTime.now(), cut = n.add(const Duration(days: 30));
    final entries = <_R>[];
    for (final a in apps.where((a) => a.isActiveSubscription)) {
      if (a.nextRenewalDate != null &&
          a.nextRenewalDate!.isAfter(n) &&
          a.nextRenewalDate!.isBefore(cut)) {
        entries.add(_R(a, a.nextRenewalDate!, 'Renews', _monthly(a)));
      }
      if (a.isPromotionalPrice &&
          a.promotionEndsDate != null &&
          a.promotionEndsDate!.isAfter(n) &&
          a.promotionEndsDate!.isBefore(cut) &&
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
    return entries
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

    // a) Uninstalled but paying
    final uninstalled = getUninstalledButPaying(apps, installed);
    for (final a in uninstalled) {
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

    // Health score (always last)
    final (score, factors) = getSubHealthScore(
      apps,
      uninstalled: uninstalled,
      promos: getPromoCliff(apps),
    );
    all.add(
      SubscriptionInsight(
        id: 'health_score',
        title: 'Subscription Health: ${getHealthLabel(score)}',
        message: factors.map((f) => '${f.points} · ${f.label}').join('\n'),
        type: score >= 75
            ? InsightType.success
            : score >= 50
            ? InsightType.warning
            : InsightType.danger,
        impactPerMonth: score.toDouble(),
      ),
    );

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
