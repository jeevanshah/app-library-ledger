import 'dart:convert';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_model.dart';
import '../models/category_model.dart';
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
import 'add_app_screen.dart';
import 'settings_screen.dart';
import 'offers_screen.dart';

final _fmt = NumberFormat.currency(
  locale: 'en_US',
  symbol: '\$',
  decimalDigits: 2,
);
final _dateFmt = DateFormat('MMM d');

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
  bool _cliffExpanded = false;
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

      final pkgNames = apps
          .where((a) => a.packageName != null)
          .map((a) => a.packageName!)
          .toList();
      if (pkgNames.isNotEmpty) await AppIconService().loadIcons(pkgNames);

      // I4: Installed package scan
      final catalog = CatalogService();
      await catalog.loadCatalog();
      final scanPkgs = catalog.appScanEntries.map((e) => e.packageName!).toList();
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
                (DateTime.now().millisecondsSinceEpoch - v) > (30 * 86400 * 1000),
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
        final matcher = OffersMatcher(_analytics);
        _matchedOffers = matcher.match(apps, offers);
      } else {
        _matchedOffers = [];
      }

      if (!mounted) return;
      setState(() {
        _apps = apps;
        _cats = cats;
        _loading = false;
      });
      _counterCtrl.forward(from: 0);
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
      await NotificationService().cancelPromoReminders(a.id);
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTokens.fieldBg,
                    borderRadius: BorderRadius.circular(12),
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
                              'Was \$${a.subscriptionCost?.toStringAsFixed(2)} → now \$${a.regularPrice?.toStringAsFixed(2)}',
                              style: GoogleFonts.spaceGrotesk(
                                color: AppTokens.textMuted,
                                fontSize: 12,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final updated = AppEntry(
                            id: a.id,
                            name: a.name,
                            appStoreLink: a.appStoreLink,
                            category: a.category,
                            packageName: a.packageName,
                            subscriptionCost: a.regularPrice,
                            billingCycle: a.billingCycle,
                            nextRenewalDate: a.nextRenewalDate,
                            isActiveSubscription: a.isActiveSubscription,
                            isPromotionalPrice: false,
                            serviceType: a.serviceType,
                          );
                          await StorageService().saveApp(updated);
                          await NotificationService().cancelPromoReminders(
                            a.id,
                          );
                          Navigator.pop(ctx);
                          _refresh();
                        },
                        child: Text(
                          'Now paying \$${a.regularPrice?.toStringAsFixed(2)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
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
                          style: TextStyle(fontSize: 12),
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
          colorScheme: const ColorScheme.dark(
            primary: AppTokens.brandEnd,
            onPrimary: Colors.white,
            surface: AppTokens.cardBg,
            onSurface: AppTokens.textPrimary,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: AppTokens.cardBg),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final updated = AppEntry(
      id: a.id,
      name: a.name,
      appStoreLink: a.appStoreLink,
      category: a.category,
      packageName: a.packageName,
      subscriptionCost: a.subscriptionCost,
      billingCycle: a.billingCycle,
      nextRenewalDate: a.nextRenewalDate,
      isActiveSubscription: a.isActiveSubscription,
      isPromotionalPrice: true,
      serviceType: a.serviceType,
      regularPrice: a.regularPrice,
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
    final monthly = _analytics.getTotalMonthlyCost(_apps);
    final active = _analytics.getActiveSubscriptionCount(_apps);
    final filtered = _filtered;
    final counts = _counts;
    final expiredPromos = _analytics
        .getExpiredPromos(_apps)
        .where((a) => !_dismissedPromoResolve.contains(a.id))
        .toList();

    return Scaffold(
      backgroundColor: AppTokens.screenBg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTokens.gold),
            )
          : SafeArea(
              child: IndexedStack(
                index: _tab,
                children: [
                  // ── Library Tab ──
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
                        child: Row(
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
                                color: AppTokens.gold.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 4,
                                    height: 4,
                                    decoration: const BoxDecoration(
                                      color: AppTokens.gold,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'DEVICE LOCAL',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppTokens.gold,
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
                            final height = lerpDouble(156.0, 44.0, t)!;
                            final vertPad = lerpDouble(28.0, 10.0, t)!;
                            final horizPad = lerpDouble(22.0, 22.0, t)!;
                            final labelFont = lerpDouble(12.0, 11.0, t)!;
                            final amountFont = lerpDouble(52.0, 18.0, t)!;
                            final pillOpacity = (1.0 - t * 2.0).clamp(0.0, 1.0);
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 14,
                              ),
                              child: GestureDetector(
                                onTap: () => setState(() => _tab = 1),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 100),
                                  decoration: BoxDecoration(
                                    color: AppTokens.cardBg,
                                    borderRadius: BorderRadius.circular(
                                      t < 0.5 ? 20.0 : 12.0,
                                    ),
                                    border: Border.all(
                                      color: AppTokens.hairline,
                                    ),
                                  ),
                                  height: height,
                                  padding: EdgeInsets.symmetric(
                                    vertical: vertPad,
                                    horizontal: horizPad,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (t < 0.5)
                                        Text(
                                          'Monthly spend',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: AppTokens.textMuted,
                                            fontSize: labelFont,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 1,
                                          ),
                                        )
                                      else
                                        Text(
                                          'Monthly spend',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: AppTokens.textMuted,
                                            fontSize: labelFont,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      AnimatedBuilder(
                                        animation: _counterAnim,
                                        builder: (_, __) => ShaderMask(
                                          shaderCallback: (bounds) =>
                                              LinearGradient(
                                                colors: [
                                                  AppTokens.gold,
                                                  AppTokens.goldLight,
                                                ],
                                              ).createShader(bounds),
                                          child: Text(
                                            _fmt.format(
                                              monthly * _counterAnim.value,
                                            ),
                                            style: GoogleFonts.playfairDisplay(
                                              color: AppTokens.gold,
                                              fontSize: amountFont,
                                              fontWeight: FontWeight.w700,
                                              height: t < 0.5 ? 1.0 : 1.2,
                                              letterSpacing: t < 0.5
                                                  ? -1.5
                                                  : -0.5,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      // Pills fade out (only when partially or fully expanded)
                      if (_apps.any((a) => a.isActiveSubscription))
                        AnimatedBuilder(
                          animation: _scrollCtrl,
                          builder: (_, __) {
                            final offset = _scrollCtrl.hasClients
                                ? _scrollCtrl.offset.clamp(0.0, double.infinity)
                                : 0.0;
                            final t = (offset / 96.0).clamp(0.0, 1.0);
                            final pillOpacity = (1.0 - t * 2.0).clamp(0.0, 1.0);
                            return AnimatedOpacity(
                              duration: const Duration(milliseconds: 100),
                              opacity: pillOpacity,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom: pillOpacity > 0 ? 4 : 0,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _pill('$active active', AppTokens.gold),
                                    const SizedBox(width: 12),
                                    if (active > 0)
                                      _pill(
                                        '\$${_analytics.getYearlyProjection(_apps).toStringAsFixed(0)}/yr',
                                        AppTokens.textMuted,
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
                          padding: const EdgeInsets.symmetric(horizontal: 22),
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
                                  borderRadius: BorderRadius.circular(12),
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
                                        '${expiredPromos.length} promo(s) have ended — prices may be outdated',
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
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
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
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 22),
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
                            ? Center(
                                child: Text(
                                  _apps.isEmpty
                                      ? 'No subscriptions yet'
                                      : 'No matches',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTokens.textMuted,
                                    fontSize: 15,
                                  ),
                                ),
                              )
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
                    cliffExpanded: _cliffExpanded,
                    onToggleCliff: () =>
                        setState(() => _cliffExpanded = !_cliffExpanded),
                    insightsExpanded: _insightsExpanded,
                    onToggleInsights: () =>
                        setState(() => _insightsExpanded = !_insightsExpanded),
                    matchedOffers: _matchedOffers,
                    offersEnabled: _offersEnabled,
                    onOpenOffers: () => setState(() => _tab = 3),
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
        showOfferDot: _offersEnabled && _matchedOffers.any((m) => !_seenOfferIds.contains(m.offer.id)),
        onTap: (i) {
          setState(() => _tab = i);
          if (i == 3) _markOffersSeen();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goAdd,
        backgroundColor: AppTokens.gold,
        foregroundColor: AppTokens.screenBg,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  Widget _searchField() => Container(
    height: 42,
    decoration: BoxDecoration(
      color: AppTokens.fieldBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTokens.hairline),
    ),
    child: TextField(
      onChanged: (v) => setState(() => _q = v),
      decoration: InputDecoration(
        hintText: 'Search...',
        hintStyle: TextStyle(color: AppTokens.textPlaceholder, fontSize: 13),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 18,
          color: Color(0xFF6B6B82),
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
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppTokens.fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Icon(icon, color: const Color(0xFF9B9BA8), size: 18),
    ),
  );
  Widget _chip(String name, int count, Color? color, bool selected) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _cat = selected ? null : name);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            Text(
              '$name $count',
              style: GoogleFonts.plusJakartaSans(
                color: selected ? AppTokens.gold : const Color(0xFF9B9BA8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _listCard(AppEntry app) {
    final baseClr = AppTokens.categoryColor(app.category);
    final days = app.nextRenewalDate != null
        ? app.nextRenewalDate!.difference(DateTime.now()).inDays
        : null;
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
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 28),
        child: const Icon(
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
          decoration: const BoxDecoration(
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
                    Row(
                      children: [
                        Text(
                          app.name,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (app.isPromotionalPrice &&
                            app.promotionEndsDate != null &&
                            app.promotionEndsDate!
                                    .difference(DateTime.now())
                                    .inDays <=
                                30)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTokens.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PROMO',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTokens.warning,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
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
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (days != null) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            days <= 7
                                ? Icons.notifications_active_rounded
                                : Icons.schedule_rounded,
                            size: 11,
                            color: urg?.fg,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Renews in $days day${days == 1 ? '' : 's'}',
                            style: GoogleFonts.plusJakartaSans(
                              color: urg?.fg,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
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
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 11,
                              color: AppTokens.gold,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to set billing date',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTokens.gold,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
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
          borderRadius: BorderRadius.circular(12),
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
          gradient: LinearGradient(
            colors: [baseClr, baseClr.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            app.name[0].toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTokens.hairline),
        ),
        padding: const EdgeInsets.all(14),
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
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════

class _DashboardView extends StatelessWidget {
  final List<AppEntry> apps;
  final AnalyticsService analytics;
  final Set<String> installed;
  final Map<String, int> dismissed;
  final void Function(String) onDismissInsight;
  final void Function(AppEntry) onEdit;
  final List<Category> cats;
  final VoidCallback onRefresh;
  final bool cliffExpanded;
  final VoidCallback onToggleCliff;
  final bool insightsExpanded;
  final VoidCallback onToggleInsights;
  final List<MatchedOffer> matchedOffers;
  final bool offersEnabled;
  final VoidCallback onOpenOffers;

  const _DashboardView({
    required this.apps,
    required this.analytics,
    required this.installed,
    required this.dismissed,
    required this.onDismissInsight,
    required this.onEdit,
    required this.cats,
    required this.onRefresh,
    required this.cliffExpanded,
    required this.onToggleCliff,
    required this.insightsExpanded,
    required this.onToggleInsights,
    required this.matchedOffers,
    required this.offersEnabled,
    required this.onOpenOffers,
  });

  @override
  Widget build(BuildContext context) {
    final monthly = analytics.getTotalMonthlyCost(apps);
    final active = analytics.getActiveSubscriptionCount(apps);
    final avg = active > 0 ? monthly / active : 0.0;
    final yearly = analytics.getYearlyProjection(apps);
    final insights = analytics.generateInsights(
      apps,
      installed: installed,
      dismissed: dismissed,
    );
    final healthInsight = insights
        .where((i) => i.id == 'health_score')
        .toList();
    final otherInsights = insights
        .where((i) => i.id != 'health_score')
        .toList();
    final cliff = analytics.getPromoCliff(apps);
    final coming = analytics.getComingUp(apps);
    final savings = analytics.getActivePromoSavings(apps);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 150),
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DASHBOARD',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                  ),
                ),
                Text(
                  'Overview',
                  style: GoogleFonts.playfairDisplay(
                    color: AppTokens.textStrong,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTokens.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: AppTokens.gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'DEVICE LOCAL',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.gold,
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
        const SizedBox(height: 16),

        // D1: Price-cliff alert card
        if (cliff.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTokens.gold.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTokens.gold.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: onToggleCliff,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.trending_up_rounded,
                        color: AppTokens.gold,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${cliff.length} promo(s) ending soon — spend rises ${_fmt.format(analytics.getPromoCliffTotal(apps))}/mo',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        cliffExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: AppTokens.textMuted,
                        size: 18,
                      ),
                    ],
                  ),
                ),
                if (cliffExpanded) ...[
                  const SizedBox(height: 10),
                  ...cliff.map(
                    (c) => GestureDetector(
                      onTap: () {
                        onEdit(c.app);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.app.name,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppTokens.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Ends ${_dateFmt.format(c.app.promotionEndsDate!)}',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppTokens.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${_fmt.format(c.oldCost)} → ${_fmt.format(c.newCost)}',
                              style: GoogleFonts.spaceGrotesk(
                                color: AppTokens.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // D2: Coming-up timeline
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTokens.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTokens.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Coming Up (30 days)',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (coming.isEmpty)
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppTokens.success,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Nothing due in the next 30 days',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.success,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              else ...[
                ...coming.take(cliffExpanded ? coming.length : 8).map((e) {
                  final d = e['date'] as DateTime;
                  final days = d.difference(DateTime.now()).inDays;
                  final urg = AppTokens.urgency(days);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        final entry = apps
                            .where((a) => a.id == e['entryId'])
                            .firstOrNull;
                        if (entry != null) onEdit(entry);
                      },
                      child: Row(
                        children: [
                          SizedBox(
                            width: 42,
                            child: Text(
                              _dateFmt.format(d),
                              style: GoogleFonts.spaceGrotesk(
                                color: AppTokens.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: urg?.fg ?? AppTokens.textMuted,
                              shape: BoxShape.circle,
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
                            _fmt.format(e['amount'] as double),
                            style: GoogleFonts.spaceGrotesk(
                              color: urg?.fg ?? AppTokens.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (coming.length > 8 && !cliffExpanded)
                  GestureDetector(
                    onTap: onToggleCliff,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+${coming.length - 8} more',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.brandEnd,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // D3: Savings tally
        if (savings > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTokens.success.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTokens.success.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.savings_rounded,
                  color: AppTokens.success,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Saving ${_fmt.format(savings)}/mo across ${analytics.getActivePromoCount(apps)} promo(s)',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.success,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 4 metric cards
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          children: [
            _metric(
              'Monthly Total',
              _fmt.format(monthly),
              'This month',
              Icons.payments_rounded,
              AppTokens.brandEnd,
            ),
            _metric(
              'Avg / App',
              _fmt.format(avg),
              'Per subscription',
              Icons.tag_rounded,
              const Color(0xFF06B6D4),
            ),
            _metric(
              'Active Subs',
              '$active',
              'Subscriptions',
              Icons.apps_rounded,
              AppTokens.success,
            ),
            _metric(
              'Yearly Proj.',
              _fmt.format(yearly),
              'Projected / yr',
              Icons.calendar_month_rounded,
              AppTokens.warning,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Insights
        if (insights.isNotEmpty) ...[
          Text(
            'Smart Insights',
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...otherInsights
              .take(3)
              .map(
                (ins) => _insightCard(
                  ins,
                  onDismiss: onDismissInsight,
                  onTap: ins.entryId != null
                      ? () {
                          final entry = apps
                              .where((a) => a.id == ins.entryId)
                              .firstOrNull;
                          if (entry != null) onEdit(entry);
                        }
                      : null,
                ),
              ),
          if (otherInsights.length > 3 && !insightsExpanded)
            GestureDetector(
              onTap: onToggleInsights,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  'Show all (${otherInsights.length})',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.brandEnd,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (insightsExpanded)
            ...otherInsights
                .skip(3)
                .map(
                  (ins) => _insightCard(
                    ins,
                    onDismiss: onDismissInsight,
                    onTap: ins.entryId != null
                        ? () {
                            final entry = apps
                                .where((a) => a.id == ins.entryId)
                                .firstOrNull;
                            if (entry != null) onEdit(entry);
                          }
                        : null,
                  ),
                ),
          const SizedBox(height: 10),
          ...healthInsight.map(
            (ins) => _insightCard(
              ins,
              onDismiss: onDismissInsight,
              showFactors: true,
            ),
          ),
        ],

        // O5: Savings Offers dashboard entry
        if (offersEnabled && matchedOffers.isNotEmpty) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onOpenOffers,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTokens.brandEnd.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTokens.brandEnd.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${matchedOffers.length} ways to save — up to ${_fmt.format(matchedOffers.first.savingsOverPromo)} over the promo period',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTokens.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metric(String t, String v, String l, IconData i, Color a) =>
      Container(
        decoration: BoxDecoration(
          color: AppTokens.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTokens.hairline),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: a.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(i, color: a, size: 16),
            ),
            const Spacer(),
            Text(
              v,
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l,
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  Widget _insightCard(
    SubscriptionInsight ins, {
    required void Function(String) onDismiss,
    VoidCallback? onTap,
    bool showFactors = false,
  }) {
    Color bg;
    Color fg;
    switch (ins.type) {
      case InsightType.danger:
        bg = AppTokens.danger.withValues(alpha: 0.08);
        fg = AppTokens.danger;
      case InsightType.success:
        bg = AppTokens.success.withValues(alpha: 0.08);
        fg = AppTokens.success;
      case InsightType.warning:
        bg = AppTokens.warning.withValues(alpha: 0.08);
        fg = AppTokens.warning;
      case InsightType.info:
        bg = AppTokens.brandEnd.withValues(alpha: 0.06);
        fg = AppTokens.brandEnd;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: fg.withValues(alpha: 0.15)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  ins.type == InsightType.success
                      ? Icons.check_circle_rounded
                      : ins.type == InsightType.danger
                      ? Icons.error_rounded
                      : ins.type == InsightType.warning
                      ? Icons.warning_amber_rounded
                      : Icons.info_rounded,
                  size: 16,
                  color: fg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ins.title,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ins.message,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (showFactors && ins.id == 'health_score') ...[
                      const SizedBox(height: 8),
                      ...ins.message
                          .split('\n')
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                line,
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppTokens.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => onDismiss(ins.id),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppTokens.textFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
