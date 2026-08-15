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
  final _searchFocus = FocusNode();
  bool _searchFocused = false;

  late List<Category> _categories;
  String? _category;
  bool _isSub = true;
  String _cycle = 'monthly';
  DateTime? _renewal;
  bool _isPromo = false;
  DateTime? _promoEnds;
  bool _userTouchedDate = false;
  bool _costCustomLatch = false;
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

  // Promo price fields — "not sure yet" escape hatches
  bool _promoCostUnsure = false;
  bool _promoEndsUnsure = false;
  bool _regularPriceUnsure = false;
  static const _commonPrices = [9.99, 14.99, 19.99, 29.99, 39.99, 49.99];

  // OCR bill scan
  bool _scanningBill = false;
  final Set<String> _ocrFilledFields = {}; // 'cost' | 'renewal' | 'name'

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
    _searchFocus.addListener(() {
      if (mounted) setState(() => _searchFocused = _searchFocus.hasFocus);
    });
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
      _matchedCatalog = _findMatchingCatalogEntry();
      // "Not sure yet" back-fills from whichever promo fields are null,
      // so re-opening an entry saved with an unanswered field doesn't
      // show it as a false validation error.
      if (a.isPromotionalPrice) {
        _promoCostUnsure = a.subscriptionCost == null;
        _promoEndsUnsure = a.promotionEndsDate == null;
        _regularPriceUnsure = a.regularPrice == null;
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
        _categories.add(
          Category(
            name: 'Utilities',
            color: AppTokens.categoryColor('Utilities'),
            isCustom: false,
          ),
        );
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

    // Update matched catalog when name changes (for tier chips) — Add
    // mode only. Edit mode's plain "App Name" field shares this same
    // controller, but re-matching there would flip the whole billing
    // section mid-edit, so it's deliberately inert once appToEdit is set.
    _nameCtrl.addListener(() {
      if (widget.appToEdit == null) {
        final match = _findMatchingCatalogEntry();
        if (match != _matchedCatalog) {
          setState(() {
            _matchedCatalog = match;
            _costCustomLatch = false;
          });
        }
        _searchDebounce?.cancel();
        _searchDebounce = Timer(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          setState(
            () => _searchResults = _searchCatalog(_nameCtrl.text.trim()),
          );
        });
      }
      _ocrFilledFields.remove('name');
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
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTokens.brandStart,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Reading your bill…',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.pop(dialogCtx);
                },
                child: Text(
                  'Cancel',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    String recognizedText = '';
    try {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
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
        const SnackBar(
          content: Text(
            "Couldn't read any text from that photo — try again or fill it in manually.",
          ),
        ),
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
        _costCustomLatch = true;
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
        const SnackBar(
          content: Text(
            "Couldn't confidently read the details — fill them in below.",
          ),
        ),
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
        if (e.name.length >= 3 && lower.contains(e.name.toLowerCase()))
          return e;
      }
    }
    return null;
  }

  double? _guessPrice(List<String> lines) {
    final priceRegex = RegExp(r'\$?\s?(\d{1,4}(?:,\d{3})*\.\d{2})');
    const preferKeywords = [
      'total',
      'amount due',
      'charged',
      'monthly',
      'plan cost',
      'you paid',
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
      if (preferred == null && preferKeywords.any(lower.contains))
        preferred = value;
      if (fallback == null || value > fallback) fallback = value;
    }
    return preferred ?? fallback;
  }

  static const _ocrMonths = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
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
    _searchFocus.dispose();
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
    final initialDate = current ?? DateTime(now.year, now.month, now.day);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CustomDatePickerSheet(
        initialDate: initialDate,
        onDateSelected: onPicked,
      ),
    );
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
      final target = nameEmpty
          ? _nameKey
          : costMissing
          ? _billingKey
          : _renewalKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (target.currentContext != null) {
          Scrollable.ensureVisible(
            target.currentContext!,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
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
        _renewal = defaultRenewalDate(cycle, _isPromo ? _promoEnds : null);
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
      _costCustomLatch = false;
      _isSub = true;
      _serviceType = catEntry.serviceType;
      if (catEntry.pricingTiers.isNotEmpty) {
        _costCtrl.text = catEntry.pricingTiers.first.monthlyPrice
            .toStringAsFixed(2);
      }
      if (!_userTouchedDate) {
        _renewal = defaultRenewalDate(_cycle, _isPromo ? _promoEnds : null);
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
    Widget? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTokens.fieldBg,
        borderRadius: BorderRadius.circular(AppTokens.rInput),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: value
                  ? AppTokens.brandStart.withValues(alpha: 0.12)
                  : AppTokens.hairline.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: icon ??
                flatIcon(
                  'tag_orange',
                  color: value ? AppTokens.brandStart : AppTokens.textFaint,
                  size: 18,
                ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: AppTokens.brandStart,
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
    String icon = 'calendar_dark',
    bool error = false,
  }) {
    final text = date == null
        ? placeholder
        : DateFormat('MMM d, yyyy').format(date);
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.rInput),
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 14),
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
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTokens.brandStart.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: flatIcon(
                'calendar_orange',
                color: AppTokens.brandStart,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.plusJakartaSans(
                  color: date == null
                      ? AppTokens.textPlaceholder
                      : AppTokens.textPrimary,
                  fontSize: 14.5,
                  fontWeight: date == null ? FontWeight.w500 : FontWeight.w600,
                ),
              ),
            ),
            Icon(
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
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppTokens.fieldBg,
            borderRadius: BorderRadius.circular(AppTokens.rInput),
            border: Border.all(color: AppTokens.hairline),
          ),
          child: Row(
            children: [
              if (cat != null && AppTokens.categories.containsKey(cat.name))
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTokens.brandStart.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: categoryIcon(cat.name, size: 22),
                )
              else
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: (cat?.color ?? AppTokens.textFaint)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: cat?.color ?? AppTokens.textFaint,
                      shape: BoxShape.circle,
                    ),
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
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
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
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: AppTokens.brandGradient,
                borderRadius: BorderRadius.circular(AppTokens.rInput),
              ),
              child: Text(
                prefill == 'nbn' ? 'NBN' : 'Mobile',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.screenBg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Set from Offers tab',
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textMuted,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
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
                onTap: () => setState(
                  () => _serviceType = _serviceType == 'nbn' ? null : 'nbn',
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: _serviceType == 'nbn'
                        ? AppTokens.brandGradient
                        : null,
                    borderRadius: BorderRadius.circular(AppTokens.rInput - 3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'NBN',
                    style: GoogleFonts.plusJakartaSans(
                      color: _serviceType == 'nbn'
                          ? AppTokens.screenBg
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
                onTap: () => setState(
                  () =>
                      _serviceType = _serviceType == 'mobile' ? null : 'mobile',
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: _serviceType == 'mobile'
                        ? AppTokens.brandGradient
                        : null,
                    borderRadius: BorderRadius.circular(AppTokens.rInput - 3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Mobile',
                    style: GoogleFonts.plusJakartaSans(
                      color: _serviceType == 'mobile'
                          ? AppTokens.screenBg
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
                  borderRadius: BorderRadius.circular(AppTokens.rInput - 4),
                  boxShadow: _cycle == 'monthly'
                      ? [
                          BoxShadow(
                            color: AppTokens.brandStart.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
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
                  borderRadius: BorderRadius.circular(AppTokens.rInput - 4),
                  boxShadow: _cycle == 'yearly'
                      ? [
                          BoxShadow(
                            color: AppTokens.brandStart.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
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

  // Same-line Billing Cycle + Promo Price Question
  Widget _cadenceAndPromoRow() {
    return Row(
      children: [
        // Left: Billing Cycle (Monthly / Yearly)
        Expanded(
          flex: 6,
          child: _labeled(
            'Billing cycle',
            _cyclePill(),
          ),
        ),
        const SizedBox(width: 10),
        // Right: Promo price toggle
        Expanded(
          flex: 5,
          child: _labeled(
            'Promo deal?',
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isPromo = !_isPromo);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  gradient: _isPromo ? AppTokens.brandGradient : null,
                  color: _isPromo ? null : AppTokens.fieldBg,
                  borderRadius: BorderRadius.circular(AppTokens.rInput),
                  border: Border.all(
                    color: _isPromo ? Colors.transparent : AppTokens.hairline,
                  ),
                  boxShadow: _isPromo
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
                      _isPromo
                          ? Icons.local_offer_rounded
                          : Icons.local_offer_outlined,
                      size: 16,
                      color: _isPromo ? Colors.white : AppTokens.textFaint,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isPromo ? 'Promo (Yes)' : 'Standard',
                      style: GoogleFonts.plusJakartaSans(
                        color: _isPromo ? Colors.white : AppTokens.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _notSureChip(VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: Alignment.center,
        child: Text(
          'Not sure yet',
          style: GoogleFonts.plusJakartaSans(
            color: AppTokens.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _priceChip(String text, bool selected, {bool muted = false}) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        gradient: selected ? AppTokens.brandGradient : null,
        color: selected ? null : AppTokens.fieldBg,
        borderRadius: BorderRadius.circular(AppTokens.rInput - 2),
        border: Border.all(
          color: selected
              ? Colors.transparent
              : AppTokens.hairline,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppTokens.brandStart.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: muted
            ? GoogleFonts.plusJakartaSans(
                color: AppTokens.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )
            : GoogleFonts.spaceGrotesk(
                color: selected ? Colors.white : AppTokens.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
      ),
    );
  }

  /// Multi-column cost and pricing tiers field
  Widget _priceField({
    required String label,
    required TextEditingController controller,
    List<PricingTier> tiers = const [],
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

    final ocrGuessed =
        ocrFieldKey != null && _ocrFilledFields.contains(ocrFieldKey);
    final text = controller.text;
    final matchesTier = tiers.any(
      (t) => t.monthlyPrice.toStringAsFixed(2) == text,
    );
    final showTierChips =
        tiers.isNotEmpty && !_costCustomLatch && (text.isEmpty || matchesTier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labeled(
          label,
          _textField(
            controller: controller,
            hint: '0.00',
            prefixText: '\$ ',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            error: error,
            style: GoogleFonts.spaceGrotesk(
              color: AppTokens.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            onChanged: (_) => _ocrFilledFields.remove(ocrFieldKey),
          ),
          helper: ocrGuessed
              ? 'Scanned — check this'
              : (error ? requiredHelper : null),
          error: error,
        ),
        const SizedBox(height: 8),
        if (showTierChips) ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tiers.length + 1,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 8,
              childAspectRatio: 3.4,
            ),
            itemBuilder: (_, index) {
              if (index < tiers.length) {
                final t = tiers[index];
                final str = t.monthlyPrice.toStringAsFixed(2);
                final sel = text == str;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      controller.text = str;
                      _ocrFilledFields.remove(ocrFieldKey);
                    });
                  },
                  child: _priceChip('${t.tierName} · \$$str', sel),
                );
              } else {
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _costCustomLatch = true);
                  },
                  child: _priceChip('Custom', false, muted: true),
                );
              }
            },
          ),
        ] else ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _commonPrices.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 8,
              childAspectRatio: 2.8,
            ),
            itemBuilder: (_, index) {
              final p = _commonPrices[index];
              final str = p.toStringAsFixed(2);
              final sel = text == str;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    controller.text = str;
                    _ocrFilledFields.remove(ocrFieldKey);
                  });
                },
                child: _priceChip('\$$str', sel),
              );
            },
          ),
          if (tiers.isNotEmpty) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _costCustomLatch = false;
                  controller.clear();
                });
              },
              child: Text(
                'Use a listed plan price instead',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.brandStart,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (allowUnsure && onUnsureToggle != null) ...[
            const SizedBox(height: 4),
            _notSureChip(onUnsureToggle),
          ],
        ],
      ],
    );
  }

  // ── Beautiful Date Selector with 1-Tap Presets ─────────────

  Widget _renewalDateSelector() {
    final date = _renewal;
    final formattedDate = date != null
        ? DateFormat('EEE, d MMM yyyy').format(date)
        : 'Select renewal date';
    final daysUntil = date != null
        ? date.difference(DateTime.now()).inDays + 1
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main Date Card
        InkWell(
          borderRadius: BorderRadius.circular(AppTokens.rInput),
          onTap: () => _pickDate(
            current: _renewal,
            onPicked: (d) => setState(() {
              _renewal = d;
              _userTouchedDate = true;
              _renewalError = false;
              _ocrFilledFields.remove('renewal');
            }),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppTokens.fieldBg,
              borderRadius: BorderRadius.circular(AppTokens.rInput),
              border: Border.all(
                color: _renewalError ? AppTokens.danger : AppTokens.hairline,
                width: _renewalError ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTokens.brandStart.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: flatIcon(
                    'calendar_orange',
                    color: AppTokens.brandStart,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formattedDate,
                        style: GoogleFonts.spaceGrotesk(
                          color: date != null
                              ? AppTokens.textPrimary
                              : AppTokens.textPlaceholder,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        daysUntil != null
                            ? (daysUntil > 0
                                ? 'Renews in $daysUntil days'
                                : (daysUntil == 0
                                    ? 'Renews today'
                                    : 'Renewed ${-daysUntil} days ago'))
                            : 'Set to get reminder alerts',
                        style: GoogleFonts.plusJakartaSans(
                          color: date != null
                              ? AppTokens.brandStart
                              : AppTokens.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTokens.cardBg,
                    borderRadius: BorderRadius.circular(AppTokens.rSmallPill),
                    border: Border.all(color: AppTokens.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Change',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 13,
                        color: AppTokens.textMuted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Quick 1-tap Presets Row
        Row(
          children: [
            _quickDatePreset('Today', DateTime.now()),
            const SizedBox(width: 6),
            _quickDatePreset(
              '+1 Month',
              DateTime(
                DateTime.now().year,
                DateTime.now().month + 1,
                DateTime.now().day,
              ),
            ),
            const SizedBox(width: 6),
            _quickDatePreset(
              '+1 Year',
              DateTime(
                DateTime.now().year + 1,
                DateTime.now().month,
                DateTime.now().day,
              ),
            ),
          ],
        ),
        if (_renewalError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              'Renewal date is required',
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.danger,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _quickDatePreset(String label, DateTime targetDate) {
    final isSelected = _renewal != null &&
        _renewal!.year == targetDate.year &&
        _renewal!.month == targetDate.month &&
        _renewal!.day == targetDate.day;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _renewal = targetDate;
            _userTouchedDate = true;
            _renewalError = false;
            _ocrFilledFields.remove('renewal');
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? AppTokens.brandStart.withValues(alpha: 0.12)
                : AppTokens.fieldBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppTokens.brandStart : AppTokens.hairline,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: isSelected ? AppTokens.brandStart : AppTokens.textMuted,
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _promoDateField({
    required String label,
    required String helper,
    required DateTime? date,
    required String icon,
    required bool unsure,
    required ValueChanged<DateTime> onPicked,
    required VoidCallback onUnsureToggle,
    String? ocrFieldKey,
  }) {
    final ocrGuessed =
        ocrFieldKey != null && _ocrFilledFields.contains(ocrFieldKey);
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

  // ── Quick Action Cards (Scan Bill / Scan Phone) ──────────────

  Widget _quickActionCards() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _scanBill,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTokens.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTokens.hairline),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: AppTokens.isDark ? 0.2 : 0.04,
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
                      color: AppTokens.brandStart.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: flatIcon(
                      'scan_frame_orange',
                      size: 20,
                      color: AppTokens.brandStart,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Scan bill',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Auto-fill with ML',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 10.5,
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
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: _goScanPhone,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTokens.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTokens.hairline),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: AppTokens.isDark ? 0.2 : 0.04,
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
                      color: AppTokens.brandStart.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: flatIcon(
                      'search_orange',
                      size: 20,
                      color: AppTokens.brandStart,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Scan phone',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Find installed',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 10.5,
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
        ),
      ],
    );
  }

  // ── Search-first entry (replaces the plain "App Name" field in add mode) ──

  Widget _searchSection() {
    final hasQuery = _nameCtrl.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
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
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                sizeCurve: Curves.easeOutCubic,
                crossFadeState: hasQuery
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _searchResultsList(),
                ),
                secondChild: const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 12),
              _quickActionCards(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _suggestedStrip(),
      ],
    );
  }

  Widget _searchField() {
    final matched = _matchedCatalog;
    final active = _searchFocused || matched != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WHAT ARE YOU ADDING?',
          style: GoogleFonts.plusJakartaSans(
            color: AppTokens.textFaint,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppTokens.cardBg,
            borderRadius: BorderRadius.circular(AppTokens.rInput),
            border: Border.all(
              color: _nameError
                  ? AppTokens.danger
                  : (active ? AppTokens.brandStart : AppTokens.hairline),
              width: active && !_nameError ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: AppTokens.isDark ? 0.2 : 0.04,
                ),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: matched != null
                      ? _iconForCatalog(matched, size: 30)
                      : KeyedSubtree(
                          key: const ValueKey('name-icon'),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTokens.brandStart.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: flatIcon(
                              'search_orange',
                              color: AppTokens.brandStart,
                              size: 18,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  focusNode: _searchFocus,
                  cursorColor: AppTokens.brandStart,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: "e.g. Netflix, gym, Spotify, NBN",
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
                  builder: (_, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTokens.brandStart.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: AppTokens.brandStart,
                      size: 20,
                    ),
                  ),
                )
              else if (_nameCtrl.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _nameCtrl.clear();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      color: AppTokens.textFaint,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
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
      children: [for (final e in _searchResults) _searchResultTile(e)],
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.cardBg,
          borderRadius: BorderRadius.circular(AppTokens.rInput),
          border: Border.all(color: AppTokens.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: AppTokens.isDark ? 0.18 : 0.03,
              ),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
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
                      fontWeight: FontWeight.w700,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTokens.brandStart.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'from \$${priceMin.toStringAsFixed(2)}',
                  style: GoogleFonts.spaceGrotesk(
                    color: AppTokens.brandStart,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
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
      MaterialPageRoute(
        builder: (_) => const DiscoveryScreen(fromOnboarding: false),
      ),
    );
    if (result == true && mounted) Navigator.pop(context, true);
  }

  // Empty-query state: compact suggested catalog entries
  Widget _suggestedStrip() {
    final quickEntries = _quickEntries;
    if (quickEntries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.padContent),
          child: Row(
            children: [
              Text(
                'POPULAR SERVICES',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textFaint,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                'Tap to pre-fill',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textFaint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.padContent,
            ),
            itemCount: quickEntries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final e = quickEntries[i];
              final isMatched = _matchedCatalog?.id == e.id;
              return GestureDetector(
                onTap: () => _selectSearchResult(e),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isMatched
                        ? AppTokens.brandStart.withValues(alpha: 0.12)
                        : AppTokens.cardBg,
                    borderRadius: BorderRadius.circular(AppTokens.rPill),
                    border: Border.all(
                      color: isMatched
                          ? AppTokens.brandStart
                          : AppTokens.hairline,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: AppTokens.isDark ? 0.15 : 0.02,
                        ),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _iconForCatalog(e, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        e.name,
                        style: GoogleFonts.plusJakartaSans(
                          color: isMatched
                              ? AppTokens.brandStart
                              : AppTokens.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
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
        vertical: 12,
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
                  fontSize: 20,
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
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: danger
              ? AppTokens.danger.withValues(alpha: 0.10)
              : AppTokens.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: danger
                ? AppTokens.danger.withValues(alpha: 0.3)
                : AppTokens.hairline,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: AppTokens.isDark ? 0.2 : 0.03,
              ),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 19,
          color: danger ? AppTokens.danger : AppTokens.textPrimary,
        ),
      ),
    );
  }

  Widget _saveBar(bool isEdit) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.padContent,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppTokens.cardBg,
        border: Border(top: BorderSide(color: AppTokens.hairline)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: AppTokens.isDark ? 0.25 : 0.05,
            ),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: _save,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: AppTokens.brandGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTokens.brandStart.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                isEdit ? 'Save Changes' : 'Save Subscription',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section card ─────────────────────────────────────────────

  Widget _sectionCard(
    String title,
    Widget child, {
    bool promo = false,
    Widget? icon,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTokens.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: promo
              ? AppTokens.warning.withValues(alpha: 0.35)
              : AppTokens.hairline,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: AppTokens.isDark ? 0.22 : 0.04,
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
              if (icon != null) ...[
                icon,
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  color: promo ? AppTokens.warning : AppTokens.textFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // The promo fields live in their own amber "cliff" block so the moment
  // the discount stops reads as a distinct, time-pressure event — the thing
  // this app exists to catch.
  Widget _promoCliffBlock() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTokens.rInput),
        border: Border.all(color: AppTokens.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              flatIcon(
                'chart_trending_dark',
                color: AppTokens.warning,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                'PROMO CLIFF',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.warning,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _promoDateField(
            label: 'Promo ends on',
            helper: 'One-off — the date your discount stops',
            date: _promoEnds,
            icon: 'clock_dark',
            unsure: _promoEndsUnsure,
            onPicked: (d) => setState(() {
              _promoEnds = d;
              if (!_userTouchedDate) {
                _renewal = defaultRenewalDate(_cycle, d);
                _renewalError = false;
              }
            }),
            onUnsureToggle: () => setState(() {
              _promoEndsUnsure = !_promoEndsUnsure;
              if (_promoEndsUnsure) _promoEnds = null;
            }),
          ),
          const SizedBox(height: 16),
          _priceField(
            label: 'Price after promo',
            controller: _regularCtrl,
            allowUnsure: true,
            unsure: _regularPriceUnsure,
            onUnsureToggle: () => setState(() {
              _regularPriceUnsure = !_regularPriceUnsure;
              if (_regularPriceUnsure) _regularCtrl.clear();
            }),
          ),
        ],
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
                      _sectionCard(
                        'SUBSCRIPTION DETAILS',
                        icon: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppTokens.brandStart.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: flatIcon(
                            'tag_orange',
                            color: AppTokens.brandStart,
                            size: 14,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isEdit && _matchedCatalog != null) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTokens.fieldBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppTokens.brandStart
                                        .withValues(alpha: 0.22),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _iconForCatalog(_matchedCatalog!, size: 40),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _matchedCatalog!.name,
                                            style: GoogleFonts.plusJakartaSans(
                                              color: AppTokens.textPrimary,
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            'Auto-matched · ${_matchedCatalog!.category}',
                                            style: GoogleFonts.plusJakartaSans(
                                              color: AppTokens.textMuted,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          _nameCtrl.clear();
                                          _matchedCatalog = null;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppTokens.cardBg,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppTokens.hairline,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.close_rounded,
                                          color: AppTokens.textMuted,
                                          size: 15,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (isEdit) ...[
                              Container(
                                key: _nameKey,
                                child: _labeled(
                                  'App Name',
                                  _textField(
                                    controller: _nameCtrl,
                                    hint: 'e.g. Netflix',
                                    error: _nameError,
                                    onChanged: (_) {
                                      if (_nameError)
                                        setState(() => _nameError = false);
                                    },
                                  ),
                                  helper: _nameError
                                      ? 'Name is required'
                                      : null,
                                  error: _nameError,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            _categoryField(),
                            if (widget.prefillServiceType != null) ...[
                              const SizedBox(height: 16),
                              _serviceTypePicker(),
                            ],
                          ],
                        ),
                      ),
                      _sectionCard(
                        'PRICING & BILLING',
                        icon: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppTokens.brandStart.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: categoryIcon('Finance', size: 16),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                                  const SizedBox(height: 14),
                                  // Same-line Billing Cycle + Promo deal toggle
                                  _cadenceAndPromoRow(),
                                  const SizedBox(height: 14),
                                  // Multi-column cost input & presets
                                  Container(
                                    key: _billingKey,
                                    child: _priceField(
                                      label: _isPromo ? 'Promo price' : 'Cost',
                                      controller: _costCtrl,
                                      tiers:
                                          _matchedCatalog?.pricingTiers ??
                                          const [],
                                      allowUnsure: _isPromo,
                                      unsure: _isPromo && _promoCostUnsure,
                                      onUnsureToggle: () => setState(() {
                                        _promoCostUnsure = !_promoCostUnsure;
                                        if (_promoCostUnsure) _costCtrl.clear();
                                      }),
                                      error: _costError,
                                      requiredHelper: 'Cost is required',
                                      ocrFieldKey: 'cost',
                                    ),
                                  ),
                                  AnimatedCrossFade(
                                    duration: const Duration(milliseconds: 260),
                                    sizeCurve: Curves.easeOutCubic,
                                    crossFadeState: _isPromo
                                        ? CrossFadeState.showFirst
                                        : CrossFadeState.showSecond,
                                    firstChild: _promoCliffBlock(),
                                    secondChild: const SizedBox(
                                      width: double.infinity,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Beautiful Date Selection Card + 1-Tap Presets
                                  Container(
                                    key: _renewalKey,
                                    child: _labeled(
                                      'Next renewal date',
                                      _renewalDateSelector(),
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
                      ),
                      _sectionCard(
                        'OPTIONAL NOTES',
                        icon: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppTokens.brandStart.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: flatIcon(
                            'edit_orange',
                            color: AppTokens.brandStart,
                            size: 14,
                          ),
                        ),
                        _textField(
                          controller: _notesCtrl,
                          hint: 'e.g. Family plan, shared with 3 people',
                          minLines: 3,
                          maxLines: 5,
                        ),
                      ),
                      const SizedBox(height: 10),
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
  // Orange is reserved for the app's single CTA color and green/yellow are
  // reserved semantics — none are offered as a category swatch.
  Color _color = const Color(0xFF6366F1);
  static const _swatches = [
    Color(0xFF6366F1),
    Color(0xFFC026D3),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFF0284C7),
    Color(0xFF5B21B6),
    Color(0xFFA855F7),
    Color(0xFF3B82F6),
    Color(0xFF701A75),
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
                              if (AppTokens.categories.containsKey(c.name))
                                categoryIcon(c.name, size: 20)
                              else
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
                                Icon(
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
                      flatIcon(
                        'add_circle_outline_dark',
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
                        side: BorderSide(color: AppTokens.hairline),
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

// ─────────────────────────────────────────────────────────────
// Beautiful Custom In-App Date Picker Bottom Sheet
// ─────────────────────────────────────────────────────────────

class _CustomDatePickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final ValueChanged<DateTime> onDateSelected;

  const _CustomDatePickerSheet({
    required this.initialDate,
    required this.onDateSelected,
  });

  @override
  State<_CustomDatePickerSheet> createState() => _CustomDatePickerSheetState();
}

class _CustomDatePickerSheetState extends State<_CustomDatePickerSheet> {
  late DateTime _selectedDate;
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _displayedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
  }

  void _prevMonth() {
    HapticFeedback.selectionClick();
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
        1,
      );
    });
  }

  void _nextMonth() {
    HapticFeedback.selectionClick();
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
        1,
      );
    });
  }

  void _selectPreset(DateTime date) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _displayedMonth = DateTime(date.year, date.month, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysInMonth = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + 1,
      0,
    ).day;
    final firstWeekday = _displayedMonth.weekday; // Monday = 1, Sunday = 7
    final daysBefore = firstWeekday - 1;

    final daysInPrevMonth = DateTime(
      _displayedMonth.year,
      _displayedMonth.month,
      0,
    ).day;

    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 28),
      decoration: BoxDecoration(
        color: AppTokens.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle Bar
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
            const SizedBox(height: 14),

            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTokens.brandStart.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: flatIcon(
                      'calendar_orange',
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
                          'Select Renewal Date',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          DateFormat('EEEE, d MMMM yyyy').format(_selectedDate),
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTokens.brandStart,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTokens.fieldBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTokens.hairline),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: AppTokens.textMuted,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Month Navigator Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTokens.fieldBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTokens.hairline),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 22),
                      color: AppTokens.textPrimary,
                      splashRadius: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: _prevMonth,
                    ),
                    Text(
                      DateFormat('MMMM yyyy').format(_displayedMonth),
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTokens.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 22),
                      color: AppTokens.textPrimary,
                      splashRadius: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: _nextMonth,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Weekday Row (Mon - Sun)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  'MON',
                  'TUE',
                  'WED',
                  'THU',
                  'FRI',
                  'SAT',
                  'SUN',
                ].map((day) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.textFaint,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),

            // Calendar Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 42,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 1.15,
                ),
                itemBuilder: (_, index) {
                  int dayNumber;
                  bool isCurrentMonth = true;
                  DateTime cellDate;

                  if (index < daysBefore) {
                    isCurrentMonth = false;
                    dayNumber = daysInPrevMonth - (daysBefore - 1 - index);
                    cellDate = DateTime(
                      _displayedMonth.year,
                      _displayedMonth.month - 1,
                      dayNumber,
                    );
                  } else if (index >= daysBefore + daysInMonth) {
                    isCurrentMonth = false;
                    dayNumber = index - (daysBefore + daysInMonth) + 1;
                    cellDate = DateTime(
                      _displayedMonth.year,
                      _displayedMonth.month + 1,
                      dayNumber,
                    );
                  } else {
                    dayNumber = index - daysBefore + 1;
                    cellDate = DateTime(
                      _displayedMonth.year,
                      _displayedMonth.month,
                      dayNumber,
                    );
                  }

                  final isSelected = _selectedDate.year == cellDate.year &&
                      _selectedDate.month == cellDate.month &&
                      _selectedDate.day == cellDate.day;

                  final isToday = today.year == cellDate.year &&
                      today.month == cellDate.month &&
                      today.day == cellDate.day;

                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedDate = cellDate;
                        if (!isCurrentMonth) {
                          _displayedMonth = DateTime(
                            cellDate.year,
                            cellDate.month,
                            1,
                          );
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        gradient: isSelected ? AppTokens.brandGradient : null,
                        color: isSelected
                            ? null
                            : (isToday
                                ? AppTokens.brandStart.withValues(alpha: 0.10)
                                : Colors.transparent),
                        borderRadius: BorderRadius.circular(10),
                        border: isToday && !isSelected
                            ? Border.all(
                                color: AppTokens.brandStart
                                    .withValues(alpha: 0.5),
                              )
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppTokens.brandStart
                                      .withValues(alpha: 0.35),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$dayNumber',
                        style: GoogleFonts.spaceGrotesk(
                          color: isSelected
                              ? Colors.white
                              : (isCurrentMonth
                                  ? AppTokens.textPrimary
                                  : AppTokens.textFaint.withValues(alpha: 0.5)),
                          fontSize: 13.5,
                          fontWeight: isSelected || isToday
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // Quick 1-Tap Presets
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _presetPill('Today', today),
                  const SizedBox(width: 6),
                  _presetPill(
                    'In 7 Days',
                    today.add(const Duration(days: 7)),
                  ),
                  const SizedBox(width: 6),
                  _presetPill(
                    '+1 Month',
                    DateTime(today.year, today.month + 1, today.day),
                  ),
                  const SizedBox(width: 6),
                  _presetPill(
                    '+1 Year',
                    DateTime(today.year + 1, today.month, today.day),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Confirm Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onDateSelected(_selectedDate);
                  Navigator.pop(context);
                },
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: AppTokens.brandGradient,
                    borderRadius: BorderRadius.circular(AppTokens.rInput),
                    boxShadow: [
                      BoxShadow(
                        color: AppTokens.brandStart.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Set Renewal Date',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetPill(String label, DateTime targetDate) {
    final isSelected = _selectedDate.year == targetDate.year &&
        _selectedDate.month == targetDate.month &&
        _selectedDate.day == targetDate.day;

    return Expanded(
      child: GestureDetector(
        onTap: () => _selectPreset(targetDate),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? AppTokens.brandStart.withValues(alpha: 0.14)
                : AppTokens.fieldBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? AppTokens.brandStart
                  : AppTokens.hairline,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: isSelected
                  ? AppTokens.brandStart
                  : AppTokens.textMuted,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
