import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/category_model.dart';
import '../services/storage_service.dart';
import '../theme/app_tokens.dart';

final _moneyFmt = NumberFormat.currency(
  locale: 'en_US',
  symbol: '\$',
  decimalDigits: 2,
);

/// The 12 swatches offered in both the standalone color picker and the
/// New Category dialog (spec: COLOR PICKER DIALOG).
const List<Color> _swatchColors = [
  Color(0xFF6366F1),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFFF472B6),
  Color(0xFF06B6D4),
  Color(0xFF22D3EE),
  Color(0xFF10B981),
  Color(0xFF34D399),
  Color(0xFFF59E0B),
  Color(0xFFFBBF24),
  Color(0xFFEF4444),
  Color(0xFF3B82F6),
];

class CategoriesScreen extends StatefulWidget {
  final List<Category> categories;
  final Map<String, double> spending; // category → monthly cost
  final Map<String, int> appCounts; // category → app count
  const CategoriesScreen({
    required this.categories,
    this.spending = const {},
    this.appCounts = const {},
    super.key,
  });
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late List<Category> _categories;

  @override
  void initState() {
    super.initState();
    _categories = List.from(widget.categories);
  }

  bool _isDuplicateName(String name, {Category? excluding}) {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.isEmpty) return false;
    return _categories.any(
      (c) => c != excluding && c.name.trim().toLowerCase() == trimmed,
    );
  }

  Future<void> _addCategory() async {
    final result = await showDialog<_NewCategoryResult>(
      context: context,
      builder: (_) => _NewCategoryDialog(isDuplicate: _isDuplicateName),
    );
    if (result == null) return;
    final cat = Category(
      name: result.name,
      color: result.color,
      isCustom: true,
    );
    await StorageService().saveCategory(cat);
    if (!mounted) return;
    setState(() => _categories.add(cat));
    HapticFeedback.mediumImpact();
  }

  Future<void> _editColor(Category cat) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(selected: cat.color),
    );
    if (picked == null || picked == cat.color) return;
    final updated = Category(
      name: cat.name,
      color: picked,
      isCustom: cat.isCustom,
    );
    await StorageService().saveCategory(updated);
    if (!mounted) return;
    setState(() {
      final i = _categories.indexOf(cat);
      if (i >= 0) _categories[i] = updated;
    });
  }

  Future<void> _rename(Category cat) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(
        initial: cat.name,
        isDuplicate: (name) => _isDuplicateName(name, excluding: cat),
      ),
    );
    if (newName == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == cat.name) return;
    final updated = Category(
      name: trimmed,
      color: cat.color,
      isCustom: cat.isCustom,
    );
    await StorageService().renameCategory(cat.name, updated);
    if (!mounted) return;
    setState(() {
      final i = _categories.indexOf(cat);
      if (i >= 0) _categories[i] = updated;
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> _delete(Category cat) async {
    final count = await StorageService().appCountForCategory(cat.name);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteCategoryDialog(name: cat.name, appCount: count),
    );
    if (ok != true) return;
    await StorageService().deleteCategory(cat.name);
    if (!mounted) return;
    setState(() => _categories.remove(cat));
    HapticFeedback.heavyImpact();
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, item);
    });
    await StorageService().saveCategoryOrder(_categories);
  }

  @override
  Widget build(BuildContext context) {
    final inUse = _categories
        .where((c) => (widget.appCounts[c.name] ?? 0) > 0)
        .length;

    return Scaffold(
      backgroundColor: AppTokens.screenBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            if (_categories.isNotEmpty) _buildSummaryStrip(inUse),
            Expanded(
              child: _categories.isEmpty ? _buildEmptyState() : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.padHeader,
        14,
        AppTokens.padHeader,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconTile(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Color(0xFFC9C9D6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Categories',
                  style: GoogleFonts.spaceGrotesk(
                    color: AppTokens.textStrong,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _IconTile(
                onTap: _addCategory,
                gradient: AppTokens.brandGradient,
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Drag to reorder · tap a color to change it',
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStrip(int inUse) {
    final segments = <MapEntry<Category, double>>[];
    for (final c in _categories) {
      final spend = widget.spending[c.name] ?? 0;
      if (spend > 0) segments.add(MapEntry(c, spend));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.padContent,
        0,
        AppTokens.padContent,
        14,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.padCard),
        decoration: BoxDecoration(
          color: AppTokens.cardBg,
          borderRadius: BorderRadius.circular(AppTokens.rCard),
          border: Border.all(color: AppTokens.hairline, width: 1),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$inUse ${inUse == 1 ? 'category' : 'categories'}',
                  style: GoogleFonts.spaceGrotesk(
                    color: AppTokens.textStrong,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'in use',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: segments.isEmpty
                  ? Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppTokens.fieldBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 10,
                        child: Row(
                          children: [
                            for (final e in segments)
                              Expanded(
                                flex: (e.value * 100).round().clamp(1, 1000000),
                                child: Container(color: e.key.color),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTokens.fieldBg,
              shape: BoxShape.circle,
              border: Border.all(color: AppTokens.hairline, width: 1),
            ),
            child: const Icon(
              Icons.category_rounded,
              size: 32,
              color: AppTokens.textFaint,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No categories yet',
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap + to create your first category',
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.padContent,
        4,
        AppTokens.padContent,
        40,
      ),
      itemCount: _categories.length,
      onReorder: _onReorder,
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final t = Curves.easeOut.transform(animation.value);
            return Transform.scale(
              scale: 1 + 0.03 * t,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTokens.rCard),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                        spreadRadius: -6,
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            );
          },
        );
      },
      itemBuilder: (context, i) {
        final cat = _categories[i];
        return _CategoryRow(
          key: ValueKey(cat.name),
          index: i,
          category: cat,
          appCount: widget.appCounts[cat.name] ?? 0,
          spend: widget.spending[cat.name] ?? 0,
          onColorTap: () => _editColor(cat),
          onRename: () => _rename(cat),
          onDelete: cat.name == uncategorizedName ? null : () => _delete(cat),
        );
      },
    );
  }
}

/// 42x42 (default) tile used for the back arrow and the "+" action in the
/// custom app bar — matches the shared "IconTile" pattern from the spec.
class _IconTile extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Gradient? gradient;
  const _IconTile({required this.child, this.onTap, this.gradient});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: gradient == null ? AppTokens.fieldBg : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppTokens.rIconBtn),
          border: gradient == null
              ? Border.all(color: AppTokens.hairline, width: 1)
              : null,
        ),
        child: child,
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final int index;
  final Category category;
  final int appCount;
  final double spend;
  final VoidCallback onColorTap;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  const _CategoryRow({
    super.key,
    required this.index,
    required this.category,
    required this.appCount,
    required this.spend,
    required this.onColorTap,
    required this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final noApps = appCount == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.gapItem),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.padCard),
        decoration: BoxDecoration(
          color: AppTokens.cardBg,
          borderRadius: BorderRadius.circular(AppTokens.rCard),
          border: Border.all(color: AppTokens.hairline, width: 1),
        ),
        child: Row(
          children: [
            Listener(
              onPointerDown: (_) => HapticFeedback.selectionClick(),
              child: ReorderableDragStartListener(
                index: index,
                child: const Icon(
                  Icons.drag_indicator_rounded,
                  color: AppTokens.textFaint,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            GestureDetector(
              onTap: onColorTap,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: category.color,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (category.isCustom) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Custom',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.textFaint,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$appCount ${appCount == 1 ? 'app' : 'apps'} · '
                    '${_moneyFmt.format(spend)}/mo',
                    style: GoogleFonts.plusJakartaSans(
                      color: noApps ? AppTokens.textFaint : AppTokens.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              color: AppTokens.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppTokens.hairlineStrong),
              ),
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AppTokens.textMuted,
              ),
              onSelected: (v) {
                if (v == 'rename') onRename();
                if (v == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(
                    'Rename',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onDelete != null)
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTokens.danger,
                        fontWeight: FontWeight.w600,
                      ),
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

/// Reusable 4-column, 12-swatch color grid — used by both the standalone
/// color picker dialog and embedded directly in the New Category dialog.
class _ColorGrid extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onSelect;
  const _ColorGrid({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final c in _swatchColors)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onSelect(c);
            },
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(14),
                border: selected == c
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
              child: selected == c
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 20,
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final Color selected;
  const _ColorPickerDialog({required this.selected});
  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _selected = widget.selected;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTokens.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick a color',
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textStrong,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            _ColorGrid(
              selected: _selected,
              onSelect: (c) => setState(() => _selected = c),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: Text(
                    'Done',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.brandStart,
                      fontWeight: FontWeight.w700,
                    ),
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

class _NewCategoryResult {
  final String name;
  final Color color;
  const _NewCategoryResult(this.name, this.color);
}

class _NewCategoryDialog extends StatefulWidget {
  final bool Function(String name) isDuplicate;
  const _NewCategoryDialog({required this.isDuplicate});
  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _ctrl = TextEditingController();
  Color _color = _swatchColors[0];
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a category name');
      return;
    }
    if (widget.isDuplicate(name)) {
      setState(() => _error = 'A category with this name already exists');
      return;
    }
    Navigator.pop(context, _NewCategoryResult(name, _color));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTokens.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New category',
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textStrong,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Category name',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            _ColorGrid(
              selected: _color,
              onSelect: (c) => setState(() => _color = c),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _GradientButton(label: 'Create', onPressed: _submit),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final String initial;
  final bool Function(String name) isDuplicate;
  const _RenameDialog({required this.initial, required this.isDuplicate});
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a category name');
      return;
    }
    if (widget.isDuplicate(name)) {
      setState(() => _error = 'A category with this name already exists');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTokens.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rename category',
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textStrong,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Category name',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: _submit,
                  child: Text(
                    'Rename',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.brandStart,
                      fontWeight: FontWeight.w700,
                    ),
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

class _DeleteCategoryDialog extends StatelessWidget {
  final String name;
  final int appCount;
  const _DeleteCategoryDialog({required this.name, required this.appCount});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTokens.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete category?',
              style: GoogleFonts.spaceGrotesk(
                color: AppTokens.textStrong,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              appCount > 0
                  ? 'Move $appCount ${appCount == 1 ? 'app' : 'apps'} to Uncategorized?'
                  : 'Delete "$name"? No apps are assigned to it.',
              style: GoogleFonts.plusJakartaSans(
                color: AppTokens.textMuted,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    'Delete',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTokens.danger,
                      fontWeight: FontWeight.w700,
                    ),
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

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _GradientButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppTokens.brandGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
