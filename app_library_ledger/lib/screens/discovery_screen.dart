import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/app_model.dart';
import '../models/catalog_entry.dart';
import '../services/catalog_service.dart';
import '../services/subscription_scanner.dart';
import '../services/storage_service.dart';
import '../services/app_icon_service.dart';
import '../theme/app_tokens.dart';

class DiscoveryScreen extends StatefulWidget {
  final bool fromOnboarding;
  const DiscoveryScreen({super.key, this.fromOnboarding = true});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _selected = <CatalogEntry>{};
  List<CatalogEntry> _detected = [];
  List<CatalogEntry> _webEntries = [];
  List<AppEntry> _existingApps = [];
  bool _scanning = true;
  bool _saving = false;

  bool _isAlreadyAdded(CatalogEntry entry) => entry.isTrackedIn(_existingApps);

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final catalog = CatalogService();
    await catalog.loadCatalog();
    _webEntries = catalog.webManualEntries;

    // Load existing apps for deduplication
    _existingApps = await StorageService().getApps();

    final detected = await SubscriptionScanner.scanDevice();
    if (detected.isNotEmpty) {
      final pkgNames = detected
          .where((e) => e.packageName != null)
          .map((e) => e.packageName!)
          .toList();
      if (pkgNames.isNotEmpty) {
        await AppIconService().loadIcons(pkgNames);
      }
    }
    if (!mounted) return;
    setState(() {
      // Exclude entries already tracked, so they can't be re-added as duplicates
      _detected = detected.where((e) => !_isAlreadyAdded(e)).toList();
      _selected.addAll(_detected);
      _webEntries = _webEntries.where((e) => !_isAlreadyAdded(e)).toList();
      _scanning = false;
    });
  }

  void _toggle(CatalogEntry entry) {
    setState(() {
      if (_selected.contains(entry)) {
        _selected.remove(entry);
      } else {
        _selected.add(entry);
      }
    });
  }

  Future<void> _confirm() async {
    if (_saving) return;
    HapticFeedback.mediumImpact();

    final toSave = _selected.where((e) => !_isAlreadyAdded(e)).toList();
    if (toSave.isEmpty) return;

    final reviewed = await showModalBottomSheet<List<AppEntry>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScanReviewSheet(entries: toSave),
    );
    if (reviewed == null || !mounted) return;

    setState(() => _saving = true);
    final storage = StorageService();
    for (final app in reviewed) {
      await storage.saveApp(app);
    }

    if (!mounted) return;
    if (widget.fromOnboarding) {
      Navigator.of(context).pushReplacementNamed('/library');
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.screenBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FIRST-TIME SETUP',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textFaint,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Discover subscriptions',
                        style: GoogleFonts.playfairDisplay(
                          color: AppTokens.textStrong,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // A3: 48px minimum hit area on Skip link
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (widget.fromOnboarding) {
                        Navigator.of(context).pushReplacementNamed('/library');
                      } else {
                        Navigator.of(context).pop(true);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 10,
                      ),
                      child: Text(
                        'Skip',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTokens.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTokens.gold.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_rounded,
                      color: AppTokens.gold,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your subscription data never leaves your device. Detection runs entirely on-device.',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _scanning
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTokens.gold),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      children: [
                        if (_detected.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'On Your Phone',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.textFaint,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...List.generate(_detected.length, (i) {
                            final entry = _detected[i];
                            return _detectedRow(entry);
                          }),
                        ] else ...[
                          const SizedBox(height: 24),
                          Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.phone_android_rounded,
                                  color: AppTokens.textFaint.withValues(
                                    alpha: 0.4,
                                  ),
                                  size: 40,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Nothing detected — add services below',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTokens.textMuted,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        Text(
                          'Popular Web & Lifestyle Services',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textFaint,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final entry in _webEntries) _webChip(entry),
                          ],
                        ),
                        const SizedBox(height: 80),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppTokens.goldGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _saving ? null : _confirm,
                        child: Center(
                          child: _saving
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTokens.screenBg,
                                  ),
                                )
                              : Text(
                                  'Add ${_selected.length} service${_selected.length == 1 ? '' : 's'}',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTokens.screenBg,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // A3: 48px minimum height on detected rows
  Widget _detectedRow(CatalogEntry entry) {
    final catColor = AppTokens.categoryColor(entry.category);
    final alreadyAdded = _isAlreadyAdded(entry);
    final checked = _selected.contains(entry);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: alreadyAdded ? null : () => _toggle(entry),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
        constraints: const BoxConstraints(minHeight: 48),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTokens.hairline, width: 1),
          ),
        ),
        child: Row(
          children: [
            _buildAvatar(
              packageName: entry.packageName,
              letter: entry.name[0].toUpperCase(),
              catColor: catColor,
              size: 40,
              borderRadius: 12,
              fontSize: 17,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    entry.category,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            if (alreadyAdded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTokens.textMuted.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTokens.hairlineStrong),
                ),
                child: Text(
                  'Added',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            if (!alreadyAdded)
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: checked ? AppTokens.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: checked ? AppTokens.gold : AppTokens.hairlineStrong,
                    width: checked ? 0 : 1.5,
                  ),
                ),
                child: checked
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppTokens.screenBg,
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar({
    required String? packageName,
    required String letter,
    required Color catColor,
    required double size,
    required int borderRadius,
    required double fontSize,
  }) {
    final iconBytes = AppIconService().iconFor(packageName);
    if (iconBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius.toDouble()),
        child: Image.memory(
          iconBytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [catColor, catColor.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius.toDouble()),
      ),
      child: Center(
        child: Text(
          letter,
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // A3: 48px minimum height on web chips
  Widget _webChip(CatalogEntry entry) {
    final alreadyAdded = _isAlreadyAdded(entry);
    final selected = _selected.contains(entry);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: alreadyAdded ? null : () => _toggle(entry),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: selected
              ? AppTokens.gold.withValues(alpha: 0.12)
              : AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppTokens.gold.withValues(alpha: 0.3)
                : AppTokens.hairline,
          ),
        ),
        child: Text(
          entry.name,
          style: GoogleFonts.plusJakartaSans(
            color: selected ? AppTokens.gold : AppTokens.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ReviewRow {
  final CatalogEntry entry;
  final TextEditingController costCtrl;
  String cycle = 'monthly';
  DateTime renewal;

  _ReviewRow(this.entry)
    : costCtrl = TextEditingController(
        text: entry.pricingTiers.isNotEmpty
            ? entry.pricingTiers.first.monthlyPrice.toStringAsFixed(2)
            : '',
      ),
      renewal = defaultRenewalDate('monthly');
}

/// Confirms cost + renewal date for each scan-detected/quick-picked
/// entry before it's saved, so scanned apps don't silently end up
/// untracked-for-spend with no cost or renewal date attached.
class _ScanReviewSheet extends StatefulWidget {
  final List<CatalogEntry> entries;
  const _ScanReviewSheet({required this.entries});

  @override
  State<_ScanReviewSheet> createState() => _ScanReviewSheetState();
}

class _ScanReviewSheetState extends State<_ScanReviewSheet> {
  late final List<_ReviewRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.entries.map((e) => _ReviewRow(e)).toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.costCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(_ReviewRow row) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: row.renewal,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTokens.gold),
          dialogTheme: const DialogThemeData(backgroundColor: AppTokens.cardBg),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => row.renewal = picked);
  }

  void _setCycle(_ReviewRow row, String cycle) {
    HapticFeedback.selectionClick();
    setState(() {
      row.cycle = cycle;
      row.renewal = defaultRenewalDate(cycle);
    });
  }

  void _confirm() {
    HapticFeedback.mediumImpact();
    final result = _rows.map((r) {
      final cost = double.tryParse(r.costCtrl.text.trim());
      return r.entry.toAppEntry().copyWith(
        isActiveSubscription: cost != null,
        subscriptionCost: cost,
        billingCycle: cost != null ? r.cycle : null,
        nextRenewalDate: cost != null ? r.renewal : null,
      );
    }).toList();
    Navigator.pop(context, result);
  }

  Widget _cyclePill(_ReviewRow row, String cycle, String label) {
    final selected = row.cycle == cycle;
    return GestureDetector(
      onTap: () => _setCycle(row, cycle),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTokens.gold.withValues(alpha: 0.12) : AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(AppTokens.rPill),
          border: Border.all(
            color: selected ? AppTokens.gold.withValues(alpha: 0.3) : AppTokens.hairline,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: selected ? AppTokens.gold : AppTokens.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _row(_ReviewRow row) {
    final fmt = DateFormat('d MMM y');
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.entry.name,
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 90,
                child: TextField(
                  controller: row.costCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.spaceGrotesk(
                    color: AppTokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: GoogleFonts.spaceGrotesk(
                      color: AppTokens.textMuted,
                      fontSize: 14,
                    ),
                    hintText: '0.00',
                    hintStyle: GoogleFonts.spaceGrotesk(color: AppTokens.textFaint, fontSize: 14),
                    isDense: true,
                    filled: true,
                    fillColor: AppTokens.fieldBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rInput),
                      borderSide: const BorderSide(color: AppTokens.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rInput),
                      borderSide: const BorderSide(color: AppTokens.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rInput),
                      borderSide: const BorderSide(color: AppTokens.gold),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _cyclePill(row, 'monthly', 'Monthly'),
              const SizedBox(width: 6),
              _cyclePill(row, 'yearly', 'Yearly'),
              const Spacer(),
              GestureDetector(
                onTap: () => _pickDate(row),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTokens.fieldBg,
                    borderRadius: BorderRadius.circular(AppTokens.rPill),
                    border: Border.all(color: AppTokens.hairline),
                  ),
                  child: Text(
                    fmt.format(row.renewal),
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTokens.cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTokens.hairlineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm cost & renewal',
                          style: GoogleFonts.playfairDisplay(
                            color: AppTokens.textStrong,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Leave a cost blank to add it without tracking spend for now.',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
                children: [for (final r in _rows) _row(r)],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppTokens.goldGradient,
                      borderRadius: BorderRadius.circular(AppTokens.rInput),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTokens.rInput),
                        onTap: _confirm,
                        child: Center(
                          child: Text(
                            'Confirm ${_rows.length} subscription${_rows.length == 1 ? '' : 's'}',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.screenBg,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
