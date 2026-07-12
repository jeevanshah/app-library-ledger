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

  Widget _iconBtn(BuildContext context, IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(AppTokens.rIconBtn),
          border: Border.all(color: AppTokens.hairline),
        ),
        child: Icon(icon, size: 20, color: AppTokens.textPrimary),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.padHeader,
        vertical: 14,
      ),
      child: Row(
        children: [
          _iconBtn(
            context,
            Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
          ),
          Expanded(
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
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTokens.cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTokens.hairline),
    ),
    child: child,
  );

  Widget _heroCard() {
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month - SpendHistoryScreen._kMonths + 1, 1);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CONFIRMED SPEND · LAST ${SpendHistoryScreen._kMonths} MO',
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textFaint,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fmt.format(confirmed),
            style: GoogleFonts.playfairDisplay(
              color: confirmed > 0 ? AppTokens.gold : AppTokens.textFaint,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            monthsWithData > 0
                ? '$monthsWithData of ${SpendHistoryScreen._kMonths} months tracked'
                : 'Your spending history builds up from here',
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, {bool hollow = false}) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: hollow ? Colors.transparent : color,
      border: hollow ? Border.all(color: color, width: 1.2) : null,
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
              Text(
                'History',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _legendDot(AppTokens.success),
              const SizedBox(width: 4),
              Text(
                'Confirmed',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 10.5,
                ),
              ),
              const SizedBox(width: 10),
              _legendDot(AppTokens.info, hollow: true),
              const SizedBox(width: 4),
              Text(
                'Estimated',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final h in history) ...[
            _monthRow(context, h, maxValue, fmt),
            if (h != history.last) const SizedBox(height: 8),
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
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              DateFormat('MMM').format(h.month),
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
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
                  final cw = maxValue > 0 ? trackW * h.confirmed / maxValue : 0.0;
                  final ew = maxValue > 0 ? trackW * h.estimated / maxValue : 0.0;
                  return SizedBox(
                    height: 24,
                    width: trackW,
                    child: Stack(
                      children: [
                        Container(width: trackW, height: 24, color: AppTokens.fieldBg),
                        Container(width: cw, height: 24, color: AppTokens.success),
                        Positioned(
                          left: cw,
                          child: Container(
                            width: ew,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppTokens.info.withValues(alpha: 0.15),
                              border: Border.all(color: AppTokens.info, width: 1),
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
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              fmt.format(total),
              textAlign: TextAlign.right,
              style: GoogleFonts.spaceGrotesk(
                color: total > 0 ? AppTokens.textPrimary : AppTokens.textFaint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
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
      backgroundColor: AppTokens.cardBgRaised,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTokens.hairlineStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                DateFormat('MMMM yyyy').format(h.month),
                style: GoogleFonts.playfairDisplay(
                  color: AppTokens.textStrong,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppTokens.gapItem),
              for (final e in confirmedEntries)
                _historyRow(e.appName, e.amount, 'Confirmed', AppTokens.success, fmt),
              for (final e in estimatedEvents)
                _historyRow(e.appName, e.amount, 'Estimated', AppTokens.info, fmt),
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
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(color: color, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            fmt.format(amount),
            style: GoogleFonts.spaceGrotesk(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppTokens.gold.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.rPill),
          border: Border.all(
            color: selected ? AppTokens.gold.withValues(alpha: 0.4) : AppTokens.hairline,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: selected ? AppTokens.gold : AppTokens.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
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
    final maxValue = values.fold(0.0, (m, v) => v > m ? v : m);
    final minValue = values.isEmpty
        ? 0.0
        : values.fold(values.first, (m, v) => v < m ? v : m);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Price Trajectory',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _rangeChip(1, '1M'),
              const SizedBox(width: 6),
              _rangeChip(3, '3M'),
              const SizedBox(width: 6),
              _rangeChip(6, '6M'),
              const SizedBox(width: 6),
              _rangeChip(12, '1Y'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Projected from tracked promo end dates — not a guarantee',
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textFaint,
              fontSize: 10.5,
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
            SizedBox(
              height: 120,
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  return GestureDetector(
                    onTapUp: (details) {
                      final dx = constraints.maxWidth / (values.length - 1);
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
                        cliffFlags: projection.map((p) => p.cliffedEntryIds.isNotEmpty).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < projection.length; i++)
                Expanded(
                  child: Text(
                    DateFormat('MMM').format(projection[i].month),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textFaint,
                      fontSize: 10,
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
      backgroundColor: AppTokens.cardBgRaised,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTokens.hairlineStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                DateFormat('MMMM yyyy').format(p.month),
                style: GoogleFonts.playfairDisplay(
                  color: AppTokens.textStrong,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Projected total: ${fmt.format(p.total)}',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppTokens.gapItem),
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
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTokens.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.name,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (cliffed)
                  Text(
                    'Price rise this month',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.warning,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            fmt.format(cost),
            style: GoogleFonts.spaceGrotesk(
              color: cliffed ? AppTokens.warning : AppTokens.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceChangesCard(BuildContext context) {
    final changes = widget.ledger.where((e) => e.kind == LedgerEventKind.priceChanged).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (changes.isEmpty) return const SizedBox.shrink();
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dateFmt = DateFormat('MMM d');

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Price Changes',
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
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
                builder: (_) => AddAppScreen(categories: widget.cats, appToEdit: entry),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.appName,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (c.previousAmount != null)
                Text(
                  '${rose ? '+' : '−'}${fmt.format(delta.abs())}/mo',
                  style: GoogleFonts.plusJakartaSans(
                    color: rose ? AppTokens.warning : AppTokens.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
        ],
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
          Text(
            'Coming Up',
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final e in coming.take(5)) ...[
            Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    dateFmt.format(e['date'] as DateTime),
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${e['name']} · ${e['label']}',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  fmt.format(e['amount'] as double),
                  style: GoogleFonts.spaceGrotesk(
                    color: AppTokens.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
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
            Icon(
              Icons.query_stats_rounded,
              size: 40,
              color: AppTokens.textFaint.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Your spending history builds up from here',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: AppTokens.textStrong,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Once you track a subscription, real billing events and price changes will appear here automatically.',
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
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
                      children: [
                        _heroCard(),
                        const SizedBox(height: 14),
                        _historyCard(context),
                        const SizedBox(height: 14),
                        _trajectoryCard(context),
                        const SizedBox(height: 14),
                        _priceChangesCard(context),
                        if (widget.ledger.any((e) => e.kind == LedgerEventKind.priceChanged))
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
    final range = (maxValue - minValue).abs() < 0.01 ? 1.0 : (maxValue - minValue);
    final n = values.length;
    final dx = n > 1 ? size.width / (n - 1) : 0.0;

    Offset pointFor(int i) {
      final x = n > 1 ? i * dx : size.width / 2;
      final normalized = (values[i] - minValue) / range;
      final y = (size.height - 8) - normalized * (size.height - 16);
      return Offset(x, y.clamp(4.0, size.height - 4.0));
    }

    final points = List.generate(n, pointFor);

    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = AppTokens.gold.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = AppTokens.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (var i = 0; i < n; i++) {
      final p = points[i];
      if (cliffFlags[i]) {
        final dashPaint = Paint()
          ..color = AppTokens.warning.withValues(alpha: 0.5)
          ..strokeWidth = 1;
        var y = 0.0;
        while (y < size.height) {
          canvas.drawLine(Offset(p.dx, y), Offset(p.dx, (y + 4).clamp(0, size.height)), dashPaint);
          y += 7;
        }
      }
      canvas.drawCircle(p, 3.5, Paint()..color = AppTokens.gold);
    }
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter old) =>
      old.values != values || old.minValue != minValue || old.maxValue != maxValue;
}
