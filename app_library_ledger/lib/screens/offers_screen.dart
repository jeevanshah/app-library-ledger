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
  bool _showAvgHint = true;
  bool _showBarHint = true;
  static const _hintAvgKey = 'offers_avg_hint_shown';
  static const _hintBarKey = 'offers_bar_hint_shown';

  @override
  void initState() {
    super.initState();
    _settings.offersEnabled.addListener(_onEnabledChanged);
    _loadSortMode();
    _loadHints();
    _loadNotSure();
    if (_settings.offersEnabled.value) {
      _fetch();
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
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

  Future<void> _loadHints() async {
    final prefs = await SharedPreferences.getInstance();
    _showAvgHint = !(prefs.getBool(_hintAvgKey) ?? false);
    _showBarHint = !(prefs.getBool(_hintBarKey) ?? false);
  }

  Future<void> _dismissAvgHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hintAvgKey, true);
    setState(() => _showAvgHint = false);
  }

  Future<void> _dismissBarHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hintBarKey, true);
    setState(() => _showBarHint = false);
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
      _loadAnchor();
      setState(() { _loading = false; });
    } catch (_) {
      setState(() { _loading = false; _fetchFailed = _allOffers.isEmpty; });
    }
  }

  Future<void> _refresh() async {
    try {
      final all = await OffersService().fetch(enabled: true, force: true);
      _allOffers = all;
      _loadAnchor();
      setState(() {});
    } catch (_) {}
  }

  void _loadAnchor() {
    final utils = widget.apps.where((a) => a.category == 'Utilities' && a.isActiveSubscription).toList();
    final kws = ['nbn','internet','broadband','mobile','sim','prepaid','tangerine','superloop','dodo','spintel','telstra','optus','vodafone','amaysim','belong','felix','kogan','boost','aldi','lebrara'];
    for (final kw in kws) {
      final m = utils.where((a) => a.name.toLowerCase().contains(kw)).firstOrNull;
      if (m != null) { _anchorEntry = m; return; }
    }
    if (utils.isNotEmpty) {
      utils.sort((a, b) => (b.subscriptionCost ?? 0).compareTo(a.subscriptionCost ?? 0));
      _anchorEntry = utils.first;
      return;
    }
    _anchorEntry = null;
  }

  Future<void> _setAnchorTier(String tier) async {
    if (_anchorEntry == null) return;
    final updated = AppEntry(
      id: _anchorEntry!.id, name: _anchorEntry!.name, appStoreLink: _anchorEntry!.appStoreLink,
      category: _anchorEntry!.category, packageName: _anchorEntry!.packageName,
      subscriptionCost: _anchorEntry!.subscriptionCost, billingCycle: _anchorEntry!.billingCycle,
      nextRenewalDate: _anchorEntry!.nextRenewalDate, isActiveSubscription: _anchorEntry!.isActiveSubscription,
      isPromotionalPrice: _anchorEntry!.isPromotionalPrice, regularPrice: _anchorEntry!.regularPrice,
      promotionEndsDate: _anchorEntry!.promotionEndsDate, serviceTier: tier,
      notes: _anchorEntry!.notes, createdAt: _anchorEntry!.createdAt,
    );
    await StorageService().saveApp(updated);
    widget.onSaveApp();
    setState(() => _anchorEntry = updated);
  }

  void _cycleSort() {
    setState(() { _sortMode = (_sortMode + 1) % 3; });
    SharedPreferences.getInstance().then((p) => p.setInt(_sortKey, _sortMode));
  }

  String get _sortLabel => switch (_sortMode) { 1 => 'Promo price', 2 => 'Ongoing price', _ => 'First-year avg' };

  List<SavingsOffer> get _filteredSorted {
    var list = _allOffers.toList();
    if (_segment == 'nbn') list = list.where((o) => o.serviceType == 'nbn').toList();
    else if (_segment == 'mobile') list = list.where((o) => o.serviceType == 'mobile').toList();
    else if (_segment == 'other') list = list.where((o) => o.serviceType != 'nbn' && o.serviceType != 'mobile').toList();
    if (_filterTier != null) list = list.where((o) => o.tier == _filterTier).toList();
    switch (_sortMode) {
      case 1: list.sort((a, b) => a.promoPrice.compareTo(b.promoPrice));
      case 2: list.sort((a, b) => a.regularPrice.compareTo(b.regularPrice));
      default: list.sort((a, b) => a.avgFirstYear.compareTo(b.avgFirstYear));
    }
    return list;
  }

  Set<String> get _availableTiers {
    var src = _allOffers;
    if (_segment != null) src = src.where((o) {
      if (_segment == 'nbn') return o.serviceType == 'nbn';
      if (_segment == 'mobile') return o.serviceType == 'mobile';
      return o.serviceType != 'nbn' && o.serviceType != 'mobile';
    }).toList();
    return src.where((o) => o.tier != null).map((o) => o.tier!).toSet();
  }

  bool get _hasOther => _allOffers.any((o) => o.serviceType != 'nbn' && o.serviceType != 'mobile');

  @override
  Widget build(BuildContext context) {
    if (!_settings.offersEnabled.value) return _buildOptIn();
    if (_loading && _allOffers.isEmpty) return const Center(child: CircularProgressIndicator(color: AppTokens.gold));
    if (_fetchFailed && _allOffers.isEmpty) return _buildError();
    return _buildPage();
  }

  Widget _buildOptIn() {
    return Center(
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80, decoration: BoxDecoration(color: AppTokens.fieldBg, shape: BoxShape.circle, border: Border.all(color: AppTokens.hairline)), child: const Icon(Icons.lock_rounded, color: AppTokens.gold, size: 36)),
        const SizedBox(height: 24),
        Text('See real savings offers matched to what you already pay', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text('Offers are downloaded anonymously. What you track never leaves your device. Links may earn us a commission.', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12, height: 1.5)),
        const SizedBox(height: 32),
        SizedBox(width: double.infinity, height: 54,
          child: DecoratedBox(decoration: BoxDecoration(gradient: AppTokens.brandGradient, borderRadius: BorderRadius.circular(16)),
            child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(16),
              onTap: () { HapticFeedback.mediumImpact(); _settings.setOffersEnabled(true); },
              child: Center(child: Text('Enable Offers', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))))))),
      ])),
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
    final offers = _filteredSorted;
    final maxAvg = offers.isNotEmpty ? offers.map((o) => o.avgFirstYear).reduce((a, b) => a > b ? a : b) : 1.0;
    final tiers = _availableTiers;
    return RefreshIndicator(
      color: AppTokens.gold, backgroundColor: AppTokens.cardBg, onRefresh: _refresh,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(22, 12, 22, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Offers', style: GoogleFonts.playfairDisplay(color: AppTokens.textStrong, fontSize: 28, fontWeight: FontWeight.w700))),
            Text('${offers.length} plans', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          Text("Fetched anonymously — what you track never leaves your device.", style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
          const SizedBox(height: 16),
          _buildSegmentControl(),
          const SizedBox(height: 12),
        ]))),
        if (_anchorEntry != null || !_anchorNotSure)
          SliverPersistentHeader(pinned: true, delegate: _AnchorDelegate(
            anchor: _anchorEntry, notSure: _anchorNotSure, onEdit: _showTierPicker,
          )),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (tiers.isNotEmpty) ...[SizedBox(height: 34, child: ListView(scrollDirection: Axis.horizontal, children: [
            _chip('All', null, _filterTier == null),
            for (final t in tiers) _chip(t, t, _filterTier == t),
          ])), const SizedBox(height: 8)],
          Row(children: [
            Expanded(child: _showAvgHint
              ? GestureDetector(onTap: _showAvgExplain, child: Text('Prices shown as first-year averages ⓘ', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)))
              : const SizedBox.shrink()),
            GestureDetector(onTap: _cycleSort, child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_sortLabel, style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
              const SizedBox(width: 2), const Icon(Icons.swap_vert_rounded, size: 14, color: AppTokens.textMuted),
              GestureDetector(onTap: _showAvgExplain, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.info_outline_rounded, size: 14, color: AppTokens.textFaint))),
            ])),
          ]),
          const SizedBox(height: 8),
        ]))),
        if (offers.isEmpty)
          SliverFillRemaining(child: Center(child: Text('No offers match your selection.', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 14))))
        else
          SliverList(delegate: SliverChildBuilderDelegate((_, i) {
            if (i == 0 && _showBarHint) return Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 6), child: GestureDetector(onTap: _dismissBarHint, child: Text('gold tick = what you pay now', style: GoogleFonts.plusJakartaSans(color: AppTokens.textFaint, fontSize: 10))));
            final idx = _showBarHint ? i - 1 : i;
            if (idx < 0 || idx >= offers.length) return null;
            return Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 8), child: _OfferCard(
              offer: offers[idx], now: DateTime.now(), maxAvg: maxAvg,
              anchor: _anchorEntry, anchorNotSure: _anchorNotSure,
              onTap: () => _showDetail(offers[idx]),
            ));
          }, childCount: offers.length + (_showBarHint ? 1 : 0))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 80), child: Column(children: [
          const SizedBox(height: 8),
          Text('NBN availability varies by address — check with the provider.', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPlaceholder, fontSize: 10.5)),
          const SizedBox(height: 4),
          Text('Prices verified at time of listing.', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPlaceholder, fontSize: 10.5)),
        ]))),
      ]),
    );
  }

  Widget _buildSegmentControl() {
    final segs = <String?>[null];
    if (_allOffers.any((o) => o.serviceType == 'nbn')) segs.add('nbn');
    if (_allOffers.any((o) => o.serviceType == 'mobile')) segs.add('mobile');
    if (_hasOther) segs.add('other');
    return Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: AppTokens.fieldBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTokens.hairline)),
      child: Row(children: segs.map((s) => Expanded(child: GestureDetector(
        onTap: () => setState(() { _segment = s; _filterTier = null; }),
        child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: _segment == s ? AppTokens.gold : Colors.transparent, borderRadius: BorderRadius.circular(7)),
          child: Text(s == 'nbn' ? 'NBN' : s == 'mobile' ? 'Mobile' : s == 'other' ? 'Other' : 'All', textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(color: _segment == s ? AppTokens.screenBg : AppTokens.textMuted, fontSize: 12.5, fontWeight: FontWeight.w500)),
        ),
      ))).toList()),
    );
  }

  Widget _chip(String label, String? tier, bool selected) {
    return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
      onTap: () => setState(() => _filterTier = selected ? null : tier),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: selected ? AppTokens.gold : Colors.transparent, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? AppTokens.gold : AppTokens.hairline)),
        child: Text(label, style: GoogleFonts.plusJakartaSans(color: selected ? AppTokens.screenBg : AppTokens.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    ));
  }

  void _showTierPicker() {
    if (_anchorEntry == null) return;
    final isNbn = _anchorEntry!.name.toLowerCase().contains('nbn') || _anchorEntry!.name.toLowerCase().contains('internet') || _anchorEntry!.name.toLowerCase().contains('broadband');
    showModalBottomSheet(context: context, backgroundColor: AppTokens.cardBg, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isNbn ? 'What speed are you on? (optional)' : 'How much data do you get now? (optional)', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in isNbn ? const ['25','50','100','Faster','Not sure'] : const ['<20GB','20–60GB','60GB+','Unlimited','Not sure'])
            GestureDetector(onTap: () { HapticFeedback.selectionClick(); if (t == 'Not sure') { _setNotSure(); } else { _setAnchorTier(t); } Navigator.pop(context); },
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: _anchorEntry?.serviceTier == t ? AppTokens.gold.withValues(alpha: 0.12) : AppTokens.fieldBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _anchorEntry?.serviceTier == t ? AppTokens.gold.withValues(alpha: 0.3) : AppTokens.hairline)),
                child: Text(t, style: GoogleFonts.plusJakartaSans(color: _anchorEntry?.serviceTier == t ? AppTokens.gold : AppTokens.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ]))),
    );
  }

  void _showAvgExplain() {
    _dismissAvgHint();
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
    if (offer.dataGB != null) specParts.add('${offer.dataGB}GB');

    showModalBottomSheet(context: context, backgroundColor: AppTokens.cardBgRaised, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 32, height: 4, decoration: BoxDecoration(color: AppTokens.hairlineStrong, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Row(children: [
          if (offer.tier != null) ...[Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppTokens.brandStart.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)), child: Text(offer.tier!, style: GoogleFonts.plusJakartaSans(color: AppTokens.brandStart, fontSize: 10.5, fontWeight: FontWeight.w600))), const SizedBox(width: 8)],
          Expanded(child: Text('${offer.provider} · ${offer.title}', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 6),
        if (specParts.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(specParts.join(' · '), style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12))),
        Text('PRICE TIMELINE', style: GoogleFonts.plusJakartaSans(color: AppTokens.textFaint, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Container(decoration: BoxDecoration(border: Border.all(color: AppTokens.hairline), borderRadius: BorderRadius.circular(10)), child: Column(children: [
          if (isFlat)
            _dtlRow('Month 1–12', _fmt.format(offer.promoPrice), true)
          else ...[
            _dtlRow('Month${pm > 1 ? 's' : ''} 1–$pm', _fmt.format(offer.promoPrice), true),
            _dtlRow('Month${(12-pm) > 1 ? 's' : ''} ${pm+1}–12', _fmt.format(offer.regularPrice), false, muted: true),
            Container(height: 1, color: AppTokens.hairline),
            _dtlRow('First-year total', _fmt.format(firstYearTotal), true, gold: true),
          ],
          if (isFlat && pm < 12) _dtlRow('First-year total', _fmt.format(firstYearTotal), true, gold: true),
        ])),
        const SizedBox(height: 12),
        if (anchorCost != null && !_anchorNotSure)
          _dtlRow('Your current plan, same 12 months', _fmt.format(anchorCost * 12), false, muted: true),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text('Ends ${_dateFmt.format(offer.validUntil)} · affiliate link', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 10.5))),
          const SizedBox(width: 12),
          SizedBox(height: 48, child: DecoratedBox(decoration: BoxDecoration(gradient: AppTokens.brandGradient, borderRadius: BorderRadius.circular(12)),
            child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(12),
              onTap: () => launchUrl(Uri.parse(offer.url), mode: LaunchMode.externalApplication),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), child: Text('View offer', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))))))),
        ]),
      ]))),
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

