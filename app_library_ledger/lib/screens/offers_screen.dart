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
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _loadAnchor([List<AppEntry>? apps]) {
    final utils = (apps ?? widget.apps).where((a) => a.category == 'Utilities' && a.isActiveSubscription).toList();
    // 1. Explicit serviceType match for current segment
    if (_segment == 'nbn' || _segment == 'mobile') {
      final explicit = utils.where((a) => a.serviceType == _segment).firstOrNull;
      if (explicit != null) { _anchorEntry = explicit; return; }
    }
    // 2. Segment-aware keyword matching
    const nbnKws = ['nbn','internet','broadband','tangerine','superloop','dodo','belong','flip','exetel','iinet','tpg'];
    const mobileKws = ['mobile','sim','prepaid','spintel','telstra','optus','vodafone','amaysim','felix','kogan','boost','aldi','lebrara'];
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
    setState(() { _anchorEntry = updated; _filterTier = tier; });
  }

  void _cycleSort() {
    setState(() { _sortMode = (_sortMode + 1) % 3; });
    SharedPreferences.getInstance().then((p) => p.setInt(_sortKey, _sortMode));
  }

  String get _sortLabel => switch (_sortMode) { 1 => 'Promo price', 2 => 'Ongoing price', _ => 'First-year avg' };

  Set<String> get _availableTiers {
    var src = _allOffers;
    if (_segment == 'nbn') src = src.where((o) => o.serviceType == 'nbn').toList();
    else if (_segment == 'mobile') src = src.where((o) => o.serviceType == 'mobile').toList();
    return src.where((o) => o.tier != null).map((o) => o.tier!).toSet();
  }

  bool get _showTierPicker {
    if (_anchorEntry == null) return false;
    if (_anchorNotSure) return false;
    if (_anchorEntry!.serviceTier != null) return false;
    if (_segment != 'nbn' && _segment != 'mobile') return false;
    return true;
  }

  List<String> get _tierPickerOptions {
    if (_segment == 'nbn') return const ['25', '50', '100', 'Faster'];
    if (_segment == 'mobile') return const ['<20GB', '20–60GB', '60GB+', 'Unlimited'];
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
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(22, 12, 22, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Offers', style: GoogleFonts.playfairDisplay(color: AppTokens.textStrong, fontSize: 28, fontWeight: FontWeight.w700))),
            Text('$totalOffers plans', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          Text("Fetched anonymously — what you track never leaves your device.", style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
          const SizedBox(height: 16),
          _buildSegmentControl(),
          const SizedBox(height: 12),
          _buildAnchorBar(),
          if (_showTierPicker) ...[const SizedBox(height: 10), _buildTierPickerCard(), const SizedBox(height: 10)],
        ]))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    }).where((o) => o.tier == tier).toList();
    switch (_sortMode) {
      case 1: offers.sort((a, b) => a.promoPrice.compareTo(b.promoPrice));
      case 2: offers.sort((a, b) => a.regularPrice.compareTo(b.regularPrice));
      default: offers.sort((a, b) => a.avgFirstYear.compareTo(b.avgFirstYear));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 80),
      itemCount: offers.isEmpty ? 1 : offers.length + 1,
      itemBuilder: (_, i) {
        if (offers.isEmpty) {
          return Center(child: Padding(padding: const EdgeInsets.only(top: 40), child: Text('No offers at $tier', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 13))));
        }
        if (i == offers.length) {
          return Padding(padding: const EdgeInsets.only(top: 16), child: Column(children: [
            Text('NBN availability varies by address — check with the provider.', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPlaceholder, fontSize: 10.5)),
            const SizedBox(height: 4),
            Text('Prices verified at time of listing. Always confirm with the provider.', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPlaceholder, fontSize: 10.5)),
          ]));
        }
        return Padding(padding: const EdgeInsets.only(bottom: 14), child: _OfferCard(
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
        onTap: () => setState(() { _segment = _segment == s ? null : s; _filterTier = _availableTiers.isNotEmpty ? _availableTiers.first : null; _loadAnchor(); WidgetsBinding.instance.addPostFrameCallback((_) => _pageCtrl.jumpToPage(0)); }),
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
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: AppTokens.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTokens.gold.withValues(alpha: 0.5))),
      child: Row(children: [
        Expanded(child: hasEntry
          ? Text.rich(TextSpan(children: [
              TextSpan(text: 'You pay ', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12)),
              TextSpan(text: _fmt.format(_anchorEntry!.subscriptionCost ?? 0), style: GoogleFonts.spaceGrotesk(color: AppTokens.gold, fontSize: 12, fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
              TextSpan(text: '/mo', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12)),
              if (hasTier) TextSpan(text: ' · ${_anchorEntry!.serviceTier}', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12)),
            ]))
          : hasUtilities
            ? Text('Tap to pick your plan', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12))
            : Text(_segment == 'mobile' ? 'Add your mobile plan' : 'Add your internet plan', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12)),
        ),
        GestureDetector(
          onTap: () => hasEntry ? _showAnchorConfig() : hasUtilities ? _showAnchorPicker() : _navigateToAdd(),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(border: Border.all(color: AppTokens.hairlineStrong), borderRadius: BorderRadius.circular(8)),
            child: Text(hasEntry ? 'Edit' : hasUtilities ? 'Pick' : 'Add', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
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
        Text('Tap an existing subscription to tag it as $label', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12)),
        const SizedBox(height: 16),
        if (entries.isNotEmpty) SizedBox(
          height: entries.length * 56.0 + 8 > 360 ? 360 : entries.length * 56.0 + 8,
          child: ListView(children: entries.map((a) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(a.name, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
            subtitle: Text('${_fmt.format(a.subscriptionCost ?? 0)}/mo · ${a.category}', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
            trailing: a.serviceType != null ? Text(a.serviceType == 'nbn' ? 'NBN' : 'Mobile', style: GoogleFonts.plusJakartaSans(color: AppTokens.textFaint, fontSize: 11)) : const Icon(Icons.chevron_right_rounded, color: AppTokens.textMuted, size: 20),
            onTap: a.serviceType != null ? null : () { Navigator.pop(context); _tagAsAnchor(a); },
          )).toList()),
        ),
        if (entries.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('No active subscriptions yet.', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12))),
        const Divider(color: AppTokens.hairlineStrong),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.add_rounded, color: AppTokens.gold, size: 22),
          title: Text('Add new subscription', style: GoogleFonts.plusJakartaSans(color: AppTokens.gold, fontSize: 13, fontWeight: FontWeight.w600)),
          onTap: () { Navigator.pop(context); _navigateToAdd(); },
        ),
      ]))),
    );
  }

  Future<void> _navigateToAdd() async {
    final cats = await StorageService().getCategories();
    if (!mounted) return;
    final segment = _segment ?? 'nbn';
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => AddAppScreen(
      categories: cats,
      prefillServiceType: segment,
    )));
    if (result == true) {
      widget.onSaveApp();
      final freshApps = await StorageService().getApps();
      if (mounted) { _loadAnchor(freshApps); setState(() {}); }
    }
  }

  Future<void> _tagAsAnchor(AppEntry entry) async {
    final updated = entry.copyWith(serviceType: _segment);
    await StorageService().saveApp(updated);
    widget.onSaveApp();
    final freshApps = await StorageService().getApps();
    if (mounted) { _loadAnchor(freshApps); setState(() {}); }
  }

  void _showAnchorConfig() {
    if (_anchorEntry == null) return;
    if (_segment != 'nbn' && _segment != 'mobile') return;
    final options = _tierPickerOptions;
    final entries = widget.apps.where((a) => a.isActiveSubscription).toList();
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: AppTokens.cardBg, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 32, height: 4, decoration: BoxDecoration(color: AppTokens.hairlineStrong, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text('Configure your plan', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w700))),
          Text('${_fmt.format(_anchorEntry!.subscriptionCost ?? 0)}/mo', style: GoogleFonts.spaceGrotesk(color: AppTokens.gold, fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 16),
        Text(_tierPickerQuestion + ' (optional)', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in options)
            GestureDetector(onTap: () { HapticFeedback.selectionClick(); _setAnchorTier(t); Navigator.pop(context); },
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: _anchorEntry?.serviceTier == t ? AppTokens.gold.withValues(alpha: 0.12) : AppTokens.fieldBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: _anchorEntry?.serviceTier == t ? AppTokens.gold.withValues(alpha: 0.3) : AppTokens.hairline)),
                child: Text(t, style: GoogleFonts.plusJakartaSans(color: _anchorEntry?.serviceTier == t ? AppTokens.gold : AppTokens.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          GestureDetector(onTap: () { HapticFeedback.selectionClick(); _setNotSure(); Navigator.pop(context); },
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7), child: Text('Not sure', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12)))),
        ]),
        const SizedBox(height: 14),
        const Divider(color: AppTokens.hairlineStrong),
        const SizedBox(height: 10),
        Text('Switch to a different plan?', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (entries.isNotEmpty) SizedBox(
          height: entries.length * 52.0 + 8 > 320 ? 320 : entries.length * 52.0 + 8,
          child: ListView(children: entries.map((a) => ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text(a.name, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
            subtitle: Text('${_fmt.format(a.subscriptionCost ?? 0)}/mo \u00B7 ${a.category}', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
            trailing: a.id == _anchorEntry!.id ? Text('Current', style: GoogleFonts.plusJakartaSans(color: AppTokens.gold, fontSize: 11, fontWeight: FontWeight.w600)) : a.serviceType != null ? Text(a.serviceType == 'nbn' ? 'NBN' : 'Mobile', style: GoogleFonts.plusJakartaSans(color: AppTokens.textFaint, fontSize: 11)) : null,
            onTap: a.id == _anchorEntry!.id ? null : () { Navigator.pop(context); _tagAsAnchor(a); },
          )).toList()),
        ),
        if (entries.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('No active subscriptions yet.', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12))),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.add_rounded, color: AppTokens.gold, size: 20),
          title: Text('Add new subscription', style: GoogleFonts.plusJakartaSans(color: AppTokens.gold, fontSize: 12, fontWeight: FontWeight.w600)),
          onTap: () { Navigator.pop(context); _navigateToAdd(); },
        ),
      ]))),
    );
  }

  Widget _buildTierPickerCard() {
    final options = _tierPickerOptions;
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTokens.fieldBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTokens.hairlineStrong)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_tierPickerQuestion + ' (optional)', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in options)
            GestureDetector(onTap: () => _setAnchorTier(t),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppTokens.cardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTokens.hairlineStrong)),
                child: Text(t, style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ),
          GestureDetector(onTap: _setNotSure,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text('Not sure', style: GoogleFonts.plusJakartaSans(color: AppTokens.textFaint, fontSize: 12)))),
        ]),
      ]),
    );
  }

  Widget _buildFilterRow(Set<String> tiers) {
    final myTier = _anchorEntry?.serviceTier;
    final tierList = tiers.toList();
    return SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, children: [
      if (myTier != null && tiers.contains(myTier))
        Padding(padding: const EdgeInsets.only(right: 6), child: GestureDetector(
          onTap: () { _pageCtrl.animateToPage(tierList.indexOf(myTier), duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic); },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: _filterTier == myTier ? AppTokens.gold : Colors.transparent, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTokens.gold, width: _filterTier == myTier ? 1 : 1)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTokens.gold, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(myTier, style: GoogleFonts.plusJakartaSans(color: _filterTier == myTier ? AppTokens.screenBg : AppTokens.gold, fontSize: 11.5, fontWeight: FontWeight.w500)),
            ]),
          ),
        )),
      for (var i = 0; i < tierList.length; i++)
        Padding(padding: const EdgeInsets.only(right: 6), child: _chip(tierList[i], i)),
    ]));
  }

  Widget _chip(String label, int pageIndex) {
    final selected = _filterTier == label;
    return GestureDetector(
      onTap: () { _pageCtrl.animateToPage(pageIndex, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic); },
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: selected ? AppTokens.gold : Colors.transparent, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? AppTokens.gold : AppTokens.hairlineStrong)),
        child: Text(label, style: GoogleFonts.plusJakartaSans(color: selected ? AppTokens.screenBg : AppTokens.textMuted, fontSize: 11.5, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildSortRow() {
    return Row(children: [
      Expanded(child: GestureDetector(onTap: _showAvgExplain, child: Text('Prices shown as first-year averages \u24D8', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)))),
      GestureDetector(onTap: _cycleSort, child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Sort: ${_sortLabel.toLowerCase()}', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
        const SizedBox(width: 2), const Icon(Icons.swap_vert_rounded, size: 14, color: AppTokens.textMuted),
      ])),
    ]);
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

    final tierMatch = _anchorEntry?.serviceTier != null && offer.tier != null && _anchorEntry!.serviceTier == offer.tier;

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
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        offer.tier!,
                        style: GoogleFonts.plusJakartaSans(
                          color: tierMatch ? AppTokens.goldLight : AppTokens.brandStart,
                          fontSize: 10.5,
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
                const SizedBox(height: 14),
                Text('PRICE TIMELINE', style: GoogleFonts.plusJakartaSans(color: AppTokens.textFaint, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(border: Border.all(color: AppTokens.hairline), borderRadius: BorderRadius.circular(10)),
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
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Text('Ends ${_dateFmt.format(offer.validUntil)} \u00B7 affiliate', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 10.5))),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: AppTokens.goldGradient, borderRadius: BorderRadius.circular(12)),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => launchUrl(Uri.parse(offer.url), mode: LaunchMode.externalApplication),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Text('View offer', style: GoogleFonts.plusJakartaSans(color: AppTokens.screenBg, fontSize: 13, fontWeight: FontWeight.w700)),
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
    final daysLeft = offer.validUntil.difference(now).inDays;
    final urgent = daysLeft <= 7;
    final isNew = offer.postedAt != null && now.difference(offer.postedAt!).inDays <= 7;
    final avg = offer.avgFirstYear;
    final userCost = anchor?.subscriptionCost;
    final userTier = anchor?.serviceTier;
    final tierMatch = userTier != null && offer.tier != null && userTier == offer.tier;
    final delta = userCost != null ? avg - userCost : null;
    final isFlat = offer.promoMonths <= 0 || offer.promoPrice == offer.regularPrice;

    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTokens.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTokens.hairline, width: 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${offer.provider} \u00B7 ${offer.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
          if (offer.tier != null || isNew) const SizedBox(width: 8),
          Flexible(child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (offer.tier != null) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: tierMatch ? AppTokens.gold.withValues(alpha: 0.12) : AppTokens.brandStart.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Text(offer.tier! + (tierMatch ? ' \u00B7 your tier' : ''), style: GoogleFonts.plusJakartaSans(color: tierMatch ? AppTokens.goldLight : AppTokens.brandStart, fontSize: 10.5, fontWeight: FontWeight.w500))),
            if (isNew) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: AppTokens.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)), child: Text('New', style: GoogleFonts.plusJakartaSans(color: AppTokens.success, fontSize: 9, fontWeight: FontWeight.w600)))],
          ])),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(_fmt.format(avg), style: GoogleFonts.spaceGrotesk(color: AppTokens.textStrong, fontSize: 20, fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 4), Text('/mo avg first year', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
          const Spacer(),
          if (delta != null && !anchorNotSure) Text(delta == 0 ? '\$0.00 vs yours' : '${delta < 0 ? '\u2212' : '+'}${_fmt.format(delta.abs())}/mo vs yours', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        Text(isFlat ? _fmt.format(offer.regularPrice) + ' flat \u00B7 no intro pricing' : '${_fmt.format(offer.promoPrice)} for ${offer.promoMonths} mo \u00B7 then ${_fmt.format(offer.regularPrice)}/mo', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.only(top: 10), decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTokens.hairline))),
          child: Row(children: [
            Expanded(child: Text(isFlat ? 'Ongoing \u00B7 affiliate' : 'Ends ${_dateFmt.format(offer.validUntil)} \u00B7 affiliate', style: GoogleFonts.plusJakartaSans(color: urgent && !isFlat ? AppTokens.warning : AppTokens.textMuted, fontSize: 11, fontWeight: urgent && !isFlat ? FontWeight.w500 : FontWeight.w400))),
            const SizedBox(width: 8),
            SizedBox(height: 38, child: DecoratedBox(decoration: BoxDecoration(gradient: AppTokens.goldGradient, borderRadius: BorderRadius.circular(10)),
              child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(10),
                onTap: () { HapticFeedback.selectionClick(); launchUrl(Uri.parse(offer.url), mode: LaunchMode.externalApplication); },
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Text('View offer', style: GoogleFonts.plusJakartaSans(color: AppTokens.screenBg, fontSize: 12, fontWeight: FontWeight.w600))))),
            )),
          ]),
        ),
      ]),
    ));
  }
}
