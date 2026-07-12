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

class CalendarScreen extends StatefulWidget {
  final List<AppEntry> apps;
  final List<Category> cats;
  final List<SpendLedgerEntry> ledger;
  const CalendarScreen({
    required this.apps,
    required this.cats,
    this.ledger = const [],
    super.key,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  void _prevMonth() {
    HapticFeedback.selectionClick();
    setState(
      () => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1),
    );
  }

  void _nextMonth() {
    HapticFeedback.selectionClick();
    setState(
      () => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1),
    );
  }

  List<DateTime?> _buildGridDays(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Mon=1..Sun=7 -> 0..6
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(leadingBlanks, null),
      for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  Color _dotColor(CalendarEventKind kind) => switch (kind) {
    CalendarEventKind.renewal => AppTokens.success,
    CalendarEventKind.promoEnd => AppTokens.warning,
    CalendarEventKind.projectedPastBilling => AppTokens.info,
  };

  Widget _dot(CalendarEventKind kind, {double size = 5}) {
    final color = _dotColor(kind);
    final hollow = kind == CalendarEventKind.projectedPastBilling;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow ? Colors.transparent : color,
        border: hollow ? Border.all(color: color, width: 1.2) : null,
      ),
    );
  }

  void _openDay(DateTime day, List<CalendarEvent> events) {
    HapticFeedback.selectionClick();
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
                DateFormat('EEEE, MMM d').format(day),
                style: GoogleFonts.playfairDisplay(
                  color: AppTokens.textStrong,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppTokens.gapItem),
              ...events.map(_dayEventRow),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayEventRow(CalendarEvent e) {
    final entry = widget.apps.where((a) => a.id == e.entryId).firstOrNull;
    return GestureDetector(
      onTap: entry == null
          ? null
          : () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AddAppScreen(categories: widget.cats, appToEdit: entry),
                ),
              );
            },
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTokens.hairline)),
        ),
        child: Row(
          children: [
            _dot(e.kind, size: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.appName,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    e.isProjected ? (e.note ?? e.label) : e.label,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _fmt.format(e.amount),
              style: GoogleFonts.spaceGrotesk(
                color: _dotColor(e.kind),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, {required VoidCallback onTap}) {
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

  void _goToToday() {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    setState(() => _visibleMonth = DateTime(now.year, now.month));
  }

  Widget _header() {
    final now = DateTime.now();
    final isCurrentMonth =
        _visibleMonth.year == now.year && _visibleMonth.month == now.month;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.padHeader,
        vertical: 14,
      ),
      child: Row(
        children: [
          _iconBtn(Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
          Expanded(
            child: Text(
              'Calendar',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textStrong,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          isCurrentMonth
              ? const SizedBox(width: 44)
              : _iconBtn(Icons.today_rounded, onTap: _goToToday),
        ],
      ),
    );
  }

  Widget _monthNav() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.padHeader),
      child: Row(
        children: [
          GestureDetector(
            onTap: _prevMonth,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(
                Icons.chevron_left_rounded,
                color: AppTokens.textPrimary,
                size: 22,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('MMMM yyyy').format(_visibleMonth),
                style: GoogleFonts.playfairDisplay(
                  color: AppTokens.textStrong,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: _nextMonth,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(
                Icons.chevron_right_rounded,
                color: AppTokens.textPrimary,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(CalendarEventKind kind, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(kind, size: 7),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: AppTokens.textMuted,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }

  Widget _legend() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.padHeader,
        vertical: 12,
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          _legendItem(CalendarEventKind.renewal, 'Renewal'),
          _legendItem(CalendarEventKind.promoEnd, 'Promo ends'),
          _legendItem(CalendarEventKind.projectedPastBilling, 'Projected'),
        ],
      ),
    );
  }

  int _todayRowIndex(List<DateTime?> cells, bool isCurrentMonth, DateTime now) {
    if (!isCurrentMonth) return -1;
    final idx = cells.indexWhere(
      (d) => d != null && d.year == now.year && d.month == now.month && d.day == now.day,
    );
    return idx == -1 ? -1 : idx ~/ 7;
  }

  Widget _weekRow(
    int w,
    List<DateTime?> cells,
    Map<DateTime, List<CalendarEvent>> byDay, {
    required bool isCurrentWeekRow,
  }) {
    final row = Row(
      children: [
        for (var i = 0; i < 7; i++) Expanded(child: _dayCell(cells[w * 7 + i], byDay)),
      ],
    );
    if (!isCurrentWeekRow) return row;
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.hairlineStrong,
        borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
      ),
      child: row,
    );
  }

  Widget _summaryLine(CalendarMonthEvents events) {
    if (events.all.isEmpty) return const SizedBox.shrink();

    final renewals = events.all.where((e) => e.kind == CalendarEventKind.renewal).toList();
    final promoEnds = events.all.where((e) => e.kind == CalendarEventKind.promoEnd).toList();
    final projected = events.all
        .where((e) => e.kind == CalendarEventKind.projectedPastBilling)
        .toList();

    final confirmedTotal = renewals.fold(0.0, (s, e) => s + e.amount);
    final promoDeltaTotal = promoEnds.fold(0.0, (s, e) => s + e.amount);
    final baseStyle = GoogleFonts.plusJakartaSans(
      color: AppTokens.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );

    final spans = <InlineSpan>[];
    void sep() {
      if (spans.isNotEmpty) spans.add(TextSpan(text: '  ·  ', style: baseStyle));
    }

    if (renewals.isNotEmpty) {
      sep();
      spans.add(
        TextSpan(
          text:
              '${renewals.length} renewal${renewals.length == 1 ? '' : 's'} · ${_fmt.format(confirmedTotal)}'
              '${projected.isNotEmpty ? ' confirmed' : ' this month'}',
          style: baseStyle.copyWith(color: AppTokens.success, fontWeight: FontWeight.w700),
        ),
      );
    }
    if (promoEnds.isNotEmpty) {
      sep();
      spans.add(
        TextSpan(
          text:
              '${promoEnds.length} promo${promoEnds.length == 1 ? '' : 's'} ending '
              '(+${_fmt.format(promoDeltaTotal)}/mo after)',
          style: baseStyle.copyWith(color: AppTokens.warning, fontWeight: FontWeight.w700),
        ),
      );
    }
    if (projected.isNotEmpty) {
      sep();
      final noConfirmed = renewals.isEmpty && promoEnds.isEmpty;
      spans.add(
        TextSpan(
          text: noConfirmed
              ? '${projected.length} estimated billing event${projected.length == 1 ? '' : 's'} · no confirmed charges this month'
              : '${projected.length} estimated',
          style: baseStyle.copyWith(color: AppTokens.info, fontWeight: FontWeight.w600),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.padHeader, vertical: 2),
      child: Text.rich(
        TextSpan(children: spans),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      ),
    );
  }

  Widget _weekdayRow() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: labels
          .map(
            (d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textFaint,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _dayCell(DateTime? day, Map<DateTime, List<CalendarEvent>> byDay) {
    if (day == null) return const SizedBox(height: 52);
    final today = DateTime.now();
    final isToday =
        day.year == today.year && day.month == today.month && day.day == today.day;
    final events = byDay[day] ?? const <CalendarEvent>[];
    final kinds = {for (final e in events) e.kind}.toList();

    final numberText = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: isToday
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTokens.gold, width: 1.5),
            )
          : null,
      child: Text(
        '${day.day}',
        style: GoogleFonts.spaceGrotesk(
          color: isToday ? AppTokens.gold : AppTokens.textPrimary,
          fontSize: 13,
          fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );

    final cell = SizedBox(
      height: 52,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          numberText,
          const SizedBox(height: 3),
          SizedBox(
            height: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < kinds.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  _dot(kinds[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (events.isEmpty) return cell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDay(day, events),
      child: cell,
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final monthEnd = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0);
    final calendarEvents = AnalyticsService().getCalendarEvents(
      widget.apps,
      rangeStart: monthStart,
      rangeEnd: monthEnd,
      ledger: widget.ledger,
    );
    final cells = _buildGridDays(_visibleMonth);
    final monthLabel = DateFormat('MMMM').format(_visibleMonth);
    final now = DateTime.now();
    final isCurrentMonth =
        _visibleMonth.year == now.year && _visibleMonth.month == now.month;
    final todayRow = _todayRowIndex(cells, isCurrentMonth, now);

    return Scaffold(
      backgroundColor: AppTokens.screenBg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            _monthNav(),
            _summaryLine(calendarEvents),
            const SizedBox(height: 8),
            GestureDetector(
              onHorizontalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v < -200) _nextMonth();
                if (v > 200) _prevMonth();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.padHeader,
                ),
                child: Column(
                  children: [
                    _weekdayRow(),
                    const SizedBox(height: 4),
                    for (var w = 0; w < cells.length ~/ 7; w++)
                      _weekRow(
                        w,
                        cells,
                        calendarEvents.byDay,
                        isCurrentWeekRow: w == todayRow,
                      ),
                  ],
                ),
              ),
            ),
            if (calendarEvents.all.isEmpty) ...[
              const SizedBox(height: 24),
              Icon(
                Icons.event_available_rounded,
                color: AppTokens.textFaint,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                'No billing events in $monthLabel',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 13,
                ),
              ),
            ],
            const Spacer(),
            _legend(),
          ],
        ),
      ),
    );
  }
}
