import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/app_model.dart';
import '../models/catalog_entry.dart';
import '../models/category_model.dart';
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
      if (a.subscriptionCost != null) {
        final match = _findMatchingCatalogEntry();
        final costStr = a.subscriptionCost!.toStringAsFixed(2);
        final matchesTier =
            match != null &&
            match.pricingTiers.any(
              (t) => t.monthlyPrice.toStringAsFixed(2) == costStr,
            );
        if (!matchesTier) _useCustomCost = true;
      }
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
    });
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
      costMissing = _parsedCost == null;
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

    if (widget.appToEdit != null) {
      await NotificationService().cancelReminders(widget.appToEdit!.id);
      await NotificationService().cancelPromoReminders(widget.appToEdit!.id);
    }
    await StorageService().saveApp(app);
    await NotificationService().scheduleRenewalReminder(app);
    await NotificationService().schedulePromoReminder(app);
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
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _onCycleChanged(String cycle) {
    HapticFeedback.selectionClick();
    setState(() {
      _cycle = cycle;
      if (!_userTouchedDate) {
        final now = DateTime.now();
        _renewal = cycle == 'yearly'
            ? DateTime(now.year + 1, now.month, now.day)
            : DateTime(now.year, now.month + 1, now.day);
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
      _nameError = false;
      _costError = false;
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
      'Category',
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
            style: GoogleFonts.plusJakartaSans(color: AppTokens.textMuted, fontSize: 12),
          ),
        ]),
      );
    }
    return _labeled(
      'Plan type (optional)',
      Container(
        height: 48,
        padding: const EdgeInsets.all(3),
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
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppTokens.gold.withValues(alpha: 0.12)
                            : AppTokens.fieldBg,
                        borderRadius: BorderRadius.circular(10),
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
                          fontSize: 13,
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
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.fieldBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTokens.hairline),
                    ),
                    child: Text(
                      'Custom',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.textMuted,
                        fontSize: 13,
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

  // C2 — Quick Add from catalog
  Widget _quickAddSection() {
    final catalog = CatalogService();
    List<CatalogEntry> quickEntries = [];
    for (final e in (catalog.appScanEntries + catalog.webManualEntries)) {
      if (e.pricingTiers.isNotEmpty) quickEntries.add(e);
      if (quickEntries.length >= 10) break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.padContent),
          child: Row(
            children: [
              Text(
                'QUICK ADD',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textFaint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  HapticFeedback.selectionClick();
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const DiscoveryScreen(fromOnboarding: false),
                    ),
                  );
                  if (result == true && mounted) Navigator.pop(context, true);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wifi_tethering_rounded,
                      size: 14,
                      color: AppTokens.gold,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Scan my phone',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
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
                onTap: () => _fillFromCatalog(e),
                child: Container(
                  width: 92,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTokens.fieldBg,
                    borderRadius: BorderRadius.circular(16),
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
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'from \$${priceMin.toStringAsFixed(2)}',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTokens.textMuted,
                          fontSize: 10,
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
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
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
        width: 42,
        height: 42,
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
          color: danger ? AppTokens.danger : const Color(0xFFC9C9D6),
        ),
      ),
    );
  }

  Widget _saveBar(bool isEdit) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x000B0B11), AppTokens.screenBg],
        ),
        border: Border(top: BorderSide(color: AppTokens.hairline)),
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
                if (!isEdit) _quickAddSection(),
                if (!isEdit) const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.padContent,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
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
                                  const SizedBox(height: 16),
                                  _labeled(
                                    'Notes',
                                    _textField(
                                      controller: _notesCtrl,
                                      hint:
                                          'e.g. Family plan, shared with 3 people',
                                      minLines: 3,
                                      maxLines: 5,
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
