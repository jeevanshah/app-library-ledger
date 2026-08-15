import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_model.dart';
import '../models/offer.dart';
import '../services/offers_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/hero_empty_state.dart';
import 'add_app_screen.dart';

final _fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
final _dateFmt = DateFormat('MMM d');

Future<void> _openOfferUrl(BuildContext context, String url) async {
  bool launched = false;
  try {
    launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {}
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't open that link.")),
    );
  }
}

class OffersScreen extends StatefulWidget {
  final List<AppEntry> apps;
  final VoidCallback onSaveApp;
  const OffersScreen({super.key, required this.apps, required this.onSaveApp});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  final SettingsService _settings = SettingsService();
  List<SavingsOffer> _allOffers = [];
  bool _loading = true;
  bool _fetchFailed = false;
  String? _segment;
  String? _filterTier;
  int _sortMode = 0; // 0: 1st-yr avg, 1: Promo price, 2: Ongoing price, 3: Max savings
  static const _sortKey = 'offers_sort_mode_v2';
  AppEntry? _anchorEntry;
  bool _anchorNotSure = false;
  static const _notSureKey = 'offers_anchor_not_sure_v2';
  final ScrollController _scrollController = ScrollController();

  static const List<String> _nbnBuckets = [
    'NBN 25', 'NBN 50', 'NBN 100', 'NBN 500', 'NBN 750', 'NBN 1000', 'NBN 2000'
  ];
  static const List<String> _mobileBuckets = [
    '<20GB', '20–60GB', '60GB+', 'Unlimited'
  ];

