import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/app_model.dart';
import '../models/catalog_entry.dart';
import '../models/category_model.dart';
import '../models/spend_ledger_entry.dart';
import '../services/app_icon_service.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_theme.dart';
import 'discovery_screen.dart';

class AddAppScreen extends StatefulWidget {
  final List<Category> categories;
  final AppEntry? appToEdit;
  final bool focusBilling;
  final String? prefillServiceType; // "nbn" or "mobile" from Offers tab
  const AddAppScreen({
    required this.categories,
    this.appToEdit,
    this.focusBilling = false,
    this.prefillServiceType,
    super.key,
  });
  @override
  State<AddAppScreen> createState() => _AddAppScreenState();
}

class _AddAppScreenState extends State<AddAppScreen>
    with TickerProviderStateMixin {
  static const uncategorizedName = 'Uncategorized';
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _regularCtrl = TextEditingController();

  late List<Category> _categories;
  String? _category;
  bool _isSub = true;
  String _cycle = 'monthly';
  DateTime? _renewal;
  bool _isPromo = false;
  DateTime? _promoEnds;
  bool _userTouchedDate = false;
  bool _expanded = false;
  bool _useCustomCost = false;
  CatalogEntry? _matchedCatalog;

  bool _nameError = false;
  bool _costError = false;
  bool _renewalError = false;

  late final AnimationController _staggerCtrl;
  late final AnimationController _highlightCtrl;
  final _scrollKey = GlobalKey();
  final _billingKey = GlobalKey();
  final _nameKey = GlobalKey();
  final _renewalKey = GlobalKey();
  List<CatalogEntry> _quickEntries = [];
  String? _serviceType; // "nbn", "mobile", or null
  String? _serviceTier; // user's speed/data tier

  // Search-first entry
  List<CatalogEntry> _searchResults = [];
  Timer? _searchDebounce;
  List<AppEntry> _existingApps = [];

  // Promo-first branching (manual/no-catalog-match path only)
  bool? _manualPromoChoice; // null = unanswered
  bool _promoCostUnsure = false;
  bool _promoEndsUnsure = false;
  bool _regularPriceUnsure = false;
  bool _promoPriceCustom = false;
  bool _regularPriceCustom = false;
  static const _commonPrices = [9.99, 14.99, 19.99, 29.99, 39.99, 49.99];

  // OCR bill scan
  bool _scanningBill = false;
  final Set<String> _ocrFilledFields = {}; // 'cost' | 'renewal' | 'name'

  bool get _isManualPricingPath => _matchedCatalog == null || _useCustomCost;

  double? get _parsedCost => double.tryParse(_costCtrl.text.trim());

  CatalogEntry? _findMatchingCatalogEntry() {
    final name = _nameCtrl.text.trim();
    final catalog = CatalogService();
    for (final e in (catalog.appScanEntries + catalog.webManualEntries)) {
      if (e.packageName != null &&
          widget.appToEdit?.packageName != null &&
          e.packageName == widget.appToEdit?.packageName)
        return e;
      if (e.name.toLowerCase() == name.toLowerCase()) return e;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _categories = List<Category>.from(widget.categories);
    String? initialCategory = _categories.isNotEmpty
        ? _categories.first.name
        : null;

    final a = widget.appToEdit;
    if (a != null) {
      _nameCtrl.text = a.name;
      initialCategory = a.category;
      _notesCtrl.text = a.notes ?? '';
      _isSub = a.isActiveSubscription;
      if (a.subscriptionCost != null) {
        _costCtrl.text = a.subscriptionCost!.toStringAsFixed(2);
      }
      _cycle = a.billingCycle ?? 'monthly';
      _renewal = a.nextRenewalDate;
      _userTouchedDate = a.nextRenewalDate != null;
      _isPromo = a.isPromotionalPrice;
      if (a.regularPrice != null) {
        _regularCtrl.text = a.regularPrice!.toStringAsFixed(2);
      }
      _promoEnds = a.promotionEndsDate;
      _serviceType = a.serviceType;
      _serviceTier = a.serviceTier;
      if (widget.prefillServiceType != null) {
        _serviceType = widget.prefillServiceType;
      }
      if ((a.isPromotionalPrice || (a.notes != null && a.notes!.isNotEmpty))) {
        _expanded = true;
      }
      // If saved cost doesn't match any tier, start in custom mode
      final match = _findMatchingCatalogEntry();
      _matchedCatalog = match;
      if (a.subscriptionCost != null) {
        final costStr = a.subscriptionCost!.toStringAsFixed(2);
        final matchesTier =
            match != null &&
            match.pricingTiers.any(
              (t) => t.monthlyPrice.toStringAsFixed(2) == costStr,
            );
        if (!matchesTier) _useCustomCost = true;
      }
      // Editing an entry already on the manual pricing path: the promo
      // question is already answered, and "not sure yet" back-fills from
      // whichever fields are null so re-opening doesn't show a false error.
      if (match == null || _useCustomCost) {
        _manualPromoChoice = a.isPromotionalPrice;
        if (a.isPromotionalPrice) {
          _promoEndsUnsure = a.promotionEndsDate == null;
          _regularPriceUnsure = a.regularPrice == null;
        }
      }
    } else if (widget.prefillServiceType == null) {
      // New, unassisted entry: default to a calm "Uncategorized" bucket
      // instead of whatever happens to be first in the seeded list.
      var unc = _findCategory(uncategorizedName);
      if (unc == null) {
        unc = Category(name: uncategorizedName, color: Colors.grey);
        _categories.add(unc);
        StorageService().saveCategory(unc);
      }
      initialCategory = uncategorizedName;
    }

    _category = _resolveCategory(initialCategory);

    if (widget.prefillServiceType != null && widget.appToEdit == null) {
      _serviceType = widget.prefillServiceType;
      _isSub = true;
      _category = 'Utilities';
      if (_findCategory('Utilities') == null) {
        _categories.add(Category(name: 'Utilities', color: AppTokens.categoryColor('Utilities'), isCustom: false));
      }
    }

    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _highlightCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _staggerCtrl.forward();

    if (widget.focusBilling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBilling();
      });
    }

    // Update matched catalog when name changes (for tier chips)
    _nameCtrl.addListener(() {
      final match = _findMatchingCatalogEntry();
      if (match != _matchedCatalog) {
        setState(() {
          _matchedCatalog = match;
          _useCustomCost = false;
        });
      }
      _ocrFilledFields.remove('name');
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _searchResults = _searchCatalog(_nameCtrl.text.trim()));
      });
    });

    _loadQuickEntries();
  }

  List<CatalogEntry> _searchCatalog(String query) {
    if (query.isEmpty) return const [];
    final q = query.toLowerCase();
    final catalog = CatalogService();
    final tracked = _existingApps;
    final startsWith = <CatalogEntry>[];
    final contains = <CatalogEntry>[];
    for (final e in (catalog.appScanEntries + catalog.webManualEntries)) {
      if (e.isTrackedIn(tracked)) continue;
      final name = e.name.toLowerCase();
      if (name.startsWith(q)) {
        startsWith.add(e);
      } else if (name.contains(q)) {
        contains.add(e);
      }
    }
    return [...startsWith, ...contains].take(6).toList();
  }

  Future<void> _selectSearchResult(CatalogEntry e) async {
    await _fillFromCatalog(e);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _scrollToBilling();
  }

  // ── OCR bill scan ──────────────────────────────────────────────
  // On-device only (google_mlkit_text_recognition) — the photo and any
  // recognized text never leave the phone. Every guessed field is
  // clearly marked ("Scanned — check this") and stays fully editable;
  // this can only pre-fill, never silently commit wrong data.

  Future<void> _scanBill() async {
    if (_scanningBill) return;
    HapticFeedback.selectionClick();
    XFile? photo;
    try {
      photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
    } catch (_) {
      return;
    }
    if (photo == null || !mounted) return;

    var cancelled = false;
    setState(() => _scanningBill = true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppTokens.cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.rCard),
            ),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTokens.gold),
                ),
                const SizedBox(width: 16),
                Text(
                  'Reading your bill…',
                  style: GoogleFonts.plusJakartaSans(color: AppTokens.textPrimary, fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.pop(dialogCtx);
                },
                child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );

    String recognizedText = '';
    try {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(InputImage.fromFilePath(photo.path));
      await recognizer.close();
      recognizedText = result.text;
    } catch (_) {
      recognizedText = '';
    }

    if (!mounted) return;
    setState(() => _scanningBill = false);
    if (cancelled) return;
    if (Navigator.of(context).canPop()) Navigator.pop(context);

    if (recognizedText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't read any text from that photo — try again or fill it in manually.")),
      );
      return;
    }
    await _applyOcrResult(recognizedText);
  }

  Future<void> _applyOcrResult(String rawText) async {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    var anyGuess = false;

    // Name — catalog fuzzy match only; never guessed from free text (a
    // "prominent" line is often the biller's own brand, not the service).
    final nameMatch = _guessCatalogName(lines);
    if (nameMatch != null) {
      await _fillFromCatalog(nameMatch);
      if (!mounted) return;
      _ocrFilledFields.add('name');
      anyGuess = true;
    }

    // Price — overrides whatever generic tier default _fillFromCatalog
    // may have just set, since this is the actual scanned figure.
    final priceGuess = _guessPrice(lines);
    if (priceGuess != null) {
      setState(() {
        _costCtrl.text = priceGuess.toStringAsFixed(2);
        _useCustomCost = true;
        _promoPriceCustom = true;
        _ocrFilledFields.add('cost');
      });
      anyGuess = true;
    }

    // Date — only a future date is trusted as a renewal-date guess.
    final dateGuess = _guessDate(lines);
    if (dateGuess != null) {
      setState(() {
        _renewal = dateGuess;
        _userTouchedDate = true;
        _ocrFilledFields.add('renewal');
      });
      anyGuess = true;
    }

    if (!mounted) return;
    if (!anyGuess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't confidently read the details — fill them in below.")),
      );
    } else {
      HapticFeedback.mediumImpact();
      _scrollToBilling();
    }
  }

  CatalogEntry? _guessCatalogName(List<String> lines) {
    final catalog = CatalogService();
    final entries = catalog.appScanEntries + catalog.webManualEntries;
    for (final line in lines) {
      final lower = line.toLowerCase();
      for (final e in entries) {
        if (e.name.length >= 3 && lower.contains(e.name.toLowerCase())) return e;
      }
    }
    return null;
  }

  double? _guessPrice(List<String> lines) {
    final priceRegex = RegExp(r'\$?\s?(\d{1,4}(?:,\d{3})*\.\d{2})');
    const preferKeywords = [
      'total', 'amount due', 'charged', 'monthly', 'plan cost', 'you paid',
    ];
    const avoidKeywords = ['subtotal', 'tax', 'gst', 'vat'];

    double? preferred;
    double? fallback;
    for (final line in lines) {
      final lower = line.toLowerCase();
      final match = priceRegex.firstMatch(line);
      if (match == null) continue;
      final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
      if (value == null) continue;
      if (avoidKeywords.any(lower.contains)) continue;
      if (preferred == null && preferKeywords.any(lower.contains)) preferred = value;
      if (fallback == null || value > fallback) fallback = value;
    }
    return preferred ?? fallback;
  }

  static const _ocrMonths = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  DateTime? _guessDate(List<String> lines) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final numericRegex = RegExp(r'\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})\b');
    final namedMonthRegex = RegExp(
      r'\b(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{4})\b',
      caseSensitive: false,
    );

    final candidates = <DateTime>[];
    for (final line in lines) {
      for (final m in numericRegex.allMatches(line)) {
        final day = int.tryParse(m.group(1)!);
        final month = int.tryParse(m.group(2)!);
        var year = int.tryParse(m.group(3)!);
        if (day == null || month == null || year == null) continue;
        if (year < 100) year += 2000;
        if (month < 1 || month > 12 || day < 1 || day > 31) continue;
        try {
          candidates.add(DateTime(year, month, day));
        } catch (_) {}
      }
      for (final m in namedMonthRegex.allMatches(line)) {
        final day = int.tryParse(m.group(1)!);
        final month = _ocrMonths[m.group(2)!.toLowerCase()];
        final year = int.tryParse(m.group(3)!);
        if (day == null || month == null || year == null) continue;
        try {
          candidates.add(DateTime(year, month, day));
        } catch (_) {}
      }
    }

    final future = candidates.where((d) => d.isAfter(today)).toList()..sort();
    return future.isEmpty ? null : future.first;
  }

  Future<void> _loadQuickEntries() async {
    final catalog = CatalogService();
    await catalog.loadCatalog();
    final tracked = await StorageService().getApps();
    if (!mounted) return;
    _existingApps = tracked;
    final entries = <CatalogEntry>[];
    for (final e in (catalog.appScanEntries + catalog.webManualEntries)) {
      if (e.pricingTiers.isEmpty || e.isTrackedIn(tracked)) continue;
      entries.add(e);
      if (entries.length >= 10) break;
    }
    setState(() => _quickEntries = entries);
  }

  void _scrollToBilling() {
    if (!_highlightCtrl.isAnimating && !_highlightCtrl.isCompleted) {
      _highlightCtrl.repeat(reverse: true);
    }
    Future.delayed(const Duration(milliseconds: 1600), () {
      _highlightCtrl.stop();
      _highlightCtrl.reset();
    });
    Scrollable.ensureVisible(
      _billingKey.currentContext!,
      alignment: 0.15,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _costCtrl.dispose();
    _regularCtrl.dispose();
    _staggerCtrl.dispose();
    _highlightCtrl.dispose();
    super.dispose();
  }

  Category? _findCategory(String? name) {
    if (name == null) return null;
    for (final c in _categories) {
      if (c.name == name) return c;
    }
    return null;
  }

  String? _resolveCategory(String? preferred) {
    if (_findCategory(preferred) != null) return preferred;
    final unc = _findCategory(uncategorizedName);
    if (unc != null) return unc.name;
    return _categories.isNotEmpty ? _categories.first.name : null;
  }

  Future<void> _selectCategoryByName(String name) async {
    var cat = _findCategory(name);
    if (cat == null) {
      cat = Category(name: name, color: AppTokens.categoryColor(name));
      await StorageService().saveCategory(cat);
      if (!mounted) return;
      setState(() => _categories.add(cat!));
    }
    if (!mounted) return;
    setState(() => _category = cat!.name);
  }

  Future<void> _openCategoryPicker() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _CategoryPickerSheet(categories: _categories, selected: _category),
    );
    if (result == null) return;
    final refreshed = await StorageService().getCategories();
    if (!mounted) return;
    setState(() {
      _categories = refreshed;
      _category = _resolveCategory(result);
    });
  }

  Future<String> _ensureCategorySelected() async {
    if (_category != null) return _category!;
    var unc = _findCategory(uncategorizedName);
    if (unc == null) {
      unc = Category(name: uncategorizedName, color: Colors.grey);
      await StorageService().saveCategory(unc);
      if (mounted) setState(() => _categories.add(unc!));
    }
    if (mounted) setState(() => _category = unc!.name);
    return unc.name;
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = current != null
        ? DateTime(current.year, current.month, current.day)
        : today;
    final firstDate = initialDate.isBefore(today) ? initialDate : today;
    final lastDate = initialDate.isAfter(DateTime(2099))
        ? initialDate
        : DateTime(2099);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
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
    if (!mounted) return;
    if (picked != null) {
      _userTouchedDate = true;
      onPicked(picked);
    }
  }

  bool _validate() {
    final nameEmpty = _nameCtrl.text.trim().isEmpty;
    bool costMissing = false;
    bool dateMissing = false;
    if (_isSub) {
      costMissing = _parsedCost == null && !_promoCostUnsure;
      dateMissing = _renewal == null;
    }
    setState(() {
      _nameError = nameEmpty;
      _costError = costMissing;
      _renewalError = dateMissing;
    });
    final ok = !nameEmpty && !costMissing && !dateMissing;
    if (!ok) {
      final target = nameEmpty ? _nameKey
          : costMissing ? _billingKey
          : _renewalKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (target.currentContext != null) {
          Scrollable.ensureVisible(target.currentContext!, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });
    }
    return ok;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final categoryName = await _ensureCategorySelected();
    if (!mounted) return;

    final cost = _parsedCost;
    final regular = double.tryParse(_regularCtrl.text.trim());
    final name = _nameCtrl.text.trim();

    final app = AppEntry(
      id: widget.appToEdit?.id,
      name: name,
      appStoreLink: _deriveAppStoreLink(),
      category: categoryName,
      packageName:
          widget.appToEdit?.packageName ?? _matchedCatalog?.packageName,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      isActiveSubscription: _isSub,
      subscriptionCost: _isSub ? cost : null,
      billingCycle: _isSub ? _cycle : null,
      nextRenewalDate: _isSub ? _renewal : null,
      isPromotionalPrice: _isSub && _isPromo,
      regularPrice: (_isSub && _isPromo) ? regular : null,
      promotionEndsDate: (_isSub && _isPromo) ? _promoEnds : null,
      serviceType: _serviceType,
      serviceTier: _serviceTier,
      createdAt: widget.appToEdit?.createdAt,
    );

    final oldCost = widget.appToEdit?.subscriptionCost;
    if (widget.appToEdit != null &&
        _isSub &&
        oldCost != null &&
        cost != null &&
        (oldCost - cost).abs() > 0.001) {
      await StorageService().appendLedgerEntry(
        SpendLedgerEntry(
          entryId: app.id,
          appName: app.name,
          date: DateTime.now(),
          amount: cost,
          previousAmount: oldCost,
          kind: LedgerEventKind.priceChanged,
          category: app.category,
        ),
      );
    }

    if (widget.appToEdit != null) {
      await NotificationService().cancelReminders(widget.appToEdit!.id);
    }
    await StorageService().saveApp(app);
    final allApps = await StorageService().getApps();
    await NotificationService().rescheduleAll(allApps);
    if (!mounted) return;
    HapticFeedback.lightImpact();
    Navigator.pop(context, true);
  }

  String _deriveAppStoreLink() {
    final pkg = widget.appToEdit?.packageName ?? _matchedCatalog?.packageName;
    if (pkg != null) {
      return 'https://play.google.com/store/apps/details?id=$pkg';
    }
    final name = _nameCtrl.text.trim();
    return 'https://apps.apple.com/app/${name.toLowerCase().replaceAll(' ', '-')}';
  }

  Future<void> _confirmDelete() async {
    final a = widget.appToEdit;
    if (a == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rCard),
        ),
        title: Text(
          'Delete subscription?',
          style: GoogleFonts.spaceGrotesk(
            color: AppTokens.textStrong,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Remove "${a.name}"? This can\'t be undone.',
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTokens.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await StorageService().deleteApp(a.id);
    await NotificationService().cancelReminders(a.id);
    final remaining = await StorageService().getApps();
    await NotificationService().rescheduleAll(remaining);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _onCycleChanged(String cycle) {
    HapticFeedback.selectionClick();
    setState(() {
      _cycle = cycle;
      if (!_userTouchedDate) {
        _renewal = defaultRenewalDate(cycle);
      }
    });
  }

  Future<void> _fillFromCatalog(CatalogEntry catEntry) async {
    HapticFeedback.selectionClick();
    await _selectCategoryByName(catEntry.category);
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = catEntry.name;
      _matchedCatalog = catEntry;
      _isSub = true;
      _serviceType = catEntry.serviceType;
      if (catEntry.pricingTiers.isNotEmpty) {
        _costCtrl.text = catEntry.pricingTiers.first.monthlyPrice
            .toStringAsFixed(2);
      }
      if (!_userTouchedDate) {
        _renewal = defaultRenewalDate(_cycle);
      }
      _nameError = false;
      _costError = false;
      _renewalError = false;
    });
  }

  Widget _labeled(
    String label,
    Widget field, {
    String? helper,
    bool error = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: AppTokens.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        field,
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              helper,
              style: GoogleFonts.plusJakartaSans(
                color: error ? AppTokens.danger : AppTokens.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  InputDecoration _decoration({
    String? hint,
    String? prefixText,
    bool error = false,
  }) {
    final borderColor = error ? AppTokens.danger : AppTokens.hairline;
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(
        color: AppTokens.textPlaceholder,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      prefixText: prefixText,
      prefixStyle: GoogleFonts.spaceGrotesk(
        color: AppTokens.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: AppTokens.fieldBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.rInput),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.rInput),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.rInput),
        borderSide: BorderSide(
          color: error ? AppTokens.danger : AppTokens.brandEnd,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    String? hint,
    String? prefixText,
    TextInputType? keyboardType,
    bool error = false,
    ValueChanged<String>? onChanged,
    int minLines = 1,
    int maxLines = 1,
    TextStyle? style,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      cursorColor: AppTokens.brandEnd,
      style:
          style ??
          GoogleFonts.plusJakartaSans(
            color: AppTokens.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
      decoration: _decoration(hint: hint, prefixText: prefixText, error: error),
    );
  }

  Widget _switchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: AppTokens.brandEnd,
            inactiveThumbColor: AppTokens.textFaint,
            inactiveTrackColor: AppTokens.cardBgRaised,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _dateField({
    required DateTime? date,
    required String placeholder,
    required VoidCallback onTap,
    IconData icon = Icons.calendar_today_rounded,
    bool error = false,
  }) {
    final text = date == null
        ? placeholder
        : DateFormat('MMM d, yyyy').format(date);
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.rInput),
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(AppTokens.rInput),
          border: Border.all(
            color: error ? AppTokens.danger : AppTokens.hairline,
            width: error ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTokens.textFaint),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.plusJakartaSans(
                  color: date == null
                      ? AppTokens.textPlaceholder
                      : AppTokens.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppTokens.textFaint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryField() {
    final cat = _findCategory(_category);
    return _labeled(
      'Category (optional)',
      InkWell(
        borderRadius: BorderRadius.circular(AppTokens.rInput),
        onTap: _openCategoryPicker,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppTokens.fieldBg,
            borderRadius: BorderRadius.circular(AppTokens.rInput),
            border: Border.all(color: AppTokens.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: cat?.color ?? AppTokens.textFaint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cat?.name ?? 'Select a category',
                  style: GoogleFonts.plusJakartaSans(
                    color: cat != null
                        ? AppTokens.textPrimary
                        : AppTokens.textPlaceholder,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppTokens.textFaint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceTypePicker() {
    final prefill = widget.prefillServiceType;
    if (prefill != null) {
      return _labeled(
        'Plan type',
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: AppTokens.brandGradient,
              borderRadius: BorderRadius.circular(AppTokens.rInput),
            ),
            child: Text(
              prefill == 'nbn' ? 'NBN' : 'Mobile',
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Set from Offers tab',
            style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12.5),
          ),
        ]),
      );
    }
    return _labeled(
      'Plan type (optional)',
      Container(
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(AppTokens.rInput),
          border: Border.all(color: AppTokens.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _serviceType = _serviceType == 'nbn' ? null : 'nbn'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: _serviceType == 'nbn' ? AppTokens.brandGradient : null,
                    borderRadius: BorderRadius.circular(AppTokens.rInput - 3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'NBN',
                    style: GoogleFonts.plusJakartaSans(
                      color: _serviceType == 'nbn' ? Colors.white : AppTokens.textFaint,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _serviceType = _serviceType == 'mobile' ? null : 'mobile'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: _serviceType == 'mobile' ? AppTokens.brandGradient : null,
                    borderRadius: BorderRadius.circular(AppTokens.rInput - 3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Mobile',
                    style: GoogleFonts.plusJakartaSans(
                      color: _serviceType == 'mobile' ? Colors.white : AppTokens.textFaint,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      helper: 'Helps match offers to your plan',
    );
  }

  Widget _cyclePill() {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTokens.fieldBg,
        borderRadius: BorderRadius.circular(AppTokens.rInput),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _onCycleChanged('monthly'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  gradient: _cycle == 'monthly'
                      ? AppTokens.brandGradient
                      : null,
                  borderRadius: BorderRadius.circular(AppTokens.rInput - 3),
                ),
                alignment: Alignment.center,
                height: double.infinity,
                child: Text(
                  'Monthly',
                  style: GoogleFonts.plusJakartaSans(
                    color: _cycle == 'monthly'
                        ? Colors.white
                        : AppTokens.textFaint,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _onCycleChanged('yearly'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  gradient: _cycle == 'yearly' ? AppTokens.brandGradient : null,
                  borderRadius: BorderRadius.circular(AppTokens.rInput - 3),
                ),
                alignment: Alignment.center,
                height: double.infinity,
                child: Text(
                  'Yearly',
                  style: GoogleFonts.plusJakartaSans(
                    color: _cycle == 'yearly'
                        ? Colors.white
                        : AppTokens.textFaint,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Promo-first branching (manual pricing path) ──────────────────

  Widget _promoQuestionCard() {
    Widget option(String label, bool value) {
      final sel = _manualPromoChoice == value;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _manualPromoChoice = value;
              _isPromo = value;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: sel ? AppTokens.brandGradient : null,
              color: sel ? null : AppTokens.fieldBg,
              borderRadius: BorderRadius.circular(AppTokens.rInput),
              border: Border.all(color: sel ? Colors.transparent : AppTokens.hairline),
            ),
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: sel ? Colors.white : AppTokens.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return _labeled(
      'Is this on a promo price?',
      Row(children: [option('No', false), const SizedBox(width: 10), option('Yes', true)]),
    );
  }

  Widget _notSureChip(VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Text(
          'Not sure yet',
          style: GoogleFonts.plusJakartaSans(
            color: AppTokens.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _priceChipField({
    required String label,
    required TextEditingController controller,
    required bool useCustom,
    required ValueChanged<bool> onUseCustomChanged,
    bool allowUnsure = false,
    bool unsure = false,
    VoidCallback? onUnsureToggle,
    String? ocrFieldKey,
    bool error = false,
    String? requiredHelper,
  }) {
    if (unsure) {
      return _labeled(
        label,
        GestureDetector(
          onTap: onUnsureToggle,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppTokens.fieldBg,
              borderRadius: BorderRadius.circular(AppTokens.rInput),
              border: Border.all(color: AppTokens.hairline),
            ),
            child: Row(
              children: [
                Text(
                  "Not sure yet — tap to add",
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPlaceholder,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final ocrGuessed = ocrFieldKey != null && _ocrFilledFields.contains(ocrFieldKey);
    return _labeled(
      label,
      useCustom
          ? _textField(
              controller: controller,
              hint: '0.00',
              prefixText: '\$ ',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              onChanged: (_) => _ocrFilledFields.remove(ocrFieldKey),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._commonPrices.map((p) {
                  final str = p.toStringAsFixed(2);
                  final sel = controller.text == str;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        controller.text = str;
                        _ocrFilledFields.remove(ocrFieldKey);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: sel ? AppTokens.gold.withValues(alpha: 0.12) : AppTokens.fieldBg,
                        borderRadius: BorderRadius.circular(AppTokens.rPill),
                        border: Border.all(
                          color: sel ? AppTokens.gold.withValues(alpha: 0.3) : AppTokens.hairline,
                        ),
                      ),
                      child: Text(
                        '\$$str',
                        style: GoogleFonts.spaceGrotesk(
                          color: sel ? AppTokens.gold : AppTokens.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      controller.text = '';
                      onUseCustomChanged(true);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTokens.fieldBg,
                      borderRadius: BorderRadius.circular(AppTokens.rPill),
                      border: Border.all(color: AppTokens.hairline),
                    ),
                    child: Text(
                      'Custom',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (allowUnsure && onUnsureToggle != null) _notSureChip(onUnsureToggle),
              ],
            ),
      helper: ocrGuessed
          ? 'Scanned — check this'
          : (error ? requiredHelper : null),
      error: error,
    );
  }

  Widget _promoDateField({
    required String label,
    required String helper,
    required DateTime? date,
    required IconData icon,
    required bool unsure,
    required ValueChanged<DateTime> onPicked,
    required VoidCallback onUnsureToggle,
    String? ocrFieldKey,
  }) {
    final ocrGuessed = ocrFieldKey != null && _ocrFilledFields.contains(ocrFieldKey);
    if (unsure) {
      return _labeled(
        label,
        GestureDetector(
          onTap: onUnsureToggle,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppTokens.fieldBg,
              borderRadius: BorderRadius.circular(AppTokens.rInput),
              border: Border.all(color: AppTokens.hairline),
            ),
            child: Text(
              'Not sure yet — tap to add',
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textPlaceholder,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        helper: helper,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labeled(
          label,
          _dateField(
            date: date,
            placeholder: 'Select date',
            icon: icon,
            onTap: () => _pickDate(
              current: date,
              onPicked: (d) {
                _ocrFilledFields.remove(ocrFieldKey);
                onPicked(d);
              },
            ),
          ),
          helper: ocrGuessed ? 'Scanned — check this' : helper,
          error: false,
        ),
        _notSureChip(onUnsureToggle),
      ],
    );
  }

  Widget _costCycleRow() {
    // Never mutate _matchedCatalog in build — computed by listener + init
    final match = _matchedCatalog;
    final hasTiers =
        match != null && match.pricingTiers.isNotEmpty && !_useCustomCost;

    if (hasTiers) {
      final tiers = match!.pricingTiers;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labeled(
            'Cost',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...List.generate(tiers.length, (i) {
                  final t = tiers[i];
                  final sel =
                      _costCtrl.text == t.monthlyPrice.toStringAsFixed(2);
                  return GestureDetector(
                    onTap: () => setState(
                      () => _costCtrl.text = t.monthlyPrice.toStringAsFixed(2),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppTokens.gold.withValues(alpha: 0.12)
                            : AppTokens.fieldBg,
                        borderRadius: BorderRadius.circular(AppTokens.rPill),
                        border: Border.all(
                          color: sel
                              ? AppTokens.gold.withValues(alpha: 0.3)
                              : AppTokens.hairline,
                        ),
                      ),
                      child: Text(
                        '${t.tierName} · \$${t.monthlyPrice.toStringAsFixed(2)}',
                        style: GoogleFonts.spaceGrotesk(
                          color: sel ? AppTokens.gold : AppTokens.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: () => setState(() {
                    _costCtrl.text = '';
                    _useCustomCost = true;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.fieldBg,
                      borderRadius: BorderRadius.circular(AppTokens.rPill),
                      border: Border.all(color: AppTokens.hairline),
                    ),
                    child: Text(
                      'Custom',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _labeled('Billing cycle', _cyclePill()),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _labeled(
            'Cost',
            _textField(
              controller: _costCtrl,
              hint: '0.00',
              prefixText: '\$ ',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              error: _costError,
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              onChanged: (_) {
                if (_costError) setState(() => _costError = false);
              },
            ),
            helper: _costError ? 'Cost is required' : null,
            error: _costError,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(width: 130, child: _labeled('Billing cycle', _cyclePill())),
      ],
    );
  }

  // B4 — icon fallback helper
  Widget _iconForCatalog(CatalogEntry entry, {double size = 44}) {
    return FutureBuilder<ImageProvider?>(
      future: AppIconService().providerFor(
        packageName: entry.packageName,
        catalogId: entry.id,
      ),
      builder: (_, snap) {
        final provider = snap.data;
        if (provider != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: provider!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          );
        }
        final catColor = AppTokens.categoryColor(entry.category);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [catColor, catColor.withValues(alpha: 0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              entry.name[0].toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Search-first entry (replaces the plain "App Name" field in add mode) ──

  Widget _searchSection() {
    final hasQuery = _nameCtrl.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.padContent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(key: _nameKey, child: _searchField()),
          if (_nameError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(
                'Name is required',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.danger,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: 14),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
            crossFadeState: hasQuery
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _searchResultsList(),
            secondChild: _suggestedStrip(),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    final matched = _matchedCatalog;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTokens.fieldBg,
        borderRadius: BorderRadius.circular(AppTokens.rInput),
        border: Border.all(
          color: _nameError ? AppTokens.danger : AppTokens.hairline,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: matched != null
                  ? _iconForCatalog(matched, size: 28)
                  : const Icon(
                      Icons.search_rounded,
                      key: ValueKey('search-icon'),
                      color: AppTokens.textFaint,
                      size: 22,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              cursorColor: AppTokens.brandEnd,
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: "Search 60+ services — try 'Netflix' or 'gym'",
                hintStyle: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPlaceholder,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onChanged: (_) {
                if (_nameError) setState(() => _nameError = false);
              },
            ),
          ),
          if (matched != null)
            TweenAnimationBuilder<double>(
              key: ValueKey(matched.id),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 350),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppTokens.success,
                size: 20,
              ),
            )
          else if (_nameCtrl.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _nameCtrl.clear();
              },
              child: const Icon(
                Icons.close_rounded,
                color: AppTokens.textFaint,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchResultsList() {
    if (_searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          "No match in our catalog — that's fine, just fill in the details below.",
          style: GoogleFonts.plusJakartaSans(
            color: AppTokens.textMuted,
            fontSize: 12.5,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final e in _searchResults) _searchResultTile(e),
      ],
    );
  }

  Widget _searchResultTile(CatalogEntry e) {
    final priceMin = e.pricingTiers.isNotEmpty
        ? e.pricingTiers.first.monthlyPrice
        : null;
    return GestureDetector(
      onTap: () => _selectSearchResult(e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(AppTokens.rInput),
          border: Border.all(color: AppTokens.hairline),
        ),
        child: Row(
          children: [
            _iconForCatalog(e, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    e.category,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            if (priceMin != null)
              Text(
                'from \$${priceMin.toStringAsFixed(2)}',
                style: GoogleFonts.spaceGrotesk(
                  color: AppTokens.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _entryPointLink({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTokens.gold),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.gold,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _goScanPhone() async {
    HapticFeedback.selectionClick();
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const DiscoveryScreen(fromOnboarding: false)),
    );
    if (result == true && mounted) Navigator.pop(context, true);
  }

  // Empty-query state: suggested catalog entries + alternate entry points
  Widget _suggestedStrip() {
    final quickEntries = _quickEntries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.padContent),
          child: Row(
            children: [
              Text(
                'SUGGESTED',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textFaint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Opacity(
                opacity: _scanningBill ? 0.5 : 1,
                child: _entryPointLink(
                  icon: Icons.receipt_long_rounded,
                  label: 'Scan a bill',
                  onTap: _scanBill,
                ),
              ),
              const SizedBox(width: 4),
              _entryPointLink(
                icon: Icons.wifi_tethering_rounded,
                label: 'Scan my phone',
                onTap: _goScanPhone,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.padContent,
            ),
            itemCount: quickEntries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 11),
            itemBuilder: (_, i) {
              final e = quickEntries[i];
              final priceMin = e.pricingTiers.isNotEmpty
                  ? e.pricingTiers.first.monthlyPrice
                  : 0.0;
              return GestureDetector(
                onTap: () => _selectSearchResult(e),
                child: Container(
                  width: 92,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTokens.fieldBg,
                    borderRadius: BorderRadius.circular(AppTokens.rInput),
                    border: Border.all(color: AppTokens.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _iconForCatalog(e, size: 44),
                      const Spacer(),
                      Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'from \$${priceMin.toStringAsFixed(2)}',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTokens.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _header(bool isEdit) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.padHeader,
        vertical: 14,
      ),
      child: Row(
        children: [
          _iconBtn(
            Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                isEdit ? 'Edit subscription' : 'Add subscription',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                  color: AppTokens.textStrong,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (isEdit)
            _iconBtn(
              Icons.delete_outline_rounded,
              danger: true,
              onTap: _confirmDelete,
            )
          else
            const SizedBox(width: 42),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, {VoidCallback? onTap, bool danger = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTokens.fieldBg,
          borderRadius: BorderRadius.circular(AppTokens.rIconBtn),
          border: Border.all(
            color: danger
                ? AppTokens.danger.withValues(alpha: 0.4)
                : AppTokens.hairline,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: danger ? AppTokens.danger : AppTokens.textPrimary,
        ),
      ),
    );
  }

  Widget _saveBar(bool isEdit) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.padContent),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTokens.screenBg.withValues(alpha: 0), AppTokens.screenBg],
        ),
        border: const Border(top: BorderSide(color: AppTokens.hairline)),
      ),
      child: PrimaryButton(
        label: isEdit ? 'Save changes' : 'Save subscription',
        onPressed: _save,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.appToEdit != null;

    return Scaffold(
      backgroundColor: AppTokens.screenBg,
      body: Column(
        children: [
          SafeArea(bottom: false, child: _header(isEdit)),
          Expanded(
            child: ListView(
              key: _scrollKey,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (!isEdit) _searchSection(),
                if (!isEdit) const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.padContent,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isEdit) ...[
                        Container(key: _nameKey, child: _labeled(
                          'App Name',
                          _textField(
                            controller: _nameCtrl,
                            hint: 'e.g. Netflix',
                            error: _nameError,
                            onChanged: (_) {
                              if (_nameError) setState(() => _nameError = false);
                            },
                          ),
                          helper: _nameError ? 'Name is required' : null,
                          error: _nameError,
                        )),
                        const SizedBox(height: 16),
                      ],
                      _categoryField(),
                      const SizedBox(height: 16),
                      _switchRow(
                        title: 'Paid subscription',
                        subtitle: 'Track cost & renewals',
                        value: _isSub,
                        onChanged: (v) => setState(() => _isSub = v),
                      ),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 260),
                        sizeCurve: Curves.easeOutCubic,
                        crossFadeState: _isSub
                            ? CrossFadeState.showFirst
                            : CrossFadeState.showSecond,
                        firstChild: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            if (!_isManualPricingPath) ...[
                              // Catalog-tier path: pick a tier, optional
                              // collapsed promo toggle — unchanged.
                              Container(
                                key: _billingKey,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    AppTokens.rInput,
                                  ),
                                ),
                                child: AnimatedBuilder(
                                  animation: _highlightCtrl,
                                  builder: (_, child) {
                                    final glow = _highlightCtrl.value * 0.12;
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: AppTokens.gold.withValues(
                                          alpha: glow,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          AppTokens.rInput + 4,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(10),
                                      child: child,
                                    );
                                  },
                                  child: _costCycleRow(),
                                ),
                              ),
                              if (widget.prefillServiceType != null) ...[
                                const SizedBox(height: 16),
                                _serviceTypePicker(),
                                const SizedBox(height: 16),
                              ],
                              Container(key: _renewalKey, child: _labeled(
                                'Next renewal date',
                                _dateField(
                                  date: _renewal,
                                  placeholder: 'Select date',
                                  error: _renewalError,
                                  onTap: () => _pickDate(
                                    current: _renewal,
                                    onPicked: (d) => setState(() {
                                      _renewal = d;
                                      _renewalError = false;
                                    }),
                                  ),
                                ),
                                helper: _renewalError
                                    ? 'Renewal date is required'
                                    : null,
                                error: _renewalError,
                              )),
                              const SizedBox(height: 12),
                              // C4 — Progressive disclosure
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _expanded = !_expanded),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _expanded
                                            ? Icons.expand_less_rounded
                                            : Icons.expand_more_rounded,
                                        color: AppTokens.textMuted,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Got a promo price? Don\'t miss when it ends',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppTokens.textMuted,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedCrossFade(
                                duration: const Duration(milliseconds: 260),
                                sizeCurve: Curves.easeOutCubic,
                                crossFadeState: _expanded
                                    ? CrossFadeState.showFirst
                                    : CrossFadeState.showSecond,
                                firstChild: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 16),
                                    _switchRow(
                                      title: 'Promotional price',
                                      subtitle: 'Discounted rate for a limited time',
                                      value: _isPromo,
                                      onChanged: (v) =>
                                          setState(() => _isPromo = v),
                                    ),
                                    AnimatedCrossFade(
                                      duration: const Duration(milliseconds: 260),
                                      sizeCurve: Curves.easeOutCubic,
                                      crossFadeState: _isPromo
                                          ? CrossFadeState.showFirst
                                          : CrossFadeState.showSecond,
                                      firstChild: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 16),
                                          _labeled(
                                            'Regular price',
                                            _textField(
                                              controller: _regularCtrl,
                                              hint: '0.00',
                                              prefixText: '\$ ',
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              style: GoogleFonts.spaceGrotesk(
                                                color: AppTokens.textPrimary,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                            helper: 'Price after the promo ends.',
                                          ),
                                          const SizedBox(height: 16),
                                          _labeled(
                                            'Promotion end date',
                                            _dateField(
                                              date: _promoEnds,
                                              placeholder: 'Select date',
                                              icon: Icons.timer_off_rounded,
                                              onTap: () => _pickDate(
                                                current: _promoEnds,
                                                onPicked: (d) => setState(
                                                  () => _promoEnds = d,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      secondChild: const SizedBox(
                                        width: double.infinity,
                                      ),
                                    ),
                                  ],
                                ),
                                secondChild: const SizedBox(
                                  width: double.infinity,
                                ),
                              ),
                            ] else ...[
                              // Manual/no-catalog-match path: ask promo
                              // status first, branch the rest of the form.
                              _promoQuestionCard(),
                              if (_manualPromoChoice != null) ...[
                                const SizedBox(height: 16),
                                if (_manualPromoChoice == false) ...[
                                  // No — fast path, stays minimal.
                                  Container(
                                    key: _billingKey,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _priceChipField(
                                            label: 'Cost',
                                            controller: _costCtrl,
                                            useCustom: _promoPriceCustom,
                                            onUseCustomChanged: (v) =>
                                                setState(() => _promoPriceCustom = v),
                                            error: _costError,
                                            requiredHelper: 'Cost is required',
                                            ocrFieldKey: 'cost',
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        SizedBox(width: 130, child: _labeled('Billing cycle', _cyclePill())),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Container(key: _renewalKey, child: _labeled(
                                    'Next renewal date',
                                    _dateField(
                                      date: _renewal,
                                      placeholder: 'Select date',
                                      error: _renewalError,
                                      onTap: () => _pickDate(
                                        current: _renewal,
                                        onPicked: (d) => setState(() {
                                          _renewal = d;
                                          _renewalError = false;
                                        }),
                                      ),
                                    ),
                                    helper: _renewalError
                                        ? 'Renewal date is required'
                                        : null,
                                    error: _renewalError,
                                  )),
                                ] else ...[
                                  // Yes — promo price, then the two dates
                                  // (kept visually and semantically distinct),
                                  // then price after promo.
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: _priceChipField(
                                          label: 'Promo price',
                                          controller: _costCtrl,
                                          useCustom: _promoPriceCustom,
                                          onUseCustomChanged: (v) =>
                                              setState(() => _promoPriceCustom = v),
                                          allowUnsure: true,
                                          unsure: _promoCostUnsure,
                                          onUnsureToggle: () => setState(() {
                                            _promoCostUnsure = !_promoCostUnsure;
                                            if (_promoCostUnsure) _costCtrl.clear();
                                          }),
                                          error: _costError,
                                          requiredHelper: 'Cost is required',
                                          ocrFieldKey: 'cost',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(width: 130, child: _labeled('Billing cycle', _cyclePill())),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Container(key: _renewalKey, child: _labeled(
                                    'Next bill date',
                                    _dateField(
                                      date: _renewal,
                                      placeholder: 'Select date',
                                      error: _renewalError,
                                      onTap: () => _pickDate(
                                        current: _renewal,
                                        onPicked: (d) => setState(() {
                                          _renewal = d;
                                          _renewalError = false;
                                          _ocrFilledFields.remove('renewal');
                                        }),
                                      ),
                                    ),
                                    helper: _renewalError
                                        ? 'Renewal date is required'
                                        : (_ocrFilledFields.contains('renewal')
                                            ? 'Scanned — check this'
                                            : 'Recurs every billing cycle'),
                                    error: _renewalError,
                                  )),
                                  const SizedBox(height: 16),
                                  _promoDateField(
                                    label: 'Promo ends on',
                                    helper: 'One-off — the date your discount stops',
                                    date: _promoEnds,
                                    icon: Icons.timer_off_rounded,
                                    unsure: _promoEndsUnsure,
                                    onPicked: (d) => setState(() => _promoEnds = d),
                                    onUnsureToggle: () => setState(() {
                                      _promoEndsUnsure = !_promoEndsUnsure;
                                      if (_promoEndsUnsure) _promoEnds = null;
                                    }),
                                  ),
                                  const SizedBox(height: 16),
                                  _priceChipField(
                                    label: 'Price after promo',
                                    controller: _regularCtrl,
                                    useCustom: _regularPriceCustom,
                                    onUseCustomChanged: (v) =>
                                        setState(() => _regularPriceCustom = v),
                                    allowUnsure: true,
                                    unsure: _regularPriceUnsure,
                                    onUnsureToggle: () => setState(() {
                                      _regularPriceUnsure = !_regularPriceUnsure;
                                      if (_regularPriceUnsure) _regularCtrl.clear();
                                    }),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                _labeled(
                                  'Notes',
                                  _textField(
                                    controller: _notesCtrl,
                                    hint: 'e.g. Family plan, shared with 3 people',
                                    minLines: 3,
                                    maxLines: 5,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                        secondChild: const SizedBox(width: double.infinity),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(top: false, child: _saveBar(isEdit)),
        ],
      ),
    );
  }
}

// ── Category picker bottom sheet ───────────────────────────────────────

class _CategoryPickerSheet extends StatefulWidget {
  final List<Category> categories;
  final String? selected;
  const _CategoryPickerSheet({
    required this.categories,
    required this.selected,
  });
  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  bool _adding = false, _saving = false;
  final _nameCtrl = TextEditingController();
  Color _color = AppTokens.brandEnd;
  static const _swatches = [
    AppTokens.brandEnd,
    AppTokens.brandStart,
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFFA855F7),
    Color(0xFF3B82F6),
    Color(0xFFEAB308),
    Color(0xFF14B8A6),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final cat = Category(name: name, color: _color, isCustom: true);
    await StorageService().saveCategory(cat);
    if (!mounted) return;
    Navigator.pop(context, cat.name);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 14,
          bottom: 14 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTokens.hairlineStrong,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Category',
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textStrong,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (!_adding) ...[
              if (widget.categories.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No categories yet — add one below.',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontSize: 13.5,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.42,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.categories.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final c = widget.categories[i];
                      final sel = c.name == widget.selected;
                      return InkWell(
                        borderRadius: BorderRadius.circular(AppTokens.rInput),
                        onTap: () => Navigator.pop(context, c.name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: sel ? AppTokens.fieldBg : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              AppTokens.rInput,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: c.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  c.name,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTokens.textPrimary,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (sel)
                                const Icon(
                                  Icons.check_rounded,
                                  color: AppTokens.brandEnd,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 6),
              InkWell(
                borderRadius: BorderRadius.circular(AppTokens.rInput),
                onTap: () => setState(() => _adding = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.add_circle_outline_rounded,
                        color: AppTokens.brandEnd,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '+ New category',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.brandEnd,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textPrimary,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Category name',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPlaceholder,
                  ),
                  filled: true,
                  fillColor: AppTokens.fieldBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.rInput),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _swatches)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _color = c);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == c
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _adding = false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.textMuted,
                        side: const BorderSide(color: AppTokens.hairline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.rInput),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _create,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTokens.brandEnd,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.rInput),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Add'),
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
}
