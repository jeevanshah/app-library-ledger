import 'dart:convert';
import 'dart:ui' show lerpDouble;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_model.dart';
import '../models/category_model.dart';
import '../models/offer.dart';
import '../models/spend_ledger_entry.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../services/analytics_service.dart';
import '../services/app_icon_service.dart';
import '../services/catalog_service.dart';
import '../services/settings_service.dart';
import '../services/subscription_scanner.dart';
import '../services/offers_service.dart';
import '../services/offers_matcher.dart';
import '../theme/app_tokens.dart';
import '../widgets/hero_empty_state.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/pulse.dart';
import 'add_app_screen.dart';
import 'calendar_screen.dart';
import 'discovery_screen.dart';
import 'spend_history_screen.dart';
import 'settings_screen.dart';
import 'offers_screen.dart';

final _fmt = NumberFormat.currency(
  locale: 'en_US',
  symbol: '\$',
  decimalDigits: 2,
);

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with TickerProviderStateMixin {
  late List<AppEntry> _apps = [];
  late List<Category> _cats = [];
  bool _loading = true;
  int _tab = 0;
  String _q = '';
  String? _cat;
  bool _grid = false;
  int _sortBy = 0;
  Set<String> _installedPkgs = {};
  Map<String, int> _dismissedInsights = {};
  Set<String> _dismissedPromoResolve = {};
  List<MatchedOffer> _matchedOffers = [];
  List<SavingsOffer> _offers = [];
  List<SpendLedgerEntry> _ledger = [];
  bool _offersEnabled = false;
  Set<String> _seenOfferIds = {};
  bool _refreshing = false;
  late final SettingsService _settingsService = SettingsService();

  /// Marks all currently matched offers as seen and persists the set,
  /// clearing the gold dot on the Offers nav icon. Called when the
  /// Offers tab is opened.
  Future<void> _markOffersSeen() async {
    final ids = _matchedOffers.map((m) => m.offer.id).toSet();
    if (ids.difference(_seenOfferIds).isEmpty) return;
    setState(() => _seenOfferIds = {..._seenOfferIds, ...ids});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('seen_offer_ids', _seenOfferIds.toList());
  }

  final _analytics = AnalyticsService();
  final _scrollCtrl = ScrollController();
  late final AnimationController _counterCtrl;
  late final Animation<double> _counterAnim;
  bool _insightsExpanded = false;

  @override
  void initState() {
    super.initState();
    _counterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _counterAnim = CurvedAnimation(
      parent: _counterCtrl,
      curve: Curves.easeOutCubic,
    );
    _settingsService.offersEnabled.addListener(_onOffersToggled);
    _refresh();
  }

  void _onOffersToggled() {
    setState(() => _offersEnabled = _settingsService.offersEnabled.value);
  }

  @override
  void dispose() {
    _settingsService.offersEnabled.removeListener(_onOffersToggled);
    _counterCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    setState(() => _loading = true);
    try {
      final apps = await StorageService().getApps();
      final cats = await StorageService().getCategories();
      if (!mounted) return;

      // Auto-graduate expired promos: once promotionEndsDate has passed
      // and a regularPrice is on file, the normal case is the promo
      // simply ended and regular pricing kicked in -- no manual step
      // needed. Entries with no regularPrice on file can't be safely
      // graduated (nothing to graduate TO) and still surface via the
      // expired-promo banner for a human to fill in the price.
      final now = DateTime.now();
      final graduated = <AppEntry>[];
      for (var i = 0; i < apps.length; i++) {
        final a = apps[i];
        if (a.isActiveSubscription &&
            a.isPromotionalPrice &&
            a.promotionEndsDate != null &&
            a.promotionEndsDate!.isBefore(now) &&
            a.regularPrice != null) {
          final updated = a.copyWith(
            subscriptionCost: a.regularPrice,
            isPromotionalPrice: false,
          );
          await StorageService().saveApp(updated);
          await NotificationService().cancelPromoReminders(a.id);
          await NotificationService().announcePromoGraduated(updated);
          apps[i] = updated;
          graduated.add(updated);
        }
      }
      if (!mounted) return;

      final pkgNames = apps
          .where((a) => a.packageName != null)
          .map((a) => a.packageName!)
          .toList();
      if (pkgNames.isNotEmpty) await AppIconService().loadIcons(pkgNames);

      // I4: Installed package scan
      final catalog = CatalogService();
      await catalog.loadCatalog();
      final scanPkgs = catalog.appScanEntries
          .map((e) => e.packageName!)
          .toList();
      if (scanPkgs.isNotEmpty) {
        try {
          final installed = await packageScannerChannel
              .invokeMethod<List<dynamic>>('checkPackagesSurgically', scanPkgs);
          _installedPkgs = (installed ?? []).map((e) => e.toString()).toSet();
        } catch (_) {
          _installedPkgs = {};
        }
      }

      // Dismissed insights
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('dismissed_insights');
        if (raw != null) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          _dismissedInsights = decoded.map((k, v) => MapEntry(k, v as int));
          _dismissedInsights.removeWhere(
            (k, v) =>
                (DateTime.now().millisecondsSinceEpoch - v) >
                (30 * 86400 * 1000),
          );
        }
        final prRaw = prefs.getString('promo_resolve_dismissed');
        if (prRaw != null) {
          final prDecoded = jsonDecode(prRaw) as Map<String, dynamic>;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          _dismissedPromoResolve = {};
          for (final e in prDecoded.entries) {
            final ts = e.value as int;
            if ((nowMs - ts) < (7 * 86400 * 1000))
              _dismissedPromoResolve.add(e.key);
          }
        }
      } catch (_) {}

      if (!mounted) return;

      // Fetch offers if enabled
      final prefs = await SharedPreferences.getInstance();
      _offersEnabled = prefs.getBool('offers_enabled') ?? false;
      _seenOfferIds = (prefs.getStringList('seen_offer_ids') ?? []).toSet();
      if (_offersEnabled) {
        final offers = await OffersService().fetch(enabled: true);
        final matcher = OffersMatcher();
        _matchedOffers = matcher.match(apps, offers);
        _offers = offers;
      } else {
        _matchedOffers = [];
        _offers = [];
      }

      final ledger = await StorageService().getSpendLedger();

      if (!mounted) return;
      setState(() {
        _apps = apps;
        _cats = cats;
        _ledger = ledger;
        _loading = false;
      });
      _counterCtrl.forward(from: 0);
      if (graduated.isNotEmpty && mounted) {
        final message = graduated.length == 1
            ? '${graduated.first.name} moved to regular price '
                  '${_fmt.format(graduated.first.subscriptionCost ?? 0)}'
                  '${graduated.first.billingCycle == 'yearly' ? '/yr' : '/mo'}'
            : '${graduated.length} subscriptions moved to regular pricing';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _goAdd() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddAppScreen(categories: _cats)),
    );
    if (ok == true) _refresh();
  }

  Future<void> _goScan() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const DiscoveryScreen(fromOnboarding: false),
      ),
    );
    if (ok == true) _refresh();
  }

  void _goSpendHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SpendHistoryScreen(apps: _apps, ledger: _ledger, cats: _cats),
      ),
    );
  }

  Widget _emptyLibraryState() {
    return HeroEmptyState(
      illustration: 'subscription_list_toggles',
      title: 'Nothing tracked yet',
      subtitle:
          'Add your first subscription to start tracking costs and renewals.',
      ctaLabel: '+ Add your first subscription',
      onCta: _goAdd,
      linkLabel: 'Scan my phone instead',
      onLink: _goScan,
    );
  }

  Future<void> _goEdit(AppEntry a) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddAppScreen(categories: _cats, appToEdit: a),
      ),
    );
    if (ok == true) _refresh();
  }

  Future<void> _deleteApp(AppEntry a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.cardBg,
        title: Text(
          'Delete?',
          style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary),
        ),
        content: Text(
          'Remove "${a.name}"?',
          style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await StorageService().deleteApp(a.id);
      await NotificationService().cancelReminders(a.id);
      final remaining = await StorageService().getApps();
      await NotificationService().rescheduleAll(remaining);
      _refresh();
    }
  }

  Future<void> _dismissInsight(String id) async {
    _dismissedInsights[id] = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'dismissed_insights',
      jsonEncode(_dismissedInsights.map((k, v) => MapEntry(k, v))),
    );
    setState(() {});
  }

  Future<void> _showExpiredPromoSheet() async {
    final expired = _analytics
        .getExpiredPromos(_apps)
        .where((a) => !_dismissedPromoResolve.contains(a.id))
        .toList();
    if (expired.isEmpty) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Expired Promos',
                style: GoogleFonts.spaceGrotesk(
                  color: AppTokens.textStrong,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ...expired.map(
                (a) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(AppTokens.padCard),
                  decoration: BoxDecoration(
                    color: AppTokens.fieldBg,
                    borderRadius: BorderRadius.circular(AppTokens.rInput),
                    border: Border.all(color: AppTokens.hairline),
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
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Was \$${a.subscriptionCost?.toStringAsFixed(2)}/mo on promo — new price unknown',
                              style: GoogleFonts.spaceGrotesk(
                                color: AppTokens.textMuted,
                                fontSize: 12.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _goEdit(a);
                        },
                        child: const Text(
                          'Set new price',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _pickNewPromoEnd(a);
                        },
                        child: const Text(
                          'Still on promo',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickNewPromoEnd(AppEntry a) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2099),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppTokens.brandEnd,
            onPrimary: Colors.white,
            surface: AppTokens.cardBg,
            onSurface: AppTokens.textPrimary,
          ),
          dialogTheme: DialogThemeData(backgroundColor: AppTokens.cardBg),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final updated = a.copyWith(
      isPromotionalPrice: true,
      promotionEndsDate: picked,
    );
    await StorageService().saveApp(updated);
    await NotificationService().schedulePromoReminder(updated);
    _refresh();
  }

  Future<void> _dismissPromoBanner(String appId) async {
    _dismissedPromoResolve.add(appId);
    final prefs = await SharedPreferences.getInstance();
    final map = {
      for (final id in _dismissedPromoResolve)
        id: DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString('promo_resolve_dismissed', jsonEncode(map));
    setState(() {});
  }

  List<AppEntry> get _filtered {
    var list = _apps.toList();
    if (_q.isNotEmpty)
      list = list
          .where((a) => a.name.toLowerCase().contains(_q.toLowerCase()))
          .toList();
    if (_cat != null) list = list.where((a) => a.category == _cat).toList();
    switch (_sortBy) {
      case 1:
        list.sort(
          (a, b) =>
              (b.subscriptionCost ?? 0).compareTo(a.subscriptionCost ?? 0),
        );
      case 2:
        list.sort(
          (a, b) => (a.nextRenewalDate ?? DateTime(2099)).compareTo(
            b.nextRenewalDate ?? DateTime(2099),
          ),
        );
      case 3:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      default:
        list.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  Map<String, int> get _counts {
    final m = <String, int>{};
    for (final a in _apps) {
      m[a.category] = (m[a.category] ?? 0) + 1;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthly = _analytics.getTotalMonthlyCost(_apps);
    final active = _analytics.getActiveSubscriptionCount(_apps);
    final promoSavings = _analytics.getActivePromoSavings(_apps);
    final renewSoonCount = _apps.where((a) {
      if (!a.isActiveSubscription || a.nextRenewalDate == null) return false;
      final diff = a.nextRenewalDate!.difference(now).inDays;
      return diff >= 0 && diff <= 7;
    }).length;
    final filtered = _filtered;
    final counts = _counts;
    final expiredPromos = _analytics
        .getExpiredPromos(_apps)
        .where((a) => !_dismissedPromoResolve.contains(a.id))
        .toList();

    return Scaffold(
      backgroundColor: AppTokens.screenBg,
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: AppTokens.brandStart),
            )
          : SafeArea(
              child: IndexedStack(
                index: _tab,
                children: [
                  // ── Library Tab ──
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTokens.padHeader,
                          10,
                          AppTokens.padHeader,
                          6,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YOUR LIBRARY',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTokens.textFaint,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  active > 0
                                      ? '$active subscriptions'
                                      : 'No subscriptions',
                                  style: GoogleFonts.playfairDisplay(
                                    color: AppTokens.textStrong,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTokens.cardBg,
                                borderRadius: BorderRadius.circular(
                                  AppTokens.rSmallPill,
                                ),
                                border: Border.all(
                                  color: AppTokens.brandStart.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: AppTokens.brandStart,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'DEVICE LOCAL',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppTokens.brandStart,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_apps.any((a) => a.isActiveSubscription))
                        AnimatedBuilder(
                          animation: _scrollCtrl,
                          builder: (_, __) {
                            final offset = _scrollCtrl.hasClients
                                ? _scrollCtrl.offset.clamp(0.0, double.infinity)
                                : 0.0;
                            final t = (offset / 96.0).clamp(0.0, 1.0);
                            final height = lerpDouble(174.0, 52.0, t)!;
                            final expandedOpacity = (1.0 - t * 2.5).clamp(0.0, 1.0);
                            final collapsedOpacity = ((t - 0.4) * 2.5).clamp(0.0, 1.0);

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 100),
                                height: height,
                                clipBehavior: Clip.hardEdge,
                                decoration: BoxDecoration(
                                  color: AppTokens.cardBg,
                                  borderRadius: BorderRadius.circular(
                                    t < 0.5 ? 20 : 14,
                                  ),
                                  border: Border.all(
                                    color: AppTokens.hairline,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: AppTokens.isDark ? 0.28 : 0.05,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    // ── Expanded Full Hero Card ──
                                    if (expandedOpacity > 0)
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        right: 0,
                                        height: 174,
                                        child: Opacity(
                                          opacity: expandedOpacity,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                // Top Row: Wallet Icon + Monthly Spend Hero + View Insights
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 46,
                                                      height: 46,
                                                      decoration: BoxDecoration(
                                                        color: AppTokens.brandStart
                                                            .withValues(alpha: 0.10),
                                                        borderRadius:
                                                            BorderRadius.circular(14),
                                                      ),
                                                      alignment: Alignment.center,
                                                      child: categoryIcon(
                                                        'Finance',
                                                        size: 26,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment.start,
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            'Monthly spend',
                                                            style: GoogleFonts
                                                                .plusJakartaSans(
                                                              color:
                                                                  AppTokens.textMuted,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight.w500,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 2),
                                                          Row(
                                                            mainAxisSize:
                                                                MainAxisSize.min,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .center,
                                                            children: [
                                                              ShaderMask(
                                                                shaderCallback:
                                                                    (bounds) =>
                                                                        LinearGradient(
                                                                  colors: [
                                                                    AppTokens
                                                                        .brandStart,
                                                                    AppTokens
                                                                        .brandEnd,
                                                                  ],
                                                                ).createShader(
                                                                  bounds,
                                                                ),
                                                                child: AnimatedBuilder(
                                                                  animation:
                                                                      _counterAnim,
                                                                  builder: (_, __) =>
                                                                      Text(
                                                                    _fmt.format(
                                                                      monthly *
                                                                          _counterAnim
                                                                              .value,
                                                                    ),
                                                                    style: GoogleFonts
                                                                        .spaceGrotesk(
                                                                      color: AppTokens
                                                                          .brandStart,
                                                                      fontSize: 24,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      letterSpacing:
                                                                          -0.5,
                                                                      fontFeatures: const [
                                                                        FontFeature
                                                                            .tabularFigures(),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(width: 6),
                                                              heroIllustration(
                                                                'piggybank_savings',
                                                                width: 32,
                                                                height: 32,
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    GestureDetector(
                                                      onTap: () {
                                                        HapticFeedback.selectionClick();
                                                        setState(() => _tab = 1);
                                                      },
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: AppTokens.brandStart
                                                              .withValues(alpha: 0.10),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                            AppTokens.rPill,
                                                          ),
                                                          border: Border.all(
                                                            color: AppTokens.brandStart
                                                                .withValues(
                                                              alpha: 0.22,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                            MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              'View insights',
                                                              style: GoogleFonts
                                                                  .plusJakartaSans(
                                                                color: AppTokens
                                                                    .brandStart,
                                                                fontSize: 11.5,
                                                                fontWeight:
                                                                    FontWeight.w700,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 3),
                                                          Icon(
                                                            Icons
                                                                .chevron_right_rounded,
                                                            size: 14,
                                                            color: AppTokens
                                                                .brandStart,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // Bottom Row: 3 Stat Mini-Cards
                                              Row(
                                                children: [
                                                  _miniStatCard(
                                                    icon: flatIcon(
                                                      'grid_orange',
                                                      color: AppTokens.brandStart,
                                                      size: 15,
                                                    ),
                                                    iconBg: AppTokens.brandStart
                                                        .withValues(alpha: 0.10),
                                                    value: '$active',
                                                    label: 'subscriptions',
                                                    onTap: () =>
                                                        setState(() => _tab = 0),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  _miniStatCard(
                                                    icon: flatIcon(
                                                      'calendar_orange',
                                                      color: AppTokens.brandStart,
                                                      size: 15,
                                                    ),
                                                    iconBg: AppTokens.brandStart
                                                        .withValues(alpha: 0.10),
                                                    value: '$renewSoonCount',
                                                    label: 'renew soon',
                                                    onTap: () => Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            CalendarScreen(
                                                          apps: _apps,
                                                          cats: _cats,
                                                          ledger: _ledger,
                                                        ),
                                                      ),
                                                    ).then((_) => _refresh()),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  _miniStatCard(
                                                    icon: categoryIcon(
                                                      'Finance',
                                                      size: 16,
                                                    ),
                                                    iconBg: AppTokens.brandStart
                                                        .withValues(alpha: 0.10),
                                                    value: promoSavings > 0
                                                        ? '\$${promoSavings.toStringAsFixed(0)}'
                                                        : '\$${_analytics.getYearlyProjection(_apps).toStringAsFixed(0)}',
                                                    label: promoSavings > 0
                                                        ? 'potential savings'
                                                        : 'yearly spend',
                                                    onTap: () =>
                                                        setState(() => _tab = 1),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    // ── Collapsed Compact Sticky Bar ──
                                    if (collapsedOpacity > 0)
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        right: 0,
                                        height: 52,
                                        child: Opacity(
                                          opacity: collapsedOpacity,
                                          child: GestureDetector(
                                            onTap: () {
                                              HapticFeedback.selectionClick();
                                              setState(() => _tab = 1);
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.spaceBetween,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width: 32,
                                                        height: 32,
                                                        decoration: BoxDecoration(
                                                          color: AppTokens.brandStart
                                                              .withValues(alpha: 0.10),
                                                          borderRadius:
                                                              BorderRadius.circular(8),
                                                        ),
                                                        alignment: Alignment.center,
                                                        child: categoryIcon(
                                                          'Finance',
                                                          size: 18,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'Monthly spend',
                                                        style: GoogleFonts
                                                            .plusJakartaSans(
                                                          color: AppTokens.textMuted,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      ShaderMask(
                                                        shaderCallback: (bounds) =>
                                                            LinearGradient(
                                                          colors: [
                                                            AppTokens.brandStart,
                                                            AppTokens.brandEnd,
                                                          ],
                                                        ).createShader(bounds),
                                                        child: AnimatedBuilder(
                                                          animation: _counterAnim,
                                                          builder: (_, __) => Text(
                                                            _fmt.format(
                                                              monthly *
                                                                  _counterAnim.value,
                                                            ),
                                                            style: GoogleFonts
                                                                .spaceGrotesk(
                                                              color:
                                                                  AppTokens.brandStart,
                                                              fontSize: 17,
                                                              fontWeight:
                                                                  FontWeight.w700,
                                                              fontFeatures: const [
                                                                FontFeature
                                                                    .tabularFigures(),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Icon(
                                                        Icons.chevron_right_rounded,
                                                        size: 16,
                                                        color: AppTokens.brandStart,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      // D4: Expired promo banner
                      if (expiredPromos.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.padHeader,
                          ),
                          child: Dismissible(
                            key: ValueKey(expiredPromos.first.id),
                            onDismissed: (_) =>
                                _dismissPromoBanner(expiredPromos.first.id),
                            child: GestureDetector(
                              onTap: _showExpiredPromoSheet,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTokens.warning.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppTokens.rInput,
                                  ),
                                  border: Border.all(
                                    color: AppTokens.warning.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppTokens.warning,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '${expiredPromos.length} promo(s) ended — set the price after promo',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppTokens.warning,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppTokens.warning,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.padHeader,
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _searchField()),
                            const SizedBox(width: 10),
                            _iconBtn(
                              Icons.sort_rounded,
                              onTap: () =>
                                  setState(() => _sortBy = (_sortBy + 1) % 4),
                            ),
                            const SizedBox(width: 8),
                            _iconBtn(
                              _grid
                                  ? Icons.view_agenda_rounded
                                  : Icons.grid_view_rounded,
                              onTap: () => setState(() => _grid = !_grid),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 42,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.padHeader,
                          ),
                          children: [
                            _chip('All', _apps.length, null, _cat == null),
                            for (final c in _cats)
                              if ((counts[c.name] ?? 0) > 0)
                                _chip(
                                  c.name,
                                  counts[c.name] ?? 0,
                                  c.color,
                                  _cat == c.name,
                                ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? (_apps.isEmpty
                                  ? _emptyLibraryState()
                                  : Center(
                                      child: Text(
                                        'No matches',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppTokens.textMuted,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ))
                            : _grid
                            ? GridView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.fromLTRB(
                                  22,
                                  0,
                                  22,
                                  150,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                      childAspectRatio: 0.85,
                                    ),
                                itemCount: filtered.length,
                                itemBuilder: (_, i) => _gridCard(filtered[i]),
                              )
                            : ListView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.fromLTRB(
                                  22,
                                  0,
                                  22,
                                  150,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (_, i) => _listCard(filtered[i]),
                              ),
                      ),
                    ],
                  ),
                  // ── Dashboard Tab ──
                  _DashboardView(
                    apps: _apps,
                    analytics: _analytics,
                    installed: _installedPkgs,
                    dismissed: _dismissedInsights,
                    onDismissInsight: _dismissInsight,
                    onEdit: _goEdit,
                    cats: _cats,
                    onRefresh: _refresh,
                    insightsExpanded: _insightsExpanded,
                    onToggleInsights: () =>
                        setState(() => _insightsExpanded = !_insightsExpanded),
                    matchedOffers: _matchedOffers,
                    offersEnabled: _offersEnabled,
                    onOpenOffers: () => setState(() => _tab = 3),
                    offers: _offers,
                    ledger: _ledger,
                    onOpenSpendHistory: _goSpendHistory,
                  ),
                  // ── Settings Tab ──
                  const SettingsScreen(),
                  // ── Offers Tab ──
                  OffersScreen(apps: _apps, onSaveApp: _refresh),
                ],
              ),
            ),
      bottomNavigationBar: GlassBottomNav(
        selectedIndex: _tab,
        showOfferDot:
            _offersEnabled &&
            _matchedOffers.any((m) => !_seenOfferIds.contains(m.offer.id)),
        onTap: (i) {
          setState(() => _tab = i);
          if (i == 3) _markOffersSeen();
        },
      ),
      floatingActionButton: PressableScale(
        child: FloatingActionButton(
          onPressed: _goAdd,
          backgroundColor: AppTokens.brandStart,
          foregroundColor: AppTokens.screenBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.rFab),
          ),
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
    );
  }

  Widget _miniStatCard({
    required Widget icon,
    required Color iconBg,
    required String value,
    required String label,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (onTap != null) {
            HapticFeedback.selectionClick();
            onTap();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: AppTokens.fieldBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTokens.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: icon,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTokens.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField() => Container(
    height: 44,
    decoration: BoxDecoration(
      color: AppTokens.fieldBg,
      borderRadius: BorderRadius.circular(AppTokens.rInput),
      border: Border.all(color: AppTokens.hairline),
    ),
    child: TextField(
      onChanged: (v) => setState(() => _q = v),
      decoration: InputDecoration(
        hintText: 'Search...',
        hintStyle: TextStyle(color: AppTokens.textPlaceholder, fontSize: 13),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: AppTokens.textFaint,
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      style: GoogleFonts.plusJakartaSans(
        color: AppTokens.textPrimary,
        fontSize: 13,
      ),
    ),
  );
  Widget _iconBtn(IconData icon, {VoidCallback? onTap}) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTokens.fieldBg,
        borderRadius: BorderRadius.circular(AppTokens.rInput),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Icon(icon, color: AppTokens.textMuted, size: 18),
    ),
  );
  Widget _chip(String name, int count, Color? color, bool selected) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _cat = (selected || name == 'All') ? null : name);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppTokens.brandStart.withValues(alpha: 0.12)
              : AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(AppTokens.rPill),
          border: Border.all(
            color: selected
                ? AppTokens.brandStart.withValues(alpha: 0.3)
                : AppTokens.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: AppTokens.categories.containsKey(name)
                    ? categoryIcon(name, size: 16)
                    : Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
              ),
            Text(
              '$name $count',
              style: GoogleFonts.plusJakartaSans(
                color: selected ? AppTokens.brandStart : AppTokens.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _statusRow(bool usePromo, int days, ({Color fg, Color bg})? urg) {
    return Row(
      children: [
        Icon(
          usePromo
              ? Icons.trending_down_rounded
              : (days <= 7
                    ? Icons.notifications_active_rounded
                    : Icons.schedule_rounded),
          size: 11,
          color: urg?.fg,
        ),
        const SizedBox(width: 4),
        Text(
          usePromo
              ? (days >= 0
                    ? 'Promo ends in $days day${days == 1 ? '' : 's'}'
                    : 'Promo ended ${-days} day${-days == 1 ? '' : 's'} ago')
              : (days >= 0
                    ? 'Renews in $days day${days == 1 ? '' : 's'}'
                    : 'Renewal overdue by ${-days} day${-days == 1 ? '' : 's'}'),
          style: GoogleFonts.plusJakartaSans(
            color: urg?.fg,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _listCard(AppEntry app) {
    final baseClr = AppTokens.categoryColor(app.category);
    final renewalDays = app.nextRenewalDate != null
        ? app.nextRenewalDate!.difference(DateTime.now()).inDays
        : null;
    final promoDays = (app.isPromotionalPrice && app.promotionEndsDate != null)
        ? app.promotionEndsDate!.difference(DateTime.now()).inDays
        : null;
    // The promo cliff is the thing this app exists to catch — if it's
    // sooner (or equal) than the next renewal, lead with that instead.
    final usePromo =
        promoDays != null && (renewalDays == null || promoDays <= renewalDays);
    final days = usePromo ? promoDays : renewalDays;
    final urg = days != null ? AppTokens.urgency(days) : null;
    return Dismissible(
      key: ValueKey(app.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        _deleteApp(app);
        return false;
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppTokens.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppTokens.rInput),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 28),
        child: Icon(
          Icons.delete_outline_rounded,
          color: AppTokens.danger,
          size: 20,
        ),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _goEdit(app);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTokens.hairline, width: 1),
            ),
          ),
          child: Row(
            children: [
              _listAvatar(app: app, baseClr: baseClr),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: baseClr,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          app.category,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (days != null) ...[
                      const SizedBox(height: 5),
                      if (usePromo && days <= 7)
                        Pulse(child: _statusRow(usePromo, days, urg))
                      else
                        _statusRow(usePromo, days, urg),
                    ],
                    if (app.subscriptionCost == null ||
                        app.nextRenewalDate == null) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddAppScreen(
                                categories: _cats,
                                appToEdit: app,
                                focusBilling: true,
                              ),
                            ),
                          ).then((ok) {
                            if (ok == true) _refresh();
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 11,
                                color: AppTokens.brandStart,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Tap to set billing date',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppTokens.brandStart,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (app.isActiveSubscription)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmt.format(app.subscriptionCost ?? 0),
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTokens.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '/${app.billingCycle == 'yearly' ? 'yr' : 'mo'}',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textFaint,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: AppTokens.textFaint.withValues(alpha: 0.4),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listAvatar({required AppEntry app, required Color baseClr}) {
    final iconBytes = AppIconService().iconFor(app.packageName);
    if (iconBytes != null)
      return Hero(
        tag: 'logo-${app.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.rAvatar),
          child: Image.memory(
            iconBytes,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      );
    return Hero(
      tag: 'logo-${app.id}',
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: baseClr.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTokens.rAvatar),
        ),
        child: Center(
          child: AppTokens.categories.containsKey(app.category)
              ? categoryIcon(app.category, size: 26)
              : Text(
                  app.name[0].toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    color: baseClr,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _gridCard(AppEntry app) {
    final baseClr = AppTokens.categoryColor(app.category);
    return GestureDetector(
      onTap: () => _goEdit(app),
      child: Container(
        decoration: BoxDecoration(
          color: AppTokens.cardBg,
          borderRadius: BorderRadius.circular(AppTokens.rInput),
          border: Border.all(color: AppTokens.hairline),
        ),
        padding: const EdgeInsets.all(AppTokens.padCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: baseClr.withValues(alpha: 0.2),
                  radius: 14,
                  child: Text(
                    app.name[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                if (app.isActiveSubscription)
                  Text(
                    '\$${app.subscriptionCost?.toStringAsFixed(0) ?? '0'}',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              app.name,
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              app.category,
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════

class _MiniMonthPreview extends StatelessWidget {
  final List<AppEntry> apps;
  final AnalyticsService analytics;
  final List<Category> cats;
  final List<SpendLedgerEntry> ledger;
  const _MiniMonthPreview({
    required this.apps,
    required this.analytics,
    required this.cats,
    required this.ledger,
  });

  List<DateTime?> _buildGridDays(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Mon=1..Sun=7 -> 0..6
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(leadingBlanks, null),
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  Color _dotColor(CalendarEventKind kind) => switch (kind) {
    CalendarEventKind.renewal => AppTokens.brandStart,
    CalendarEventKind.promoEnd => AppTokens.warning,
    CalendarEventKind.projectedPastBilling => AppTokens.info,
  };

  Widget _dot(CalendarEventKind kind) {
    final color = _dotColor(kind);
    final hollow = kind == CalendarEventKind.projectedPastBilling;
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow ? Colors.transparent : color,
        border: hollow ? Border.all(color: color, width: 1) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final events = analytics.getCalendarEvents(
      apps,
      rangeStart: monthStart,
      rangeEnd: monthEnd,
      ledger: ledger,
    );
    final cells = _buildGridDays(month);
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final duesThisMonth = events.all.length;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CalendarScreen(apps: apps, cats: cats, ledger: ledger),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTokens.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTokens.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: AppTokens.isDark ? 0.2 : 0.03,
              ),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTokens.brandStart.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: flatIcon(
                    'calendar_orange',
                    color: AppTokens.brandStart,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Renewal Calendar',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      DateFormat('MMMM yyyy').format(month),
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: duesThisMonth > 0
                        ? AppTokens.brandStart.withValues(alpha: 0.10)
                        : AppTokens.fieldBg,
                    borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
                    border: Border.all(
                      color: duesThisMonth > 0
                          ? AppTokens.brandStart.withValues(alpha: 0.2)
                          : AppTokens.hairline,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        duesThisMonth > 0
                            ? '$duesThisMonth due'
                            : 'None due',
                        style: GoogleFonts.plusJakartaSans(
                          color: duesThisMonth > 0
                              ? AppTokens.brandStart
                              : AppTokens.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 13,
                        color: duesThisMonth > 0
                            ? AppTokens.brandStart
                            : AppTokens.textMuted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: labels
                  .map(
                    (l) => Expanded(
                      child: Center(
                        child: Text(
                          l,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textFaint,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 4),
            for (var w = 0; w < cells.length ~/ 7; w++)
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: _buildCell(cells[w * 7 + i], events.byDay, now),
                    ),
                ],
              ),
            if (events.all.isEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: AppTokens.brandStart,
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'No renewals due this month',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCell(
    DateTime? day,
    Map<DateTime, List<CalendarEvent>> byDay,
    DateTime today,
  ) {
    if (day == null) return const SizedBox(height: 24);
    final isToday =
        day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    final kinds = {
      for (final e in byDay[day] ?? const <CalendarEvent>[]) e.kind,
    }.toList();
    return SizedBox(
      height: 24,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 17,
            height: 17,
            alignment: Alignment.center,
            decoration: isToday
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTokens.brandStart.withValues(alpha: 0.12),
                    border: Border.all(color: AppTokens.brandStart, width: 1),
                  )
                : null,
            child: Text(
              '${day.day}',
              style: GoogleFonts.spaceGrotesk(
                color: isToday ? AppTokens.brandStart : AppTokens.textPrimary,
                fontSize: 10,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (kinds.isNotEmpty) ...[
            const SizedBox(height: 1),
            SizedBox(
              height: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < kinds.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    _dot(kinds[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  final List<AppEntry> apps;
  final AnalyticsService analytics;
  final Set<String> installed;
  final Map<String, int> dismissed;
  final void Function(String) onDismissInsight;
  final void Function(AppEntry) onEdit;
  final List<Category> cats;
  final VoidCallback onRefresh;
  final bool insightsExpanded;
  final VoidCallback onToggleInsights;
  final List<MatchedOffer> matchedOffers;
  final bool offersEnabled;
  final VoidCallback onOpenOffers;
  final List<SavingsOffer> offers;
  final List<SpendLedgerEntry> ledger;
  final VoidCallback onOpenSpendHistory;

  const _DashboardView({
    required this.apps,
    required this.analytics,
    required this.installed,
    required this.dismissed,
    required this.onDismissInsight,
    required this.onEdit,
    required this.cats,
    required this.onRefresh,
    required this.insightsExpanded,
    required this.onToggleInsights,
    required this.matchedOffers,
    required this.offersEnabled,
    required this.onOpenOffers,
    required this.offers,
    required this.ledger,
    required this.onOpenSpendHistory,
  });

  @override
  Widget build(BuildContext context) {
    final monthly = analytics.getTotalMonthlyCost(apps);
    final active = analytics.getActiveSubscriptionCount(apps);
    final avg = active > 0 ? monthly / active : 0.0;
    final yearly = analytics.getYearlyProjection(apps);

    // Spending breakdown pie chart data: active apps with a real
    // monthly cost, biggest first, top 5 named + the rest folded
    // into "Other".
    final spendEntries =
        apps
            .where((a) => a.isActiveSubscription)
            .map((a) => (app: a, cost: analytics.getMonthlyCost(a)))
            .where((e) => e.cost > 0)
            .toList()
          ..sort((a, b) => b.cost.compareTo(a.cost));
    const kVisibleSpendSlices = 5;
    final topSpend = spendEntries.take(kVisibleSpendSlices).toList();
    final otherSpend = spendEntries.skip(kVisibleSpendSlices).toList();
    final otherSpendTotal = otherSpend.fold<double>(
      0,
      (sum, e) => sum + e.cost,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 150),
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -30,
              right: -24,
              child: heroIllustration(
                'piggybank_savings',
                width: 110,
                height: 110,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DASHBOARD',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textFaint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'Overview',
                      style: GoogleFonts.playfairDisplay(
                        color: AppTokens.textStrong,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTokens.brandStart.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(
                          AppTokens.rSmallPill,
                        ),
                        border: Border.all(
                          color: AppTokens.brandStart.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          flatIcon(
                            'shield_lock_dark',
                            color: AppTokens.brandStart,
                            size: 11,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'ON-DEVICE',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.brandStart,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Multi-Metric Overview Hero
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTokens.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTokens.hairline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: AppTokens.isDark ? 0.25 : 0.04,
                ),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Top: Monthly Total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MONTHLY COMMITMENT',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textFaint,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            AppTokens.brandStart,
                            AppTokens.brandEnd,
                          ],
                        ).createShader(bounds),
                        child: Text(
                          _fmt.format(monthly),
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTokens.brandStart,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.fieldBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTokens.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Yearly proj.',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _fmt.format(yearly),
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 3 Quick Metric Pills
              Row(
                children: [
                  _dashboardMetricPill(
                    label: 'Active Apps',
                    value: '$active',
                    icon: flatIcon(
                      'grid_orange',
                      color: AppTokens.brandStart,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _dashboardMetricPill(
                    label: 'Avg / Sub',
                    value: _fmt.format(avg),
                    icon: categoryIcon('Finance', size: 14),
                  ),
                  const SizedBox(width: 8),
                  _dashboardMetricPill(
                    label: 'Annual Cost',
                    value: '\$${(yearly).toStringAsFixed(0)}',
                    icon: flatIcon(
                      'chart_trending_dark',
                      color: AppTokens.brandStart,
                      size: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Calendar preview card
        _MiniMonthPreview(
          apps: apps,
          analytics: analytics,
          cats: cats,
          ledger: ledger,
        ),
        const SizedBox(height: 14),

        // Spending History dashboard entry
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onOpenSpendHistory();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTokens.cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTokens.hairline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: AppTokens.isDark ? 0.2 : 0.03,
                  ),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTokens.brandStart.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: flatIcon(
                    'chart_trending_dark',
                    color: AppTokens.brandStart,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spending History & Ledger',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        ledger.isNotEmpty
                            ? '${ledger.length} recorded transactions · View trends'
                            : 'Track historical payments & price changes',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTokens.fieldBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTokens.hairline),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: AppTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Spending breakdown donut & expense progress cards
        if (spendEntries.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTokens.cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTokens.hairline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: AppTokens.isDark ? 0.25 : 0.04,
                  ),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SPENDING BREAKDOWN',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textFaint,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                    Text(
                      '${spendEntries.length} Active',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.brandStart,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Donut Chart
                SizedBox(
                  height: 190,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 3,
                          centerSpaceRadius: 52,
                          sections: [
                            for (final e in topSpend)
                              PieChartSectionData(
                                value: e.cost,
                                color: AppTokens.categoryColor(e.app.category),
                                radius: 36,
                                showTitle: false,
                              ),
                            if (otherSpendTotal > 0)
                              PieChartSectionData(
                                value: otherSpendTotal,
                                color: AppTokens.textFaint.withValues(
                                  alpha: 0.5,
                                ),
                                radius: 36,
                                showTitle: false,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'TOTAL / MO',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.textFaint,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _fmt.format(monthly),
                            style: GoogleFonts.spaceGrotesk(
                              color: AppTokens.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Top Expense Rows with Progress Bars
                for (final e in topSpend) ...[
                  _spendExpenseCard(
                    app: e.app,
                    cost: e.cost,
                    monthlyTotal: monthly,
                    onTap: () => onEdit(e.app),
                  ),
                  const SizedBox(height: 8),
                ],
                if (otherSpend.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _showOtherSpendSheet(context, otherSpend),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTokens.fieldBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTokens.hairline),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppTokens.textFaint,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Other subscriptions (${otherSpend.length})',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTokens.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            _fmt.format(otherSpendTotal),
                            style: GoogleFonts.spaceGrotesk(
                              color: AppTokens.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
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
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Savings Offers dashboard entry
        if (offersEnabled && matchedOffers.isNotEmpty)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onOpenOffers();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTokens.brandEnd.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppTokens.brandEnd.withValues(alpha: 0.25),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTokens.brandEnd.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTokens.brandEnd.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: flatIcon(
                      'tag_orange',
                      color: AppTokens.brandEnd,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cheaper Plans Available',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${matchedOffers.length} plan(s) found · Save up to ${_fmt.format(matchedOffers.first.savingsOverPromo)}',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.brandEnd,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTokens.brandEnd,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        if (offersEnabled && matchedOffers.isNotEmpty)
          const SizedBox(height: 14),
      ],
    );
  }

  Widget _dashboardMetricPill({
    required String label,
    required String value,
    required Widget icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTokens.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                icon,
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spendExpenseCard({
    required AppEntry app,
    required double cost,
    required double monthlyTotal,
    required VoidCallback onTap,
  }) {
    final pct = monthlyTotal > 0 ? (cost / monthlyTotal) : 0.0;
    final color = AppTokens.categoryColor(app.category);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTokens.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: categoryIcon(app.category, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.name,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        app.category,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmt.format(cost),
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTokens.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '${(pct * 100).toStringAsFixed(0)}% of total',
                      style: GoogleFonts.plusJakartaSans(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: AppTokens.hairline,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet listing the apps folded into the "Other" pie slice,
  /// so collapsing them into one slice doesn't lose information.
  void _showOtherSpendSheet(
    BuildContext context,
    List<({AppEntry app, double cost})> otherSpend,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Other subscriptions',
                style: GoogleFonts.spaceGrotesk(
                  color: AppTokens.textStrong,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              for (final e in otherSpend) ...[
                _spendExpenseCard(
                  app: e.app,
                  cost: e.cost,
                  monthlyTotal: analytics.getTotalMonthlyCost(apps),
                  onTap: () {
                    Navigator.pop(ctx);
                    onEdit(e.app);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