  @override
  void initState() {
    super.initState();
    _settings.offersEnabled.addListener(_onEnabledChanged);
    _loadSortMode();
    _loadNotSure();
    if (_settings.offersEnabled.value) {
      _fetch();
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  void didUpdateWidget(OffersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apps != widget.apps) _loadAnchor();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _settings.offersEnabled.removeListener(_onEnabledChanged);
    super.dispose();
  }

  void _onEnabledChanged() {
    if (_settings.offersEnabled.value) {
      _fetch();
    } else {
      setState(() {
        _allOffers = [];
        _loading = false;
      });
    }
  }

  Future<void> _loadSortMode() async {
    final prefs = await SharedPreferences.getInstance();
    _sortMode = prefs.getInt(_sortKey) ?? 0;
    if (mounted) setState(() {});
  }

  Future<void> _loadNotSure() async {
    final prefs = await SharedPreferences.getInstance();
    _anchorNotSure = prefs.getBool(_notSureKey) ?? false;
    if (mounted) setState(() {});
  }

  Future<void> _setNotSure() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notSureKey, true);
    _anchorNotSure = true;
    if (mounted) setState(() {});
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _fetchFailed = false;
    });
    try {
      final all = await OffersService().fetch(enabled: true, force: false);
      _allOffers = all;
      if (_segment == null) {
        if (_allOffers.any((o) => o.serviceType == 'nbn')) {
          _segment = 'nbn';
        } else if (_allOffers.any((o) => o.serviceType == 'mobile')) {
          _segment = 'mobile';
        }
      }
      _loadAnchor();
      if (_filterTier == null) {
        if (_anchorEntry?.serviceTier != null && _availableTiers.contains(_anchorEntry!.serviceTier)) {
          _filterTier = _anchorEntry!.serviceTier;
        } else {
          final tiers = _availableTiers;
          if (tiers.isNotEmpty) _filterTier = tiers.first;
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchFailed = _allOffers.isEmpty;
        });
      }
    }
  }

  Future<void> _refresh() async {
    HapticFeedback.selectionClick();
    try {
      final all = await OffersService().fetch(enabled: true, force: true);
      _allOffers = all;
      _loadAnchor();
      if (_filterTier != null && !_availableTiers.contains(_filterTier)) {
        _resetTierFilter();
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _resetTierFilter() {
    final tiers = _availableTiers;
    if (_anchorEntry?.serviceTier != null && tiers.contains(_anchorEntry!.serviceTier)) {
      _filterTier = _anchorEntry!.serviceTier;
    } else {
      _filterTier = tiers.isNotEmpty ? tiers.first : null;
    }
  }

  void _loadAnchor([List<AppEntry>? apps]) {
    final allApps = (apps ?? widget.apps).toList();
    final active = allApps.where(
      (a) => a.isActiveSubscription || (a.subscriptionCost != null && a.subscriptionCost! > 0),
    ).toList();

    // 1. Explicit serviceType match for current segment
    if (_segment == 'nbn' || _segment == 'mobile') {
      final explicit = active.where((a) => a.serviceType == _segment).firstOrNull;
      if (explicit != null) {
        _anchorEntry = explicit;
        return;
      }
    }

    // 2. Keyword fallback matching ONLY among untagged apps
    if (_segment == 'nbn') {
      const nbnKws = [
        'nbn', 'broadband', 'superloop', 'tangerine', 'aussie bb',
        'aussie broadband', 'exetel', 'flip', 'dodo internet'
      ];
      for (final kw in nbnKws) {
        final m = active.where(
          (a) => a.serviceType == null && a.name.toLowerCase().contains(kw),
        ).firstOrNull;
        if (m != null) {
          _anchorEntry = m;
          return;
        }
      }
    } else if (_segment == 'mobile') {
      const mobileKws = [
        'mobile', 'sim', 'prepaid', 'postpaid', 'felix', 'amaysim',
        'boost mobile', 'lebara', 'aldi mobile', 'circles.life', 'gomo'
      ];
      for (final kw in mobileKws) {
        final m = active.where(
          (a) => a.serviceType == null && a.name.toLowerCase().contains(kw),
        ).firstOrNull;
        if (m != null) {
          _anchorEntry = m;
          return;
        }
      }
    }

    _anchorEntry = null;
  }

  Future<void> _setAnchorTier(String tier) async {
    if (_anchorEntry == null) return;
    final updated = _anchorEntry!.copyWith(serviceTier: tier);
    await StorageService().saveApp(updated);
    widget.onSaveApp();
    if (!mounted) return;
    setState(() {
      _anchorEntry = updated;
      _filterTier = tier;
    });
  }

  void _cycleSort() {
    HapticFeedback.selectionClick();
    setState(() => _sortMode = (_sortMode + 1) % 4);
    SharedPreferences.getInstance().then((p) => p.setInt(_sortKey, _sortMode));
  }

  String get _sortLabel => switch (_sortMode) {
    1 => 'Promo price',
    2 => 'Ongoing price',
    3 => 'Max savings',
    _ => '1st-year avg',
  };

  Set<String> get _availableTiers {
    var src = _allOffers;
    if (_segment == 'nbn') {
      src = src.where((o) => o.serviceType == 'nbn').toList();
    } else if (_segment == 'mobile') {
      src = src.where((o) => o.serviceType == 'mobile').toList();
    }
    final buckets = src.where((o) => o.tierBucket != null).map((o) => o.tierBucket!).toSet();
    if (_segment == 'nbn') {
      return (buckets.toList()
            ..sort((a, b) => _nbnBucketSpeed(a).compareTo(_nbnBucketSpeed(b))))
          .toSet();
    }
    if (_segment == 'mobile') {
      const order = ['<20GB', '20–60GB', '60GB+', 'Unlimited'];
      return order.where(buckets.contains).toSet();
    }
    return buckets;
  }

  bool get _showTierPicker {
    if (_anchorEntry == null) return false;
    if (_anchorNotSure) return false;
    final tier = _anchorEntry!.serviceTier;
    if (_segment == 'nbn') {
      if (tier != null && _nbnBuckets.contains(tier)) return false;
      return true;
    }
    if (_segment == 'mobile') {
      if (tier != null && _mobileBuckets.contains(tier)) return false;
      return true;
    }
    return false;
  }

  int _nbnBucketSpeed(String bucket) =>
      int.tryParse(RegExp(r'\d+').firstMatch(bucket)?.group(0) ?? '') ?? 0;

  List<String> get _tierPickerOptions {
    if (_segment == 'nbn') {
      final available = _availableTiers;
      return available.isNotEmpty ? available.toList() : _nbnBuckets;
    }
    if (_segment == 'mobile') {
      final available = _availableTiers;
      return available.isNotEmpty ? available.toList() : _mobileBuckets;
    }
    return const [];
  }

  String get _tierPickerQuestion {
    if (_segment == 'nbn') return 'What speed is your current NBN plan?';
    if (_segment == 'mobile') return 'How much data do you get on your mobile plan?';
    return 'Select your service tier';
  }

  List<SavingsOffer> _getFilteredAndSortedOffers() {
    var offers = _allOffers.where((o) {
      if (_segment == 'nbn' && o.serviceType != 'nbn') return false;
      if (_segment == 'mobile' && o.serviceType != 'mobile') return false;
      if (_filterTier != null && o.tierBucket != _filterTier) return false;
      return true;
    }).toList();

    final userCost = _anchorEntry?.subscriptionCost;

    switch (_sortMode) {
      case 1:
        offers.sort((a, b) => a.promoPrice.compareTo(b.promoPrice));
      case 2:
        offers.sort((a, b) => a.regularPrice.compareTo(b.regularPrice));
      case 3:
        if (userCost != null) {
          offers.sort((a, b) {
            final deltaA = userCost - a.avgFirstYear;
            final deltaB = userCost - b.avgFirstYear;
            return deltaB.compareTo(deltaA);
          });
        } else {
          offers.sort((a, b) => a.avgFirstYear.compareTo(b.avgFirstYear));
        }
      default:
        offers.sort((a, b) => a.avgFirstYear.compareTo(b.avgFirstYear));
    }

    return offers;
  }

  @override
  Widget build(BuildContext context) {
    if (!_settings.offersEnabled.value) return _buildOptIn();
    if (_loading && _allOffers.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: AppTokens.brandStart),
      );
    }
    if (_fetchFailed && _allOffers.isEmpty) return _buildError();
    return _buildPage();
  }

  Widget _buildOptIn() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppTokens.cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTokens.hairline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: AppTokens.isDark ? 0.3 : 0.05,
                ),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              heroIllustration('shield_lock_verified', width: 90, height: 90),
              const SizedBox(height: 18),
              Text(
                'Unlock Real Savings Deals',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  color: AppTokens.textStrong,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Compare anonymous Australian broadband and mobile deals directly against what you currently pay to find lower rates.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTokens.fieldBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTokens.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    flatIcon('shield_lock_dark', color: AppTokens.brandStart, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      '100% On-Device · Anonymous Sync',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.brandStart,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _settings.setOffersEnabled(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.brandStart,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rPill),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Enable Deals & Savings',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: AppTokens.textFaint, size: 48),
            const SizedBox(height: 16),
            Text(
              "Couldn't load latest offers — pull down to refresh.",
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textMuted,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refresh,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTokens.brandStart,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.rPill),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage() {
    final tiers = _availableTiers;
    final filteredOffers = _getFilteredAndSortedOffers();
    final totalOffersInSegment = _allOffers.where((o) {
      if (_segment == 'nbn') return o.serviceType == 'nbn';
      if (_segment == 'mobile') return o.serviceType == 'mobile';
      return true;
    }).length;

    return RefreshIndicator(
      color: AppTokens.brandStart,
      backgroundColor: AppTokens.cardBg,
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Scrollable Header Sections ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SAVINGS & DEALS',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.textFaint,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Better Rates',
                            style: GoogleFonts.playfairDisplay(
                              color: AppTokens.textStrong,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
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
                          color: AppTokens.brandStart.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(
                            AppTokens.rSmallPill,
                          ),
                          border: Border.all(
                            color: AppTokens.brandStart.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            flatIcon(
                              'tag_orange',
                              color: AppTokens.brandStart,
                              size: 13,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '$totalOffersInSegment Plans',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTokens.brandStart,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Segment switcher (NBN vs Mobile)
                  _buildSegmentControl(),
                  const SizedBox(height: 14),

                  // Hero Comparison / Potential Savings Card
                  _buildHeroSavingsCard(),
                  if (_showTierPicker) ...[
                    const SizedBox(height: 12),
                    _buildTierPickerCard(),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Sticky Tier Filter Chips ──
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyFilterHeaderDelegate(
              child: Container(
                color: AppTokens.screenBg,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: _buildFilterRow(tiers),
              ),
            ),
          ),

          // ── Sort / Count Row (non-sticky) ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
              child: _buildSortRow(filteredOffers.length),
            ),
          ),

          // ── Full-Height Vertical Plan Cards List ──
          if (filteredOffers.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 40, bottom: 80),
                child: HeroEmptyState(
                  illustration: 'search_document_scan',
                  title: 'No offers match this tier',
                  subtitle: 'Try selecting a different speed or data filter above.',
                  illustrationSize: 84,
                  compact: true,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 140),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == filteredOffers.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          _segment == 'nbn'
                              ? 'Plan pricing verified against provider rate cards. Speeds vary by connection technology.'
                              : 'Mobile plan rates verified. Always verify 5G/4G coverage in your area before switching.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textFaint,
                            fontSize: 11,
                          ),
                        ),
                      );
                    }
                    final offer = filteredOffers[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _OfferCard(
                        offer: offer,
                        now: DateTime.now(),
                        anchor: _anchorEntry,
                        anchorNotSure: _anchorNotSure,
                        onTap: () => _showDetail(offer),
                      ),
                    );
                  },
                  childCount: filteredOffers.length + 1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroSavingsCard() {
    final hasAnchor = _anchorEntry != null && _anchorEntry!.subscriptionCost != null;
    final userCost = _anchorEntry?.subscriptionCost ?? 0;
    final userTier = _anchorEntry?.serviceTier;
    final segmentLabel = _segment == 'mobile' ? 'Mobile' : 'NBN Broadband';

    // Find best deal in user's matching tier or across current segment
    SavingsOffer? bestDeal;
    if (hasAnchor) {
      final pool = _allOffers.where((o) {
        if (_segment == 'nbn' && o.serviceType != 'nbn') return false;
        if (_segment == 'mobile' && o.serviceType != 'mobile') return false;
        if (userTier != null && o.tierBucket != userTier) return false;
        return true;
      }).toList();

      if (pool.isNotEmpty) {
        pool.sort((a, b) => a.avgFirstYear.compareTo(b.avgFirstYear));
        bestDeal = pool.first;
      }
    }

    final double monthlyDelta = (hasAnchor && bestDeal != null)
        ? (userCost - bestDeal.avgFirstYear)
        : 0;
    final bool hasPositiveSavings = monthlyDelta > 0.50;
    final double annualSavings = monthlyDelta * 12;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTokens.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasPositiveSavings
              ? AppTokens.success.withValues(alpha: 0.35)
              : AppTokens.hairline,
        ),
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
            children: [
              heroIllustration(
                'piggybank_savings',
                width: 44,
                height: 44,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasPositiveSavings
                          ? 'Potential ${_fmt.format(monthlyDelta)}/mo Savings'
                          : hasAnchor
                              ? 'Plan Matching Active'
                              : 'Compare Your Current $segmentLabel Plan',
                      style: GoogleFonts.plusJakartaSans(
                        color: hasPositiveSavings
                            ? AppTokens.success
                            : AppTokens.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasPositiveSavings
                          ? 'Save up to ${_fmt.format(annualSavings)}/yr switching to ${bestDeal?.provider ?? 'a matching plan'}'
                          : hasAnchor
                              ? 'Comparing against your ${_anchorEntry!.name} plan (${_fmt.format(userCost)}/mo)'
                              : 'Tag your current $segmentLabel subscription to see live side-by-side savings.',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTokens.fieldBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTokens.hairline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        hasAnchor ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                        size: 16,
                        color: hasAnchor ? AppTokens.brandStart : AppTokens.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          hasAnchor
                              ? '${_anchorEntry!.name} · ${_fmt.format(userCost)}/mo${userTier != null ? ' ($userTier)' : ''}'
                              : 'No $segmentLabel plan tagged',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => hasAnchor
                      ? _showAnchorConfig()
                      : _showAnchorPicker(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.brandStart.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
                      border: Border.all(
                        color: AppTokens.brandStart.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      hasAnchor ? 'Edit Plan' : 'Tag Plan',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.brandStart,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentControl() {
    final segs = <String>[];
    if (_allOffers.any((o) => o.serviceType == 'nbn')) segs.add('nbn');
    if (_allOffers.any((o) => o.serviceType == 'mobile')) segs.add('mobile');
    if (_segment == null && segs.isNotEmpty) _segment = segs.first;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTokens.fieldBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Row(
        children: segs.map((s) {
          final active = _segment == s;
          final label = s == 'nbn' ? 'NBN Broadband' : 'Mobile SIM Plans';
          final icon = s == 'nbn' ? Icons.router_rounded : Icons.phone_android_rounded;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _segment = s;
                  _loadAnchor();
                  _resetTierFilter();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: active ? AppTokens.brandGradient : null,
                  color: active ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: AppTokens.brandStart.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: active ? Colors.white : AppTokens.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: GoogleFonts.plusJakartaSans(
                        color: active ? Colors.white : AppTokens.textMuted,
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFilterRow(Set<String> tiers) {
    final myTier = _anchorEntry?.serviceTier;
    final tierList = tiers.toList();

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tierList.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = tierList[i];
          final selected = _filterTier == t;
          final isMyTier = myTier != null && myTier == t;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _filterTier = t);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppTokens.brandStart
                    : AppTokens.fieldBg,
                borderRadius: BorderRadius.circular(AppTokens.rPill),
                border: Border.all(
                  color: selected
                      ? AppTokens.brandStart
                      : isMyTier
                          ? AppTokens.brandStart.withValues(alpha: 0.5)
                          : AppTokens.hairline,
                  width: isMyTier ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMyTier) ...[
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : AppTokens.brandStart,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  Text(
                    t,
                    style: GoogleFonts.plusJakartaSans(
                      color: selected ? Colors.white : AppTokens.textPrimary,
                      fontSize: 12,
                      fontWeight: selected || isMyTier
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortRow(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '$count plans in ${_filterTier ?? 'all tiers'}',
          style: GoogleFonts.plusJakartaSans(
            color: AppTokens.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        GestureDetector(
          onTap: _cycleSort,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTokens.fieldBg,
              borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
              border: Border.all(color: AppTokens.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_vert_rounded, size: 14, color: AppTokens.brandStart),
                const SizedBox(width: 4),
                Text(
                  'Sort: ${_sortLabel.toLowerCase()}',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTierPickerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.fieldBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Row(
        children: [
          Icon(
            _segment == 'mobile' ? Icons.data_usage_rounded : Icons.speed_rounded,
            size: 20,
            color: AppTokens.brandStart,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tierPickerQuestion,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Enables exact like-for-like tier matching',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _showTierPickerSheet,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTokens.brandStart,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
              ),
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Set Tier'),
          ),
        ],
      ),
    );
  }

  Widget _tierChipsWrap() {
    final options = _tierPickerOptions;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in options)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _setAnchorTier(t);
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _anchorEntry?.serviceTier == t
                    ? AppTokens.brandStart.withValues(alpha: 0.12)
                    : AppTokens.fieldBg,
                borderRadius: BorderRadius.circular(AppTokens.rPill),
                border: Border.all(
                  color: _anchorEntry?.serviceTier == t
                      ? AppTokens.brandStart
                      : AppTokens.hairline,
                  width: _anchorEntry?.serviceTier == t ? 1.5 : 1.0,
                ),
              ),
              child: Text(
                t,
                style: GoogleFonts.plusJakartaSans(
                  color: _anchorEntry?.serviceTier == t
                      ? AppTokens.brandStart
                      : AppTokens.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            _setNotSure();
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTokens.fieldBg,
              borderRadius: BorderRadius.circular(AppTokens.rPill),
              border: Border.all(color: AppTokens.hairline),
            ),
            child: Text(
              'Not sure',
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showTierPickerSheet() {
    if (_anchorEntry == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
              Text(
                _tierPickerQuestion,
                style: GoogleFonts.spaceGrotesk(
                  color: AppTokens.textStrong,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Matches you directly with comparable plans in the same speed/data bracket.',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              _tierChipsWrap(),
            ],
          ),
        ),
      ),
    );
  }

  void _showAnchorPicker() {
    final entries = widget.apps.toList();
    final label = _segment == 'mobile' ? 'Mobile SIM' : 'NBN Broadband';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
              Text(
                'Tag Your $label Plan',
                style: GoogleFonts.spaceGrotesk(
                  color: AppTokens.textStrong,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select which subscription represents your current $label service to calculate savings.',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              if (entries.isNotEmpty)
                SizedBox(
                  height: entries.length * 60.0 > 280 ? 280 : entries.length * 60.0,
                  child: ListView(
                    shrinkWrap: true,
                    children: entries
                        .map(
                          (a) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: AppTokens.fieldBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTokens.hairline),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                a.name,
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppTokens.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${_fmt.format(a.subscriptionCost ?? 0)}/mo · ${a.category}',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppTokens.textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                              trailing: a.serviceType != null
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTokens.brandStart.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        a.serviceType == 'nbn' ? 'Tagged NBN' : 'Tagged Mobile',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppTokens.brandStart,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 20,
                                    ),
                              onTap: () {
                                Navigator.pop(context);
                                _tagAsAnchor(a);
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No tracked subscriptions yet.',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _navigateToAdd();
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text('Add New $label Subscription'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.brandStart,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rPill),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToAdd() async {
    final cats = await StorageService().getCategories();
    if (!mounted) return;
    final segment = _segment ?? 'nbn';
    final previous = _anchorEntry;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddAppScreen(
          categories: cats,
          prefillServiceType: segment,
        ),
      ),
    );
    if (result == true) {
      if (previous != null && previous.serviceType == segment) {
        await StorageService().saveApp(previous.copyWith(serviceType: null));
      }
      widget.onSaveApp();
      final freshApps = await StorageService().getApps();
      if (mounted) {
        _loadAnchor(freshApps);
        setState(() {});
      }
      if (mounted && _showTierPicker) _showTierPickerSheet();
    }
  }

  Future<void> _tagAsAnchor(AppEntry entry) async {
    final segment = _segment ?? 'nbn';
    final previous = _anchorEntry;

    // Verify if existing serviceTier is valid for target segment
    String? validTier = entry.serviceTier;
    if (segment == 'nbn' && validTier != null && !_nbnBuckets.contains(validTier)) {
      validTier = null;
    } else if (segment == 'mobile' && validTier != null && !_mobileBuckets.contains(validTier)) {
      validTier = null;
    }

    final updated = entry.copyWith(
      serviceType: segment,
      serviceTier: validTier,
    );
    await StorageService().saveApp(updated);

    if (previous != null &&
        previous.id != entry.id &&
        previous.serviceType == segment) {
      await StorageService().saveApp(previous.copyWith(serviceType: null));
    }

    widget.onSaveApp();
    final freshApps = await StorageService().getApps();
    if (mounted) {
      _loadAnchor(freshApps);
      setState(() {});
    }

    if (mounted && _showTierPicker) {
      _showTierPickerSheet();
    }
  }

  Future<void> _untagAnchor() async {
    if (_anchorEntry == null) return;
    final updated = _anchorEntry!.copyWith(serviceType: null, serviceTier: null);
    await StorageService().saveApp(updated);
    widget.onSaveApp();
    final freshApps = await StorageService().getApps();
    if (mounted) {
      _loadAnchor(freshApps);
      setState(() {});
    }
  }

  void _showAnchorConfig() {
    if (_anchorEntry == null) return;
    final entries = widget.apps.toList();
    final segmentLabel = _segment == 'mobile' ? 'Mobile' : 'NBN';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current $segmentLabel Anchor',
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTokens.textStrong,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _anchorEntry!.name,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${_fmt.format(_anchorEntry!.subscriptionCost ?? 0)}/mo',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTokens.brandStart,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _tierPickerQuestion,
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _tierChipsWrap(),
              const SizedBox(height: 18),
              Divider(color: AppTokens.hairline),
              const SizedBox(height: 12),
              Text(
                'Switch to a different tracked subscription?',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (entries.isNotEmpty)
                SizedBox(
                  height: entries.length * 54.0 > 200 ? 200 : entries.length * 54.0,
                  child: ListView(
                    shrinkWrap: true,
                    children: entries
                        .map(
                          (a) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              a.name,
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTokens.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${_fmt.format(a.subscriptionCost ?? 0)}/mo',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTokens.textMuted,
                                fontSize: 11,
                              ),
                            ),
                            trailing: a.id == _anchorEntry!.id
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTokens.brandStart.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Active Anchor',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: AppTokens.brandStart,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                : null,
                            onTap: a.id == _anchorEntry!.id
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    _tagAsAnchor(a);
                                  },
                          ),
                        )
                        .toList(),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _untagAnchor();
                      },
                      icon: const Icon(Icons.link_off_rounded, size: 16, color: Colors.redAccent),
                      label: const Text('Untag Plan', style: TextStyle(color: Colors.redAccent)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.rPill),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(SavingsOffer offer) {
    HapticFeedback.selectionClick();
    final pm = offer.promoMonths.clamp(0, 12);
    final firstYearTotal = offer.avgFirstYear * 12;
    final isFlat = pm == 0 || pm == 12 || offer.promoPrice == offer.regularPrice;
    final anchorCost = _anchorEntry?.subscriptionCost;
    final anchor12MoTotal = anchorCost != null ? anchorCost * 12 : null;
    final netAnnualSavings = anchor12MoTotal != null ? anchor12MoTotal - firstYearTotal : null;

    final specParts = <String>[];
    if (offer.techType != null) specParts.add(offer.techType!);
    if (offer.dataGB != null && offer.dataGB! > 0) specParts.add('${offer.dataGB}GB data');

    final tierMatch = _anchorEntry?.serviceTier != null &&
        offer.tierBucket != null &&
        _anchorEntry!.serviceTier == offer.tierBucket;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
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

              // ── Header Card ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTokens.brandStart.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: flatIcon(
                      'tag_orange',
                      color: AppTokens.brandStart,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (offer.tier != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: tierMatch
                                      ? AppTokens.brandStart.withValues(alpha: 0.15)
                                      : AppTokens.fieldBg,
                                  borderRadius: BorderRadius.circular(
                                    AppTokens.rSmallPill,
                                  ),
                                  border: Border.all(
                                    color: tierMatch
                                        ? AppTokens.brandStart.withValues(alpha: 0.3)
                                        : AppTokens.hairline,
                                  ),
                                ),
                                child: Text(
                                  offer.tier! + (tierMatch ? ' · Your Tier' : ''),
                                  style: GoogleFonts.plusJakartaSans(
                                    color: tierMatch
                                        ? AppTokens.brandStart
                                        : AppTokens.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                offer.provider,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppTokens.textMuted,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          offer.title,
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTokens.textStrong,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Side-by-Side Savings Comparison ──
              if (anchorCost != null && netAnnualSavings != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: netAnnualSavings > 0
                        ? AppTokens.success.withValues(alpha: 0.08)
                        : AppTokens.fieldBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: netAnnualSavings > 0
                          ? AppTokens.success.withValues(alpha: 0.35)
                          : AppTokens.hairline,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YOUR CURRENT PLAN',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTokens.textFaint,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _fmt.format(anchorCost),
                                  style: GoogleFonts.spaceGrotesk(
                                    color: AppTokens.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${_fmt.format(anchor12MoTotal)}/yr total',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTokens.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 44,
                            color: AppTokens.hairline,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'THIS DEAL',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTokens.textFaint,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _fmt.format(offer.avgFirstYear),
                                  style: GoogleFonts.spaceGrotesk(
                                    color: AppTokens.brandStart,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${_fmt.format(firstYearTotal)}/yr avg',
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
                      if (netAnnualSavings > 0) ...[
                        const SizedBox(height: 12),
                        Divider(color: AppTokens.success.withValues(alpha: 0.2), height: 1),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.savings_rounded, size: 16, color: AppTokens.success),
                            const SizedBox(width: 8),
                            Text(
                              'You save ${_fmt.format(netAnnualSavings)} in the 1st year',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTokens.success,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── 12-Month Trajectory Timeline ──
              Text(
                '12-MONTH PRICE TIMELINE',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textFaint,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTokens.fieldBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTokens.hairline),
                ),
                child: Column(
                  children: [
                    _trajectoryStrip(pm, flat: isFlat),
                    if (isFlat)
                      _dtlRow('Month 1–12', _fmt.format(offer.promoPrice), true)
                    else ...[
                      _dtlRow(
                        'Month${pm > 1 ? 's' : ''} 1–$pm (Introductory Rate)',
                        _fmt.format(offer.promoPrice),
                        true,
                      ),
                      Divider(color: AppTokens.hairline, height: 1),
                      _dtlRow(
                        'Month${(12 - pm) > 1 ? 's' : ''} ${pm + 1}–12 (Regular Rate)',
                        _fmt.format(offer.regularPrice),
                        false,
                        muted: true,
                      ),
                    ],
                    Divider(color: AppTokens.hairline, height: 1),
                    _dtlRow(
                      'First-Year Total Cost',
                      _fmt.format(firstYearTotal),
                      false,
                      gold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Plan Specs Pills ──
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _specBadge(Icons.check_circle_outline_rounded, 'No lock-in contract'),
                  _specBadge(Icons.wifi_rounded, offer.techType ?? 'High speed connection'),
                  if (offer.dataGB != null && offer.dataGB! > 0)
                    _specBadge(Icons.data_usage_rounded, '${offer.dataGB}GB data allowance'),
                  if (offer.validUntil != null)
                    _specBadge(Icons.schedule_rounded, 'Valid until ${_dateFmt.format(offer.validUntil!)}'),
                ],
              ),
              const SizedBox(height: 20),

              // ── Action CTA Button ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _openOfferUrl(context, offer.url);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text('View Deal on ${offer.provider} ↗'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.brandStart,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rPill),
                    ),
                    textStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _specBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTokens.fieldBg,
        borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTokens.brandStart),
          const SizedBox(width: 5),
          Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _trajectoryStrip(int promoMonths, {required bool flat}) {
    final pm = promoMonths.clamp(0, 12);
    final reg = 12 - pm;
    final promoColor = AppTokens.success.withValues(alpha: 0.25);
    final regularColor = AppTokens.hairline.withValues(alpha: 0.8);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 20,
              child: flat
                  ? Container(color: promoColor)
                  : Row(
                      children: [
                        Expanded(flex: pm, child: Container(color: promoColor)),
                        Container(width: 2, color: AppTokens.warning),
                        Expanded(flex: reg, child: Container(color: regularColor)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _stripLegendDot(AppTokens.success, 'Promo Rate ($pm mo)'),
              const SizedBox(width: 14),
              if (!flat) ...[
                _stripLegendDot(AppTokens.warning, 'Price Cliff'),
                const SizedBox(width: 14),
                _stripLegendDot(AppTokens.textMuted, 'Regular Rate ($reg mo)'),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _stripLegendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );

  Widget _dtlRow(
    String label,
    String amount,
    bool isPromo, {
    bool gold = false,
    bool muted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isPromo ? AppTokens.success.withValues(alpha: 0.04) : Colors.transparent,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: muted ? AppTokens.textMuted : AppTokens.textPrimary,
                fontSize: 12.5,
                fontWeight: gold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            amount,
            style: GoogleFonts.spaceGrotesk(
              color: gold
                  ? AppTokens.brandStart
                  : muted
                      ? AppTokens.textMuted
                      : AppTokens.textPrimary,
              fontSize: 13,
              fontWeight: gold ? FontWeight.w700 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyFilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  const _StickyFilterHeaderDelegate({required this.child});

  @override
  double get minExtent => 54.0;

  @override
  double get maxExtent => 54.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StickyFilterHeaderDelegate oldDelegate) {
    return true;
  }
}

class _OfferCard extends StatelessWidget {
  final SavingsOffer offer;
  final DateTime now;
  final AppEntry? anchor;
  final bool anchorNotSure;
  final VoidCallback onTap;

  const _OfferCard({
    required this.offer,
    required this.now,
    this.anchor,
    required this.anchorNotSure,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final daysLeft = offer.validUntil?.difference(now).inDays;
    final urgent = daysLeft != null && daysLeft <= 7;
    final avg = offer.avgFirstYear;
    final userCost = anchor?.subscriptionCost;
    final userTier = anchor?.serviceTier;
    final tierMatch = userTier != null && offer.tierBucket != null && userTier == offer.tierBucket;
    final delta = userCost != null ? userCost - avg : null;
    final isFlat = offer.promoMonths <= 0 || offer.promoPrice == offer.regularPrice;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTokens.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (delta != null && delta > 0.50)
                ? AppTokens.success.withValues(alpha: 0.35)
                : AppTokens.hairline,
          ),
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
            // Top Row: Provider + Tier + Badges
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.provider,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        offer.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (offer.tier != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tierMatch
                          ? AppTokens.brandStart.withValues(alpha: 0.15)
                          : AppTokens.fieldBg,
                      borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
                      border: Border.all(
                        color: tierMatch
                            ? AppTokens.brandStart.withValues(alpha: 0.35)
                            : AppTokens.hairline,
                      ),
                    ),
                    child: Text(
                      offer.tier! + (tierMatch ? ' · Your Tier' : ''),
                      style: GoogleFonts.plusJakartaSans(
                        color: tierMatch
                            ? AppTokens.brandStart
                            : AppTokens.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Price & Savings Row (Protected against RenderFlex overflow)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _fmt.format(avg),
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTokens.textStrong,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '/mo avg',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                ),
                if (delta != null && !anchorNotSure)
                  Flexible(
                    child: Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: delta > 0.50
                            ? AppTokens.success.withValues(alpha: 0.15)
                            : AppTokens.fieldBg,
                        borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
                        border: Border.all(
                          color: delta > 0.50
                              ? AppTokens.success.withValues(alpha: 0.3)
                              : AppTokens.hairline,
                        ),
                      ),
                      child: Text(
                        delta > 0.50
                            ? 'Save ${_fmt.format(delta)}/mo'
                            : delta < -0.50
                                ? '+${_fmt.format(delta.abs())}/mo vs yours'
                                : 'Same as yours',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: delta > 0.50
                              ? AppTokens.success
                              : AppTokens.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Promo Breakdown Text
            Text.rich(
              TextSpan(
                children: isFlat
                    ? [
                        TextSpan(
                          text: _fmt.format(offer.regularPrice),
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.brandStart,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: ' flat ongoing · no promo cliff',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ]
                    : [
                        TextSpan(
                          text: _fmt.format(offer.promoPrice),
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.brandStart,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: ' for ',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                        TextSpan(
                          text: '${offer.promoMonths} mo',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textPrimary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: ' · then ',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                        TextSpan(
                          text: '${_fmt.format(offer.regularPrice)}/mo',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.brandStart,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
              ),
            ),
            const SizedBox(height: 12),

            // Mini Trajectory Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: isFlat
                    ? Container(
                        color: AppTokens.success.withValues(alpha: 0.35),
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: offer.promoMonths.clamp(1, 12),
                            child: Container(
                              color: AppTokens.success.withValues(alpha: 0.4),
                            ),
                          ),
                          Container(width: 2, color: AppTokens.warning),
                          Expanded(
                            flex: (12 - offer.promoMonths).clamp(1, 12),
                            child: Container(
                              color: AppTokens.hairline.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 14),

            // Action & Expiry Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 14,
                        color: AppTokens.brandStart,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          offer.validUntil != null
                              ? 'Ends ${_dateFmt.format(offer.validUntil!)}'
                              : 'Ongoing rate',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: urgent ? AppTokens.warning : AppTokens.textFaint,
                            fontSize: 11,
                            fontWeight: urgent ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _openOfferUrl(context, offer.url);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.brandStart,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
                    ),
                    textStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View Deal'),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
