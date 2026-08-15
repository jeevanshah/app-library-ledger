import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/app_model.dart';
import '../models/category_model.dart';
import '../models/spend_ledger_entry.dart';
import '../services/analytics_service.dart';
import '../theme/app_tokens.dart';
import 'add_app_screen.dart';

class SpendHistoryScreen extends StatefulWidget {
  static const _kMonths = 6;

  final List<AppEntry> apps;
  final List<SpendLedgerEntry> ledger;
  final List<Category> cats;
  const SpendHistoryScreen({
    required this.apps,
    required this.ledger,
    required this.cats,
    super.key,
  });

  @override
  State<SpendHistoryScreen> createState() => _SpendHistoryScreenState();
}

class _SpendHistoryScreenState extends State<SpendHistoryScreen> {
  int _trajectoryMonths = 3;

  Widget _iconBtn(
    BuildContext context,
    IconData icon, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(AppTokens.rIconBtn),
          border: Border.all(color: AppTokens.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: AppTokens.isDark ? 0.18 : 0.03,
              ),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: AppTokens.textPrimary),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.padHeader,
        vertical: 12,
      ),
      child: Row(
        children: [
          _iconBtn(
            context,
            Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Spending History',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  color: AppTokens.textStrong,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 42),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTokens.cardBg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTokens.hairline),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: AppTokens.isDark ? 0.25 : 0.04),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );

  Widget _heroCard() {
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final now = DateTime.now();
    final cutoff = DateTime(
      now.year,
      now.month - SpendHistoryScreen._kMonths + 1,
      1,
    );
    final confirmed = widget.ledger
        .where(
          (e) => e.kind == LedgerEventKind.billed && !e.date.isBefore(cutoff),
        )
        .fold(0.0, (s, e) => s + e.amount);
    final monthsWithData = {
      for (final e in widget.ledger.where(
        (e) => e.kind == LedgerEventKind.billed && !e.date.isBefore(cutoff),
      ))
        '${e.date.year}-${e.date.month}',
    }.length;

    return _card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONFIRMED SPEND · LAST ${SpendHistoryScreen._kMonths} MO',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textFaint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [AppTokens.brandStart, AppTokens.brandEnd],
                  ).createShader(bounds),
                  child: Text(
                    fmt.format(confirmed),
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.brandStart,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  monthsWithData > 0
                      ? '$monthsWithData of ${SpendHistoryScreen._kMonths} months recorded'
                      : 'Your spending history accumulates as you use the app',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTokens.brandStart.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: categoryIcon('Finance', size: 26),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, {bool hollow = false}) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: hollow ? Colors.transparent : color,
      border: hollow ? Border.all(color: color, width: 1.5) : null,
    ),
  );

  Widget _historyCard(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final history = AnalyticsService().getMonthlySpendHistory(
      widget.apps,
      widget.ledger,
      months: SpendHistoryScreen._kMonths,
    );
    final maxValue = history.fold(
      0.0,
      (m, h) => (h.confirmed + h.estimated) > m ? h.confirmed + h.estimated : m,
    );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTokens.brandStart.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: categoryIcon('Finance', size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Monthly Spend',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _legendDot(AppTokens.success),
              const SizedBox(width: 4),
              Text(
                'Paid',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              _legendDot(AppTokens.info, hollow: true),
              const SizedBox(width: 4),
              Text(
                'Est.',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final h in history) ...[
            _monthRow(context, h, maxValue, fmt),
            if (h != history.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _monthRow(
    BuildContext context,
    MonthSpend h,
    double maxValue,
    NumberFormat fmt,
  ) {
    final total = h.confirmed + h.estimated;
    return GestureDetector(
      onTap: total > 0 ? () => _openMonth(context, h) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTokens.hairline),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Text(
                DateFormat('MMM').format(h.month),
                style: GoogleFonts.spaceGrotesk(
                  color: AppTokens.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final trackW = constraints.maxWidth;
                    final cw = maxValue > 0
                        ? trackW * h.confirmed / maxValue
                        : 0.0;
                    final ew = maxValue > 0
                        ? trackW * h.estimated / maxValue
                        : 0.0;
                    return SizedBox(
                      height: 20,
                      width: trackW,
                      child: Stack(
                        children: [
                          Container(
                            width: trackW,
                            height: 20,
                            color: AppTokens.cardBg,
                          ),
                          Container(
                            width: cw,
                            height: 20,
                            decoration: BoxDecoration(
                              color: AppTokens.success,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Positioned(
                            left: cw,
                            child: Container(
                              width: ew,
                              height: 20,
                              decoration: BoxDecoration(
                                color: AppTokens.info.withValues(alpha: 0.18),
                                border: Border.all(
                                  color: AppTokens.info,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 70,
              child: Text(
                fmt.format(total),
                textAlign: TextAlign.right,
                style: GoogleFonts.spaceGrotesk(
                  color: total > 0
                      ? AppTokens.textPrimary
                      : AppTokens.textFaint,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppTokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  void _openMonth(BuildContext context, MonthSpend h) {
    HapticFeedback.selectionClick();
    final monthStart = DateTime(h.month.year, h.month.month, 1);
    final monthEnd = DateTime(h.month.year, h.month.month + 1, 0);
    final confirmedEntries = widget.ledger.where(
      (e) =>
          e.kind == LedgerEventKind.billed &&
          e.date.year == h.month.year &&
          e.date.month == h.month.month,
    );
    final events = AnalyticsService().getCalendarEvents(
      widget.apps,
      rangeStart: monthStart,
      rangeEnd: monthEnd,
    );
    final confirmedAppIds = confirmedEntries.map((e) => e.entryId).toSet();
    final estimatedEvents = events.all.where(
      (e) =>
          e.kind == CalendarEventKind.projectedPastBilling &&
          !confirmedAppIds.contains(e.entryId),
    );
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                  Text(
                    DateFormat('MMMM yyyy').format(h.month),
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.textStrong,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    fmt.format(h.confirmed + h.estimated),
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.brandStart,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final e in confirmedEntries)
                _historyRow(
                  e.appName,
                  e.amount,
                  'Confirmed',
                  AppTokens.success,
                  fmt,
                ),
              for (final e in estimatedEvents)
                _historyRow(
                  e.appName,
                  e.amount,
                  'Estimated',
                  AppTokens.info,
                  fmt,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyRow(
    String name,
    double amount,
    String label,
    Color color,
    NumberFormat fmt,
  ) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTokens.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            fmt.format(amount),
            style: GoogleFonts.spaceGrotesk(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // ── Price Trajectory (forward-looking) ──────────────────────────

  Widget _rangeChip(int months, String label) {
    final selected = _trajectoryMonths == months;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _trajectoryMonths = months);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: selected ? AppTokens.brandGradient : null,
          color: selected ? null : AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(AppTokens.rPill),
          border: Border.all(
            color: selected ? Colors.transparent : AppTokens.hairline,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTokens.brandStart.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: selected ? Colors.white : AppTokens.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _trajectoryCard(BuildContext context) {
    final projection = AnalyticsService().getMonthlyCostProjection(
      widget.apps,
      months: _trajectoryMonths,
    );
    final values = projection.map((p) => p.total).toList();
    final rawMax = values.fold(0.0, (m, v) => v > m ? v : m);
    final rawMin = values.isEmpty
        ? 0.0
        : values.fold(values.first, (m, v) => v < m ? v : m);
    final isFlat = (rawMax - rawMin).abs() < 0.01;
    var pad = 0.0;
    if (isFlat) {
      pad = rawMax * 0.08;
      if (pad < 5.0) pad = 5.0;
      if (pad > 40.0) pad = 40.0;
    }
    final maxValue = rawMax + pad;
    final minValue = rawMin - pad < 0 ? 0.0 : rawMin - pad;
    final axisFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTokens.brandStart.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: flatIcon(
                  'chart_trending_dark',
                  color: AppTokens.brandStart,
                  size: 15,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trajectory',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _rangeChip(1, '1M'),
              const SizedBox(width: 3),
              _rangeChip(3, '3M'),
              const SizedBox(width: 3),
              _rangeChip(6, '6M'),
              const SizedBox(width: 3),
              _rangeChip(12, '1Y'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Projected from tracked promo end dates — not a guarantee',
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textFaint,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 14),
          if (values.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Not enough tracked data yet',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  height: 120,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        axisFmt.format(maxValue),
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTokens.textFaint,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        axisFmt.format(minValue),
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTokens.textFaint,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 120,
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        return GestureDetector(
                          onTapUp: (details) {
                            final dx = constraints.maxWidth /
                                (values.length - 1);
                            final idx = (details.localPosition.dx / dx)
                                .round()
                                .clamp(0, values.length - 1);
                            _openTrajectoryMonth(context, projection[idx]);
                          },
                          child: CustomPaint(
                            size: Size(constraints.maxWidth, 120),
                            painter: _TrajectoryPainter(
                              values: values,
                              minValue: minValue,
                              maxValue: maxValue,
                              cliffFlags: projection
                                  .map((p) => p.cliffedEntryIds.isNotEmpty)
                                  .toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 36),
              for (var i = 0; i < projection.length; i++)
                Expanded(
                  child: Text(
                    DateFormat('MMM').format(projection[i].month),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openTrajectoryMonth(BuildContext context, MonthProjection p) {
    HapticFeedback.selectionClick();
    final active = widget.apps.where((a) => a.isActiveSubscription).toList();
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                  Text(
                    DateFormat('MMMM yyyy').format(p.month),
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.textStrong,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    fmt.format(p.total),
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.brandStart,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Projected spend factoring upcoming promo cliff resets',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              for (final a in active) _trajectoryRow(a, p, fmt),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trajectoryRow(AppEntry a, MonthProjection p, NumberFormat fmt) {
    final cliffed = p.cliffedEntryIds.contains(a.id);
    final usesRegular =
        a.isPromotionalPrice &&
        a.promotionEndsDate != null &&
        a.regularPrice != null &&
        !a.promotionEndsDate!.isAfter(p.month);
    final cost = usesRegular
        ? (a.billingCycle == 'yearly' ? a.regularPrice! / 12 : a.regularPrice!)
        : AnalyticsService().getMonthlyCost(a);

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTokens.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTokens.categoryColor(
                a.category,
              ).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: categoryIcon(a.category, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.name,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (cliffed)
                  Text(
                    'Price rise this month',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.warning,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            fmt.format(cost),
            style: GoogleFonts.spaceGrotesk(
              color: cliffed ? AppTokens.warning : AppTokens.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceChangesCard(BuildContext context) {
    final changes =
        widget.ledger
            .where((e) => e.kind == LedgerEventKind.priceChanged)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    if (changes.isEmpty) return const SizedBox.shrink();
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dateFmt = DateFormat('MMM d, yyyy');

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTokens.brandStart.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: flatIcon(
                  'tag_orange',
                  color: AppTokens.brandStart,
                  size: 15,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Price Changes Log',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final c in changes) ...[
            _priceChangeRow(context, c, fmt, dateFmt),
            if (c != changes.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _priceChangeRow(
    BuildContext context,
    SpendLedgerEntry c,
    NumberFormat fmt,
    DateFormat dateFmt,
  ) {
    final entry = widget.apps.where((a) => a.id == c.entryId).firstOrNull;
    final rose = c.previousAmount != null && c.amount > c.previousAmount!;
    final delta = c.previousAmount != null ? c.amount - c.previousAmount! : 0.0;

    return GestureDetector(
      onTap: entry == null
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AddAppScreen(categories: widget.cats, appToEdit: entry),
              ),
            ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTokens.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.appName,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.previousAmount != null
                        ? 'Was ${fmt.format(c.previousAmount)} → now ${fmt.format(c.amount)}'
                        : 'Now ${fmt.format(c.amount)}',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.textMuted,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateFmt.format(c.date),
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            if (c.previousAmount != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (rose ? AppTokens.warning : AppTokens.success)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
                  border: Border.all(
                    color: (rose ? AppTokens.warning : AppTokens.success)
                        .withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '${rose ? '+' : '−'}${fmt.format(delta.abs())}/mo',
                  style: GoogleFonts.spaceGrotesk(
                    color: rose ? AppTokens.warning : AppTokens.success,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _comingUpCard() {
    final coming = AnalyticsService().getComingUp(widget.apps);
    if (coming.isEmpty) return const SizedBox.shrink();
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dateFmt = DateFormat('MMM d');

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTokens.brandStart.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: flatIcon(
                  'clock_alarm_orange',
                  color: AppTokens.brandStart,
                  size: 15,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Upcoming Charges',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final e in coming.take(5)) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTokens.fieldBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTokens.hairline),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      dateFmt.format(e['date'] as DateTime),
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTokens.brandStart,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${e['name']} · ${e['label']}',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    fmt.format(e['amount'] as double),
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (e != coming.take(5).last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.padContent),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            heroIllustration('piggybank_savings', width: 90, height: 90),
            const SizedBox(height: 16),
            Text(
              'Your spending history builds up here',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textStrong,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Once you track subscriptions, billing events, and price changes, historical trends will automatically plot here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.screenBg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: widget.apps.isEmpty
                  ? _emptyState()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                      children: [
                        _heroCard(),
                        const SizedBox(height: 14),
                        _trajectoryCard(context),
                        const SizedBox(height: 14),
                        _historyCard(context),
                        const SizedBox(height: 14),
                        _priceChangesCard(context),
                        if (widget.ledger.any(
                          (e) => e.kind == LedgerEventKind.priceChanged,
                        ))
                          const SizedBox(height: 14),
                        _comingUpCard(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrajectoryPainter extends CustomPainter {
  final List<double> values;
  final double minValue;
  final double maxValue;
  final List<bool> cliffFlags;

  _TrajectoryPainter({
    required this.values,
    required this.minValue,
    required this.maxValue,
    required this.cliffFlags,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final range = (maxValue - minValue).abs() < 0.01
        ? 1.0
        : (maxValue - minValue);
    final n = values.length;
    final dx = n > 1 ? size.width / (n - 1) : 0.0;

    Offset pointFor(int i) {
      final x = n > 1 ? i * dx : size.width / 2;
      final normalized = (values[i] - minValue) / range;
      final y = (size.height - 12) - normalized * (size.height - 24);
      return Offset(x, y.clamp(8.0, size.height - 8.0));
    }

    final points = List.generate(n, pointFor);

    // Gradient fill under the smooth curve
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cpX = (p0.dx + p1.dx) / 2;
      fillPath.cubicTo(cpX, p0.dy, cpX, p1.dy, p1.dx, p1.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();

    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppTokens.brandStart.withValues(alpha: 0.22),
        AppTokens.brandStart.withValues(alpha: 0.01),
      ],
    );

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = fillGradient.createShader(
          Rect.fromLTWH(0, 0, size.width, size.height),
        )
        ..style = PaintingStyle.fill,
    );

    // Smooth line curve
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cpX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(cpX, p0.dy, cpX, p1.dy, p1.dx, p1.dy);
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = AppTokens.brandStart
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Nodes & Cliff Vertical Dashes
    for (var i = 0; i < n; i++) {
      final p = points[i];
      if (cliffFlags[i]) {
        final dashPaint = Paint()
          ..color = AppTokens.warning.withValues(alpha: 0.6)
          ..strokeWidth = 1.2;
        var y = 0.0;
        while (y < size.height) {
          canvas.drawLine(
            Offset(p.dx, y),
            Offset(p.dx, (y + 4).clamp(0, size.height)),
            dashPaint,
          );
          y += 7;
        }
      }

      // Outer glow
      canvas.drawCircle(
        p,
        6,
        Paint()..color = AppTokens.brandStart.withValues(alpha: 0.25),
      );
      // Inner circle
      canvas.drawCircle(
        p,
        3.5,
        Paint()
          ..color = cliffFlags[i] ? AppTokens.warning : AppTokens.brandStart,
      );
      // Center dot
      canvas.drawCircle(p, 1.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter old) =>
      old.values != values ||
      old.minValue != minValue ||
      old.maxValue != maxValue;
}