class _AnchorDelegate extends SliverPersistentHeaderDelegate {
  final AppEntry? anchor; final bool notSure; final VoidCallback onEdit;
  const _AnchorDelegate({required this.anchor, required this.notSure, required this.onEdit});
  @override double get minExtent => 48;
  @override double get maxExtent => 48;
  @override bool shouldRebuild(covariant _AnchorDelegate old) => anchor != old.anchor || notSure != old.notSure;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: AppTokens.screenBg, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppTokens.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTokens.gold.withValues(alpha: 0.5))),
        child: Row(children: [
          Expanded(child: anchor != null
            ? Text.rich(TextSpan(children: [
                TextSpan(text: 'You pay ', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12)),
                TextSpan(text: _fmt.format(anchor!.subscriptionCost ?? 0), style: GoogleFonts.spaceGrotesk(color: AppTokens.gold, fontSize: 12, fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
                TextSpan(text: '/mo', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12)),
                if (anchor!.serviceTier != null) TextSpan(text: ' · ${anchor!.serviceTier}', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12)),
              ]))
            : Text('Add your internet/mobile bill to compare', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12)),
          ),
          GestureDetector(onTap: onEdit, child: Padding(padding: const EdgeInsets.all(8), child: Text('Edit', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)))),
        ]),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final SavingsOffer offer; final DateTime now; final double maxAvg;
  final AppEntry? anchor; final bool anchorNotSure; final VoidCallback onTap;
  const _OfferCard({required this.offer, required this.now, required this.maxAvg, this.anchor, required this.anchorNotSure, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final daysLeft = offer.validUntil.difference(now).inDays;
    final urgent = daysLeft <= 7;
    final isNew = offer.postedAt != null && now.difference(offer.postedAt!).inDays <= 7;
    final avg = offer.avgFirstYear;
    final barWidth = (avg / maxAvg).clamp(0.15, 1.0);
    final userCost = anchor?.subscriptionCost;
    final userTier = anchor?.serviceTier;
    final tierMatch = userTier != null && offer.tier != null && userTier == offer.tier;
    final delta = userCost != null ? avg - userCost : null;

    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTokens.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTokens.hairline, width: 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${offer.provider} · ${offer.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 13, fontWeight: FontWeight.w500))),
          if (offer.tier != null) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppTokens.brandStart.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Text(offer.tier! + (tierMatch ? ' · yours' : ''), style: GoogleFonts.plusJakartaSans(color: AppTokens.brandStart, fontSize: 10.5, fontWeight: FontWeight.w500)))],
          if (isNew) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: AppTokens.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), child: Text('New', style: GoogleFonts.plusJakartaSans(color: AppTokens.success, fontSize: 9, fontWeight: FontWeight.w600)))],
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(_fmt.format(avg), style: GoogleFonts.spaceGrotesk(color: AppTokens.textStrong, fontSize: 20, fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 4), Text('/mo avg first year', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 10.5)),
          const Spacer(),
          if (delta != null && !anchorNotSure) Text(delta == 0 ? '\$0.00/mo vs yours' : '${delta < 0 ? '-' : '+'}${_fmt.format(delta.abs())}/mo vs yours', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        SizedBox(height: 12, child: Stack(children: [
          Container(width: double.infinity, height: 4, decoration: BoxDecoration(color: const Color(0xFF2E2E3A), borderRadius: BorderRadius.circular(2))),
          Positioned.fill(child: FractionallySizedBox(widthFactor: barWidth, child: Container(height: 4, decoration: BoxDecoration(color: const Color(0xFF2E2E3A), borderRadius: BorderRadius.circular(2))))),
          if (userCost != null && !anchorNotSure)
            Positioned(left: ((userCost / maxAvg).clamp(0.0, 1.0) * (MediaQuery.of(context).size.width - 68)).clamp(8.0, (MediaQuery.of(context).size.width - 68) - 4.0), top: 0, child: Container(width: 2, height: 12, decoration: BoxDecoration(color: AppTokens.gold, borderRadius: BorderRadius.circular(1)))),
        ])),
        const SizedBox(height: 6),
        Text(offer.promoMonths <= 0 || offer.promoPrice == offer.regularPrice ? '${_fmt.format(offer.regularPrice)} flat · no intro pricing' : '${_fmt.format(offer.promoPrice)} for ${offer.promoMonths} mo · then ${_fmt.format(offer.regularPrice)}/mo', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 11)),
        Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.only(top: 8), decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTokens.hairline))),
          child: Row(children: [
            Expanded(child: Text('Ends ${_dateFmt.format(offer.validUntil)} · affiliate', style: GoogleFonts.plusJakartaSans(color: urgent ? AppTokens.warning : AppTokens.textMuted, fontSize: 10.5, fontWeight: urgent ? FontWeight.w500 : FontWeight.w400))),
            const SizedBox(width: 8),
            GestureDetector(onTap: () { HapticFeedback.selectionClick(); launchUrl(Uri.parse(offer.url), mode: LaunchMode.externalApplication); },
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(border: Border.all(color: AppTokens.hairlineStrong), borderRadius: BorderRadius.circular(8)),
                child: Text('View offer', style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 11, fontWeight: FontWeight.w500))),
            ),
          ]),
        ),
      ]),
    ));
  }
}