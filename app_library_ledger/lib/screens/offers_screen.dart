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
import 'add_app_screen.dart';

final _fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
final _dateFmt = DateFormat('MMM d');

Future<void> _openOfferUrl(BuildContext context, String url) async {
  bool launched = false;
  try {
    launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open that link.")));
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
  int _sortMode = 0;
  static const _sortKey = 'offers_sort_mode';
  AppEntry? _anchorEntry;
  bool _anchorNotSure = false;
  static const _notSureKey = 'offers_anchor_not_sure_v2';
  late final PageController _pageCtrl = PageController();

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
    _pageCtrl.dispose();
    _settings.offersEnabled.removeListener(_onEnabledChanged);
    super.dispose();
  }

  void _onEnabledChanged() {
    if (_settings.offersEnabled.value) {
      _fetch();
    } else {
      setState(() { _allOffers = []; _loading = false; });
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
    setState(() { _loading = true; _fetchFailed = false; });
    try {
      final all = await OffersService().fetch(enabled: true, force: false);
      _allOffers = all;
      // Default segment on first load
      if (_segment == null) {
        if (_allOffers.any((o) => o.serviceType == 'nbn')) _segment = 'nbn';
        else if (_allOffers.any((o) => o.serviceType == 'mobile')) _segment = 'mobile';
      }
      _loadAnchor();
      // Default tier filter to first available tier
      if (_filterTier == null) {
        final tiers = _availableTiers;
        if (tiers.isNotEmpty) _filterTier = tiers.first;
      }
      if (mounted) setState(() { _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _fetchFailed = _allOffers.isEmpty; });
    }
  }

  Future<void> _refresh() async {
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
    _filterTier = tiers.isNotEmpty ? tiers.first : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _pageCtrl.jumpToPage(0));
  }

  void _loadAnchor([List<AppEntry>? apps]) {
    final active = (apps ?? widget.apps).where((a) => a.isActiveSubscription).toList();
    final utils = active.where((a) => a.category == 'Utilities').toList();
    // 1. Explicit serviceType match (user-confirmed tag) — any category, since tagging is deliberate
    if (_segment == 'nbn' || _segment == 'mobile') {
      final explicit = active.where((a) => a.serviceType == _segment).firstOrNull;
      if (explicit != null) { _anchorEntry = explicit; return; }
    }
    // 2. Segment-aware keyword matching
    const nbnKws = ['nbn','internet','broadband','tangerine','superloop','dodo','belong','flip','exetel','iinet','tpg','telstra','optus','vodafone','spintel'];
    const mobileKws = ['mobile','sim','prepaid','spintel','telstra','optus','vodafone','amaysim','felix','kogan','boost','aldi','lebara'];
    if (_segment == 'nbn' || _segment == null) {
      for (final kw in nbnKws) {
        final m = utils.where((a) => a.name.toLowerCase().contains(kw)).firstOrNull;
        if (m != null) { _anchorEntry = m; return; }
      }
    }
    if (_segment == 'mobile' || _segment == null) {
      for (final kw in mobileKws) {
        final m = utils.where((a) => a.name.toLowerCase().contains(kw)).firstOrNull;
        if (m != null) { _anchorEntry = m; return; }
      }
    }
    // 3. When no segment selected (All): fallback to most expensive Utilities entry
    // When segment is set: leave anchor null so user is prompted to pick
    if (_segment == null && utils.isNotEmpty) {
      utils.sort((a, b) => (b.subscriptionCost ?? 0).compareTo(a.subscriptionCost ?? 0));
      _anchorEntry = utils.first;
      return;
    }
    _anchorEntry = null;
  }

  Future<void> _setAnchorTier(String tier) async {
    if (_anchorEntry == null) return;
    final updated = _anchorEntry!.copyWith(serviceTier: tier);
    await StorageService().saveApp(updated);
    widget.onSaveApp();
    if (!mounted) return;
    setState(() { _anchorEntry = updated; _filterTier = tier; });
  }

  void _cycleSort() {
    setState(() { _sortMode = (_sortMode + 1) % 3; });
    SharedPreferences.getInstance().then((p) => p.setInt(_sortKey, _sortMode));
  }

  String get _sortLabel => switch (_sortMode) { 1 => 'Promo price', 2 => 'Ongoing price', _ => 'First-year avg' };

  /// Returned as a [Set] for the filter-row/carousel call sites, but built
  /// from an already-sorted list — [LinkedHashSet] (Dart's default `Set`)
  /// preserves insertion order, so `.toList()`/`.first` on the result stay
  /// in speed/data order instead of arbitrary catalog order.
  Set<String> get _availableTiers {
    var src = _allOffers;
    if (_segment == 'nbn') src = src.where((o) => o.serviceType == 'nbn').toList();
    else if (_segment == 'mobile') src = src.where((o) => o.serviceType == 'mobile').toList();
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
    if (_anchorEntry!.serviceTier != null) return false;
    if (_segment != 'nbn' && _segment != 'mobile') return false;
    return _tierPickerOptions.isNotEmpty;
  }

  /// Numeric speed embedded in an "NBN N" bucket label, for sorting —
  /// a plain string sort would put "NBN 1000" before "NBN 25".
  int _nbnBucketSpeed(String bucket) =>
      int.tryParse(RegExp(r'\d+').firstMatch(bucket)?.group(0) ?? '') ?? 0;

  /// Tier pill options for the picker card, derived from whichever
  /// tiers actually appear in the current catalog ([_availableTiers])
  /// rather than a fixed list — so a new NBN speed tier (or a mobile
  /// data bucket) shows up here automatically as the offers feed adds
  /// them, instead of needing a code change every time.
  List<String> get _tierPickerOptions {
    if (_segment == 'nbn' || _segment == 'mobile') return _availableTiers.toList();
    return const [];
  }

  String get _tierPickerQuestion {
    if (_segment == 'nbn') return 'What speed are you on?';
    if (_segment == 'mobile') return 'How much data do you get now?';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (!_settings.offersEnabled.value) return _buildOptIn();
    if (_loading && _allOffers.isEmpty) return const Center(child: CircularProgressIndicator(color: AppTokens.gold));
    if (_fetchFailed && _allOffers.isEmpty) return _buildError();
    return _buildPage();
  }

  Widget _buildOptIn() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 80, height: 80, decoration: BoxDecoration(color: AppTokens.fieldBg, shape: BoxShape.circle, border: Border.all(color: AppTokens.hairline)), child: const Icon(Icons.lock_rounded, color: AppTokens.gold, size: 36)),
            const SizedBox(height: 24),
            Text('See real savings offers matched to what you already pay', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('Offers are downloaded anonymously. What you track never leaves your device. Links may earn us a commission.', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12, height: 1.5)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppTokens.brandGradient, borderRadius: BorderRadius.circular(16)),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () { HapticFeedback.mediumImpact(); _settings.setOffersEnabled(true); },
                    child: Center(
                      child: Text('Enable Offers', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
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

  Widget _buildError() {
    return Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_rounded, color: AppTokens.textFaint, size: 48),
      const SizedBox(height: 16),
      Text("Couldn't load offers — pull to refresh.", textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 14)),
    ])));
  }

  Widget _buildPage() {
    final tiers = _availableTiers;
    final totalOffers = _allOffers.where((o) {
      if (_segment == 'nbn') return o.serviceType == 'nbn';
      if (_segment == 'mobile') return o.serviceType == 'mobile';
      return true;
    }).length;
    return RefreshIndicator(
      color: AppTokens.gold, backgroundColor: AppTokens.cardBg, onRefresh: _refresh,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(AppTokens.padHeader, 12, AppTokens.padHeader, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(child: Text('Offers', style: GoogleFonts.playfairDisplay(color: AppTokens.textStrong, fontSize: 28, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: _showPrivacyExplain, child: const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.info_outline_rounded, size: 14, color: AppTokens.textMuted))),
            Text('$totalOffers plans', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 16),
          _buildSegmentControl(),
          const SizedBox(height: 12),
          _buildAnchorBar(),
          if (_showTierPicker) ...[const SizedBox(height: AppTokens.gapItem), _buildTierPickerCard(), const SizedBox(height: AppTokens.gapItem)],
        ]))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: AppTokens.padHeader), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 12),
          _buildFilterRow(tiers),
          if (tiers.isNotEmpty) const SizedBox(height: 8),
          _buildSortRow(),
          const SizedBox(height: 12),
        ]))),
        if (totalOffers == 0)
          SliverFillRemaining(child: Center(child: Text('No offers match your selection.', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 14))))
        else
          SliverFillRemaining(child: _buildCarousel(tiers)),
      ]),
    );
  }

  Widget _buildCarousel(Set<String> tiers) {
    final tierList = tiers.toList();
    if (tierList.isEmpty) return const SizedBox.shrink();
    final pages = tierList.map((t) => _buildTierScroll(t)).toList();
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (_) { FocusScope.of(context).unfocus(); return false; },
      child: PageView(
        controller: _pageCtrl,
        onPageChanged: (i) {
          setState(() {
            _filterTier = tierList[i];
          });
        },
        children: pages,
      ),
    );
  }

  Widget _buildTierScroll(String tier) {
    final offers = _allOffers.where((o) {
      if (_segment == 'nbn') return o.serviceType == 'nbn';
      if (_segment == 'mobile') return o.serviceType == 'mobile';
      return true;
    }).where((o) => o.tierBucket == tier).toList();
    switch (_sortMode) {
      case 1: offers.sort((a, b) => a.promoPrice.compareTo(b.promoPrice));
      case 2: offers.sort((a, b) => a.regularPrice.compareTo(b.regularPrice));
      default: offers.sort((a, b) => a.avgFirstYear.compareTo(b.avgFirstYear));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(AppTokens.padHeader, 0, AppTokens.padHeader, 80),
      itemCount: offers.isEmpty ? 1 : offers.length + 1,
      itemBuilder: (_, i) {
        if (offers.isEmpty) {
          return Center(child: Padding(padding: const EdgeInsets.only(top: 40), child: Text('No offers at $tier', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 13))));
        }
        if (i == offers.length) {
          return Padding(padding: const EdgeInsets.only(top: 16), child: Text(
            _segment == 'nbn'
                ? 'Prices verified at time of listing — availability varies by address.'
                : 'Prices verified at time of listing. Always confirm with the provider.',
            textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPlaceholder, fontSize: 11)));
        }
        return Padding(padding: const EdgeInsets.only(bottom: AppTokens.gapItem), child: _OfferCard(
          offer: offers[i], now: DateTime.now(),
          anchor: _anchorEntry, anchorNotSure: _anchorNotSure,
          onTap: () => _showDetail(offers[i]),
        ));
      },
    );
  }

  Widget _buildSegmentControl() {
    final segs = <String>[];
    if (_allOffers.any((o) => o.serviceType == 'nbn')) segs.add('nbn');
    if (_allOffers.any((o) => o.serviceType == 'mobile')) segs.add('mobile');
    if (_segment == null && segs.isNotEmpty) _segment = segs.first;
    return Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: AppTokens.fieldBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTokens.hairline)),
      child: Row(children: segs.map((s) => Expanded(child: GestureDetector(
        onTap: () => setState(() { _segment = _segment == s ? null : s; _loadAnchor(); _resetTierFilter(); }),
        child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: _segment == s ? AppTokens.gold : Colors.transparent, borderRadius: BorderRadius.circular(7)),
          child: Text(s == 'nbn' ? 'NBN' : 'Mobile', textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(color: _segment == s ? AppTokens.screenBg : AppTokens.textMuted, fontSize: 12.5, fontWeight: FontWeight.w500)),
        ),
      ))).toList()),
    );
  }

  Widget _buildAnchorBar() {
    final hasEntry = _anchorEntry != null;
    final hasTier = hasEntry && _anchorEntry!.serviceTier != null;
    final hasUtilities = widget.apps.any((a) => a.category == 'Utilities' && a.isActiveSubscription);
    final hasPromoCliff = hasEntry && _anchorEntry!.isPromotionalPrice && _anchorEntry!.promotionEndsDate != null;
    final daysToCliff = hasPromoCliff ? _anchorEntry!.promotionEndsDate!.difference(DateTime.now()).inDays : null;
    final cliffUrgent = daysToCliff != null && daysToCliff <= 7;
    return Container(padding: const EdgeInsets.symmetric(horizontal: AppTokens.padCard, vertical: 9),
      decoration: BoxDecoration(color: AppTokens.cardBg, borderRadius: BorderRadius.circular(AppTokens.rInput), border: Border.all(color: AppTokens.gold.withValues(alpha: 0.5))),
      child: Row(children: [
        Expanded(child: hasEntry
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: 'You pay ', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12.5)),
                TextSpan(text: _fmt.format(_anchorEntry!.subscriptionCost ?? 0), style: GoogleFonts.spaceGrotesk(color: AppTokens.gold, fontSize: 12.5, fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
                TextSpan(text: '/mo', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12.5)),
                if (hasTier) TextSpan(text: ' · ${_anchorEntry!.serviceTier}', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12.5)),
              ])),
              if (hasPromoCliff)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(
                  'Promo ends ${_dateFmt.format(_anchorEntry!.promotionEndsDate!)}${_anchorEntry!.regularPrice != null ? ' — then ${_fmt.format(_anchorEntry!.regularPrice!)}/mo' : ''}',
                  style: GoogleFonts.plusJakartaSans(color: cliffUrgent ? AppTokens.warning : AppTokens.textFaint, fontSize: 10.5, fontWeight: cliffUrgent ? FontWeight.w500 : FontWeight.w400),
                )),
            ])
          : hasUtilities
            ? Text('Tap to pick your plan', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12.5))
            : Text(_segment == 'mobile' ? 'Add your mobile plan' : 'Add your internet plan', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12.5)),
        ),
        GestureDetector(
          onTap: () => hasEntry ? _showAnchorConfig() : hasUtilities ? _showAnchorPicker() : _navigateToAdd(),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(border: Border.all(color: AppTokens.hairlineStrong), borderRadius: BorderRadius.circular(8)),
            child: Text(hasEntry ? 'Edit' : hasUtilities ? 'Pick' : 'Add', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ),
        ),
      ]),
    );
  }

  void _showAnchorPicker() {
    if (_segment != 'nbn' && _segment != 'mobile') return;
    final entries = widget.apps.where((a) => a.isActiveSubscription).toList();
    final label = _segment == 'mobile' ? 'Mobile' : 'NBN';
    showModalBottomSheet(context: context, backgroundColor: AppTokens.cardBg, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Which plan is your $label?', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Tap an existing subscription to tag it as $label', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12.5)),
        const SizedBox(height: 16),
        if (entries.isNotEmpty) SizedBox(
          height: entries.length * 56.0 + 8 > 360 ? 360 : entries.length * 56.0 + 8,
          child: ListView(children: entries.map((a) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(a.name, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w500)),
            subtitle: Text('${_fmt.format(a.subscriptionCost ?? 0)}/mo · ${a.category}', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
            trailing: a.serviceType != null ? Text(a.serviceType == 'nbn' ? 'NBN' : 'Mobile', style: GoogleFonts.plusJakartaSans(color: AppTokens.textFaint, fontSize: 11)) : const Icon(Icons.chevron_right_rounded, color: AppTokens.textMuted, size: 20),
            onTap: a.serviceType != null ? null : () { Navigator.pop(context); _tagAsAnchor(a); },
          )).toList()),
        ),
        if (entries.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('No active subscriptions yet.', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12.5))),
        const Divider(color: AppTokens.hairlineStrong),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.add_rounded, color: AppTokens.gold, size: 22),
          title: Text('Add new subscription', style: GoogleFonts.plusJakartaSans(color: AppTokens.gold, fontSize: 12.5, fontWeight: FontWeight.w600)),
          onTap: () { Navigator.pop(context); _navigateToAdd(); },
        ),
      ]))),
    );
  }

  Future<void> _navigateToAdd() async {
    final cats = await StorageService().getCategories();
    if (!mounted) return;
    final segment = _segment ?? 'nbn';
    final previous = _anchorEntry;
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => AddAppScreen(
      categories: cats,
      prefillServiceType: segment,
    )));
    if (result == true) {
      if (previous != null && previous.serviceType == segment) {
        await StorageService().saveApp(previous.copyWith(serviceType: null));
      }
      widget.onSaveApp();
      final freshApps = await StorageService().getApps();
      if (mounted) { _loadAnchor(freshApps); setState(() {}); }
      if (mounted && _showTierPicker) _showTierPickerSheet();
    }
  }

  Future<void> _tagAsAnchor(AppEntry entry) async {
    final previous = _anchorEntry;
    final updated = entry.copyWith(serviceType: _segment);
    await StorageService().saveApp(updated);
    if (previous != null && previous.id != entry.id && previous.serviceType == _segment) {
      await StorageService().saveApp(previous.copyWith(serviceType: null));
    }
    widget.onSaveApp();
    final freshApps = await StorageService().getApps();
    if (mounted) { _loadAnchor(freshApps); setState(() {}); }
    if (mounted && _showTierPicker) _showTierPickerSheet();
  }

  void _showAnchorConfig() {
    if (_anchorEntry == null) return;
    if (_segment != 'nbn' && _segment != 'mobile') return;
    final entries = widget.apps.where((a) => a.isActiveSubscription).toList();
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: AppTokens.cardBg, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 32, height: 4, decoration: BoxDecoration(color: AppTokens.hairlineStrong, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Text('Configure your plan', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w700))),
          Text('${_fmt.format(_anchorEntry!.subscriptionCost ?? 0)}/mo', style: GoogleFonts.spaceGrotesk(color: AppTokens.gold, fontSize: 12.5, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 16),
        Text(_tierPickerQuestion + ' (optional)', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _tierChipsWrap(),
        const SizedBox(height: AppTokens.gapItem),
        const Divider(color: AppTokens.hairlineStrong),
        const SizedBox(height: AppTokens.gapItem),
        Text('Switch to a different plan?', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (entries.isNotEmpty) SizedBox(
          height: entries.length * 52.0 + 8 > 320 ? 320 : entries.length * 52.0 + 8,
          child: ListView(children: entries.map((a) => ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text(a.name, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w500)),
            subtitle: Text('${_fmt.format(a.subscriptionCost ?? 0)}/mo \u00B7 ${a.category}', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
            trailing: a.id == _anchorEntry!.id ? Text('Current', style: GoogleFonts.plusJakartaSans(color: AppTokens.gold, fontSize: 11, fontWeight: FontWeight.w600)) : a.serviceType != null ? Text(a.serviceType == 'nbn' ? 'NBN' : 'Mobile', style: GoogleFonts.plusJakartaSans(color: AppTokens.textFaint, fontSize: 11)) : null,
            onTap: a.id == _anchorEntry!.id ? null : () { Navigator.pop(context); _tagAsAnchor(a); },
          )).toList()),
        ),
        if (entries.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('No active subscriptions yet.', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12.5))),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.add_rounded, color: AppTokens.gold, size: 20),
          title: Text('Add new subscription', style: GoogleFonts.plusJakartaSans(color: AppTokens.gold, fontSize: 12.5, fontWeight: FontWeight.w600)),
          onTap: () { Navigator.pop(context); _navigateToAdd(); },
        ),
      ]))),
    );
  }

  Widget _buildTierPickerCard() {
    return Container(padding: const EdgeInsets.symmetric(horizontal: AppTokens.padCard, vertical: 12), decoration: BoxDecoration(color: AppTokens.fieldBg, borderRadius: BorderRadius.circular(AppTokens.rInput), border: Border.all(color: AppTokens.hairlineStrong)),
      child: Row(children: [
        Expanded(child: Text('$_tierPickerQuestion (optional)', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600))),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _showTierPickerSheet,
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(border: Border.all(color: AppTokens.hairlineStrong), borderRadius: BorderRadius.circular(8)),
            child: Text('Set', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ),
        ),
      ]),
    );
  }

  Widget _tierChipsWrap() {
    final options = _tierPickerOptions;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final t in options)
        GestureDetector(onTap: () { HapticFeedback.selectionClick(); _setAnchorTier(t); Navigator.pop(context); },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: _anchorEntry?.serviceTier == t ? AppTokens.gold.withValues(alpha: 0.12) : AppTokens.fieldBg, borderRadius: BorderRadius.circular(AppTokens.rPill), border: Border.all(color: _anchorEntry?.serviceTier == t ? AppTokens.gold.withValues(alpha: 0.3) : AppTokens.hairline)),
            child: Text(t, style: GoogleFonts.plusJakartaSans(color: _anchorEntry?.serviceTier == t ? AppTokens.gold : AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ),
      GestureDetector(onTap: () { HapticFeedback.selectionClick(); _setNotSure(); Navigator.pop(context); },
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: Text('Not sure', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12.5)))),
    ]);
  }

  void _showTierPickerSheet() {
    if (_anchorEntry == null) return;
    if (_segment != 'nbn' && _segment != 'mobile') return;
    showModalBottomSheet(context: context, backgroundColor: AppTokens.cardBg, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 32, height: 4, decoration: BoxDecoration(color: AppTokens.hairlineStrong, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        Text(_tierPickerQuestion, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Helps match you to the right tier of offers.', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12.5)),
        const SizedBox(height: 16),
        _tierChipsWrap(),
      ]))),
    );
  }

  Widget _buildFilterRow(Set<String> tiers) {
    final myTier = _anchorEntry?.serviceTier;
    final tierList = tiers.toList();
    final showMyTierChip = myTier != null && tiers.contains(myTier);
    return SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, children: [
      if (showMyTierChip)
        Padding(padding: const EdgeInsets.only(right: 6), child: GestureDetector(
          onTap: () { _pageCtrl.animateToPage(tierList.indexOf(myTier), duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic); },
          child: Container(padding: const EdgeInsets.only(left: 10, right: 12, top: 6, bottom: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _filterTier == myTier ? AppTokens.gold : Colors.transparent, borderRadius: BorderRadius.circular(AppTokens.rPill), border: Border.all(color: AppTokens.gold, width: _filterTier == myTier ? 1 : 1)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTokens.gold, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(myTier, style: GoogleFonts.plusJakartaSans(color: _filterTier == myTier ? AppTokens.screenBg : AppTokens.gold, fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
          ),
        )),
      for (var i = 0; i < tierList.length; i++)
        if (!showMyTierChip || tierList[i] != myTier)
          Padding(padding: const EdgeInsets.only(right: 6), child: _chip(tierList[i], i)),
    ]));
  }

  Widget _chip(String label, int pageIndex) {
    final selected = _filterTier == label;
    return GestureDetector(
      onTap: () { _pageCtrl.animateToPage(pageIndex, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic); },
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: selected ? AppTokens.gold : Colors.transparent, borderRadius: BorderRadius.circular(AppTokens.rPill), border: Border.all(color: selected ? AppTokens.gold : AppTokens.hairlineStrong)),
        child: Text(label, style: GoogleFonts.plusJakartaSans(color: selected ? AppTokens.screenBg : AppTokens.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildSortRow() {
    return Row(children: [
      GestureDetector(onTap: _showAvgExplain, child: const Icon(Icons.info_outline_rounded, size: 14, color: AppTokens.textMuted)),
      const Spacer(),
      GestureDetector(onTap: _cycleSort, child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Sort: ${_sortLabel.toLowerCase()}', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
        const SizedBox(width: 6),
        Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => Container(
          width: 4, height: 4,
          margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
          decoration: BoxDecoration(shape: BoxShape.circle, color: i == _sortMode ? AppTokens.gold : AppTokens.hairlineStrong),
        ))),
        const SizedBox(width: 4), const Icon(Icons.swap_vert_rounded, size: 14, color: AppTokens.textMuted),
      ])),
    ]);
  }

  void _showPrivacyExplain() {
    showModalBottomSheet(context: context, backgroundColor: AppTokens.cardBg, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your privacy', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text('Fetched anonymously — what you track never leaves your device.', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 13, height: 1.5)),
      ]))),
    );
  }

  void _showAvgExplain() {
    showModalBottomSheet(context: context, backgroundColor: AppTokens.cardBg, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('First-year average', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text('First-year average combines the promo months and ongoing price over 12 months. A short cheap promo can\'t hide an expensive ongoing plan.', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 13, height: 1.5)),
      ]))),
    );
  }

  void _showDetail(SavingsOffer offer) {
    final pm = offer.promoMonths.clamp(0, 12);
    final firstYearTotal = offer.avgFirstYear * 12;
    final isFlat = pm == 0 || pm == 12 || offer.promoPrice == offer.regularPrice;
    final anchorCost = _anchorEntry?.subscriptionCost;
    final specParts = <String>[];
    if (offer.techType != null) specParts.add(offer.techType!);
    if (offer.dataGB != null && offer.dataGB! > 0) specParts.add('${offer.dataGB}GB data');

    final tierMatch = _anchorEntry?.serviceTier != null && offer.tierBucket != null && _anchorEntry!.serviceTier == offer.tierBucket;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.cardBgRaised,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 32, height: 4, decoration: BoxDecoration(color: AppTokens.hairlineStrong, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  if (offer.tier != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: tierMatch ? AppTokens.gold.withValues(alpha: 0.15) : AppTokens.brandStart.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
                      ),
                      child: Text(
                        offer.tier!,
                        style: GoogleFonts.plusJakartaSans(
                          color: tierMatch ? AppTokens.goldLight : AppTokens.brandStart,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text('${offer.provider} \u00B7 ${offer.title}', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w600))),
                ]),
                if (specParts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(specParts.join(' \u00B7 '), style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
                ],
                const SizedBox(height: AppTokens.gapItem),
                Text('PRICE TIMELINE', style: GoogleFonts.plusJakartaSans(color: AppTokens.textFaint, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(border: Border.all(color: AppTokens.hairline), borderRadius: BorderRadius.circular(AppTokens.rInput)),
                  child: Column(children: [
                    if (isFlat)
                      _dtlRow('Month 1\u201312', _fmt.format(offer.promoPrice), true)
                    else ...[
                      _dtlRow('Month${pm > 1 ? 's' : ''} 1\u2013$pm', _fmt.format(offer.promoPrice), true),
                      Container(height: 1, color: AppTokens.hairline),
                      _dtlRow('Month${(12 - pm) > 1 ? 's' : ''} ${pm + 1}\u201312', _fmt.format(offer.regularPrice), false, muted: true),
                      Container(height: 1, color: AppTokens.hairline),
                      _dtlRow('First-year total', _fmt.format(firstYearTotal), true, gold: true),
                    ],
                    if (isFlat && pm < 12) ...[
                      Container(height: 1, color: AppTokens.hairline),
                      _dtlRow('First-year total', _fmt.format(firstYearTotal), true, gold: true),
                    ],
                  ]),
                ),
                const SizedBox(height: 12),
                if (anchorCost != null && !_anchorNotSure)
                  _dtlRow('Your current plan, same 12 months', _fmt.format(anchorCost * 12), false, muted: true),
                const SizedBox(height: AppTokens.gapItem),
                Row(children: [
                  Expanded(child: Text(offer.validUntil != null ? 'Ends ${_dateFmt.format(offer.validUntil!)} \u00B7 affiliate' : 'Ongoing \u00B7 affiliate', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11))),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: AppTokens.goldGradient, borderRadius: BorderRadius.circular(AppTokens.rInput)),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppTokens.rInput),
                          onTap: () => _openOfferUrl(context, offer.url),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Text('View offer', style: GoogleFonts.plusJakartaSans(color: AppTokens.screenBg, fontSize: 12.5, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dtlRow(String label, String amount, bool isPromo, {bool gold = false, bool muted = false}) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: isPromo ? AppTokens.success.withValues(alpha: 0.04) : Colors.transparent),
      child: Row(children: [
        Expanded(child: Text(label, style: GoogleFonts.plusJakartaSans(color: muted ? AppTokens.textMuted : AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w400))),
        Text(amount, style: GoogleFonts.spaceGrotesk(color: gold ? AppTokens.gold : muted ? AppTokens.textMuted : AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final SavingsOffer offer; final DateTime now;
  final AppEntry? anchor; final bool anchorNotSure; final VoidCallback onTap;
  const _OfferCard({required this.offer, required this.now, this.anchor, required this.anchorNotSure, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final daysLeft = offer.validUntil?.difference(now).inDays;
    final urgent = daysLeft != null && daysLeft <= 7;
    final isNew = offer.postedAt != null && now.difference(offer.postedAt!).inDays <= 7;
    final avg = offer.avgFirstYear;
    final userCost = anchor?.subscriptionCost;
    final userTier = anchor?.serviceTier;
    final tierMatch = userTier != null && offer.tierBucket != null && userTier == offer.tierBucket;
    final delta = userCost != null ? avg - userCost : null;
    final isFlat = offer.promoMonths <= 0 || offer.promoPrice == offer.regularPrice;

    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(AppTokens.padCard),
      decoration: BoxDecoration(color: AppTokens.cardBg, borderRadius: BorderRadius.circular(AppTokens.rInput), border: Border.all(color: AppTokens.hairline, width: 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(offer.provider, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700))),
          if (offer.tier != null || isNew) const SizedBox(width: 8),
          Flexible(child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (offer.tier != null) Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: tierMatch ? AppTokens.gold.withValues(alpha: 0.12) : AppTokens.brandStart.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppTokens.rSmallPill)), child: Text(offer.tier! + (tierMatch ? ' \u00B7 your tier' : ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(color: tierMatch ? AppTokens.goldLight : AppTokens.brandStart, fontSize: 11, fontWeight: FontWeight.w500)))),
            if (isNew) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppTokens.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppTokens.rSmallPill)), child: Text('New', style: GoogleFonts.plusJakartaSans(color: AppTokens.success, fontSize: 9, fontWeight: FontWeight.w600)))],
          ])),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(_fmt.format(avg), style: GoogleFonts.spaceGrotesk(color: AppTokens.textStrong, fontSize: 20, fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 4), Text('/mo avg first year', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
          const Spacer(),
          if (delta != null && !anchorNotSure)
            delta == 0
                ? Text('Same as yours', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11))
                : Text.rich(TextSpan(children: [
                    TextSpan(text: _fmt.format(delta.abs()), style: GoogleFonts.plusJakartaSans(color: AppTokens.gold, fontSize: 11, fontWeight: FontWeight.w700)),
                    TextSpan(text: delta < 0 ? ' less than yours' : ' more than yours', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
                  ])),
        ]),
        const SizedBox(height: 6),
        Text.rich(TextSpan(children: isFlat
            ? [
                TextSpan(text: _fmt.format(offer.regularPrice), style: GoogleFonts.plusJakartaSans(color: AppTokens.gold, fontSize: 11, fontWeight: FontWeight.w700)),
                TextSpan(text: ' flat \u00B7 no intro pricing', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
              ]
            : [
                TextSpan(text: _fmt.format(offer.promoPrice), style: GoogleFonts.plusJakartaSans(color: AppTokens.gold, fontSize: 11, fontWeight: FontWeight.w700)),
                TextSpan(text: ' for ', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
                TextSpan(text: '${offer.promoMonths} mo', style: GoogleFonts.plusJakartaSans(color: AppTokens.gold, fontSize: 11, fontWeight: FontWeight.w700)),
                TextSpan(text: ' \u00B7 then ', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
                TextSpan(text: '${_fmt.format(offer.regularPrice)}/mo', style: GoogleFonts.plusJakartaSans(color: AppTokens.gold, fontSize: 11, fontWeight: FontWeight.w700)),
              ])),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.only(top: 10), decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTokens.hairline))),
          child: Row(children: [
            Expanded(child: Text((isFlat || offer.validUntil == null) ? 'Ongoing \u00B7 affiliate' : 'Ends ${_dateFmt.format(offer.validUntil!)} \u00B7 affiliate', style: GoogleFonts.plusJakartaSans(color: urgent && !isFlat ? AppTokens.warning : AppTokens.textMuted, fontSize: 11, fontWeight: urgent && !isFlat ? FontWeight.w500 : FontWeight.w400))),
            const SizedBox(width: 8),
            SizedBox(height: 38, child: DecoratedBox(decoration: BoxDecoration(gradient: AppTokens.goldGradient, borderRadius: BorderRadius.circular(AppTokens.rInput)),
              child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(AppTokens.rInput),
                onTap: () { HapticFeedback.selectionClick(); _openOfferUrl(context, offer.url); },
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Text('View offer', style: GoogleFonts.plusJakartaSans(color: AppTokens.screenBg, fontSize: 12.5, fontWeight: FontWeight.w600))))),
            )),
          ]),
        ),
      ]),
    ));
  }
}
