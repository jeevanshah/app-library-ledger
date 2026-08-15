import 'dart:ui';
import 'package:flutter/material.dart';

/// PriceMinder — Shared Design Tokens
/// Based on the handoff spec: 00_shared_tokens.md
abstract class AppTokens {
  // ── Theme switch ───────────────────────────────────────────────────
  // Set from main.dart's MaterialApp.builder each rebuild, in sync with
  // whichever ThemeData Flutter actually resolved (system-follow or a
  // manual override) — see AppTheme.lightTheme/darkTheme. Every color
  // getter below reads this flag. Dart call sites for `AppTokens.x` are
  // identical whether `x` is a const field or a getter, so turning these
  // into getters required no changes anywhere else in the app.
  static bool isDark = false;

  // ── Surfaces ───────────────────────────────────────────────────────
  // Light = 2026-08 rebrand. Dark = the original pre-rebrand design,
  // restored as a real Dark Mode rather than deleted.
  static Color get screenBg =>
      isDark ? const Color(0xFF0B0B11) : const Color(0xFFFFFFFF);
  static Color get cardBg =>
      isDark ? const Color(0xFF14141C) : const Color(0xFFFFFFFF);
  static Color get fieldBg =>
      isDark ? const Color(0xFF15151D) : const Color(0xFFF3F4F6);
  static Color get cardBgRaised =>
      isDark ? const Color(0xFF17171F) : const Color(0xFFFFFFFF);
  static Color get navBg =>
      isDark ? const Color(0xD1181820) : const Color(0xF2FFFFFF);
  static Color get hairline =>
      isDark ? const Color(0x0DFFFFFF) : const Color(0x14000000);
  static Color get hairlineStrong =>
      isDark ? const Color(0x14FFFFFF) : const Color(0x1F000000);

  // ── Text (black ink in light mode, not navy — explicitly decided) ──
  static Color get textStrong =>
      isDark ? const Color(0xFFF6F6FB) : const Color(0xFF14141C);
  static Color get textPrimary =>
      isDark ? const Color(0xFFF2F2F8) : const Color(0xFF24242E);
  static Color get textMuted =>
      isDark ? const Color(0xFF7C7C92) : const Color(0xFF6B6B76);
  static Color get textFaint =>
      isDark ? const Color(0xFF6B6B82) : const Color(0xFF9797A1);
  static Color get textPlaceholder =>
      isDark ? const Color(0xFF5C5C72) : const Color(0xFFB4B4BC);

  // ── CTA / action (the single dominant accent app-wide) ─────────────
  // Light: orange (2026-08 rebrand). Dark: gold — restoring the original
  // design's look, since gold (not the old purple/indigo brand gradient)
  // was what actually painted the majority of these call sites before the
  // rebrand renamed them to brandStart/brandEnd. The old purple/indigo is
  // retired, not reintroduced — keeping it would make dark mode read as
  // purple-accented instead of the gold-dominant look it used to be.
  static Color get brandStart =>
      isDark ? const Color(0xFFC8A96E) : const Color(0xFFFF5A1F);
  static Color get brandEnd =>
      isDark ? const Color(0xFFDFC896) : const Color(0xFFFF8A50);
  static Color get brandMid =>
      isDark ? const Color(0xFFD4BC8B) : const Color(0xFFFF7238);

  // ── Gold accent (brand/identity only — logo, hero moments. Never a
  // functional UI signal in light mode; doubles as the CTA accent in dark
  // mode via brandStart/brandEnd above). Theme-invariant — never changed
  // by the rebrand. ────────────────────────────────────────────────────
  static const Color gold = Color(0xFFC8A96E);
  static const Color goldLight = Color(0xFFD4BC8B);
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC8A96E), Color(0xFFDFC896)],
  );
  static LinearGradient get brandGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandStart, brandEnd],
  );
  static LinearGradient get brandGradient3 => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandStart, brandMid, brandEnd],
    stops: const [0.0, 0.46, 1.0],
  );
  static BoxShadow get brandGlowShadow => isDark
      ? BoxShadow(
          color: brandEnd.withValues(alpha: 0.75),
          blurRadius: 44,
          offset: const Offset(0, 24),
          spreadRadius: -20,
        )
      : BoxShadow(
          color: brandMid.withValues(alpha: 0.28),
          blurRadius: 28,
          offset: const Offset(0, 14),
          spreadRadius: -16,
        );

  // ── Category Palette ──────────────────────────────────────────────
  static const Map<String, _CatDef> categories = {
    'Productivity': _CatDef(Color(0xFF6366F1), [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
    ], 'productivity'),
    'Media / Streaming': _CatDef(Color(0xFFEC4899), [
      Color(0xFFEC4899),
      Color(0xFFF472B6),
    ], 'media_streaming'),
    'Utilities': _CatDef(Color(0xFF06B6D4), [
      Color(0xFF06B6D4),
      Color(0xFF22D3EE),
    ], 'utilities'),
    'Shopping': _CatDef(Color(0xFFC026D3), [
      Color(0xFFC026D3),
      Color(0xFFE879F9),
    ], 'shopping'),
    'Health / Fitness': _CatDef(Color(0xFF0284C7), [
      Color(0xFF0284C7),
      Color(0xFF7DD3FC),
    ], 'health_fitness'),
    'Finance': _CatDef(Color(0xFF5B21B6), [
      Color(0xFF5B21B6),
      Color(0xFFA78BFA),
    ], 'finance'),
    'Notes / Journaling': _CatDef(Color(0xFFA855F7), [
      Color(0xFFA855F7),
      Color(0xFFC084FC),
    ], 'notes_journaling'),
    'Social': _CatDef(Color(0xFF3B82F6), [
      Color(0xFF3B82F6),
      Color(0xFF60A5FA),
    ], 'social'),
    'Education': _CatDef(Color(0xFF701A75), [
      Color(0xFF701A75),
      Color(0xFFA21CAF),
    ], 'education'),
    'Travel': _CatDef(Color(0xFF14B8A6), [
      Color(0xFF14B8A6),
      Color(0xFF2DD4BF),
    ], 'travel'),
  };

  static Color categoryColor(String name) =>
      categories[name]?.base ?? Colors.grey;
  static List<Color> categoryGradient(String name) =>
      categories[name]?.gradient ?? [Colors.grey, Colors.grey.shade400];

  // ── Semantic (strict — savings/success=green, time-pressure=yellow,
  // expired/error=red; never reused as decoration) ──────────────────
  static Color get success =>
      isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B); // same in both themes
  static Color get danger =>
      isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  static Color get info =>
      isDark ? const Color(0xFF38BDF8) : const Color(0xFF2563EB);

  // ── Urgency thresholds ────────────────────────────────────────────
  static ({Color fg, Color bg}) urgency(int days) {
    if (days <= 3) {
      return (fg: danger, bg: danger.withValues(alpha: 0.1));
    }
    if (days <= 7) {
      return (fg: warning, bg: warning.withValues(alpha: 0.1));
    }
    return (fg: success, bg: success.withValues(alpha: 0.1));
  }

  // ── Corner Radii ──────────────────────────────────────────────────
  static const double rBanner = 26;
  static const double rCard = 20;
  static const double rMetric = 20;
  static const double rChip = 12;
  static const double rField = 15;
  static const double rInput = 14;
  static const double rIconBtn = 14;
  static const double rAvatar = 15;
  static const double rFab = 20;
  static const double rNav = 22;
  static const double rPill = 20;
  static const double rSmallPill = 8;

  // ── Spacing ───────────────────────────────────────────────────────
  static const double padContent = 18;
  static const double padHeader = 22;
  static const double padCard = 14;
  static const double padBanner = 22;
  static const double gapItem = 11;
  static const double gapSection = 18;

  // ── Shadows ────────────────────────────────────────────────────────
  // Light: restrained — thin borders do most of the separation work.
  // Dark: the original design's heavier glow shadows.
  static BoxShadow cardShadow(Color accent) => isDark
      ? BoxShadow(
          color: accent.withValues(alpha: 0.18),
          blurRadius: 18,
          offset: const Offset(0, 8),
          spreadRadius: -8,
        )
      : BoxShadow(
          color: accent.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 6),
          spreadRadius: -6,
        );
}

class _CatDef {
  final Color base;
  final List<Color> gradient;
  final String icon;
  const _CatDef(this.base, this.gradient, this.icon);
}

/// A flat icon from assets/images/icons/flat, recolored to [color] via
/// srcIn — one asset works for any tint (active/inactive/muted) instead
/// of needing separate light/dark source files per state.
Widget flatIcon(String name, {required Color color, double size = 24}) {
  return ColorFiltered(
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    child: Image.asset(
      'assets/images/icons/flat/$name.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    ),
  );
}

/// A glossy hero-tier illustration from assets/images/icons/illustrations.
/// Used as-is (no tint) for onboarding, empty states, and bold background
/// moments — never for functional 20-24px UI per the asset hierarchy.
Widget heroIllustration(String name, {double? width, double? height}) {
  return Image.asset(
    'assets/images/icons/illustrations/$name.png',
    width: width,
    height: height,
    fit: BoxFit.contain,
  );
}

/// A category's full-colour icon (assets/images/icons/categories/), resolved
/// from the category name. Used as-is — these icons ship pre-tinted in their
/// category colour, unlike the monochrome flat/ set that [flatIcon] recolours.
Widget categoryIcon(String categoryName, {double size = 20}) {
  final icon = AppTokens.categories[categoryName]?.icon;
  if (icon == null) return SizedBox(width: size, height: size);
  return Image.asset(
    'assets/images/icons/categories/category_$icon.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    errorBuilder: (_, __, ___) =>
        Container(width: size, height: size, color: Colors.red),
  );
}

/// Gradient avatar widget (shared across all screens)
Widget gradientAvatar(String letter, Color color, {double size = 52}) {
  // Try to find the matching category
  List<Color> colors;
  for (final entry in AppTokens.categories.entries) {
    if (entry.value.base == color) {
      colors = entry.value.gradient;
      return _buildAvatar(letter, colors, size);
    }
  }
  colors = [color, color.withValues(alpha: 0.7)];
  return _buildAvatar(letter, colors, size);
}

Widget _buildAvatar(String letter, List<Color> colors, double size) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(AppTokens.rAvatar),
      boxShadow: [
        BoxShadow(
          color: colors.first.withValues(alpha: 0.45),
          blurRadius: 18,
          offset: const Offset(0, 8),
          spreadRadius: -8,
        ),
      ],
    ),
    child: Center(
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// Glass bottom nav bar
class GlassBottomNav extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onTap;
  final bool showOfferDot;
  const GlassBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    this.showOfferDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.rNav),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: AppTokens.navBg,
                border: Border.all(color: AppTokens.hairline, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: AppTokens.isDark ? 0.4 : 0.10,
                    ),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navItem(0, 'grid_dark', 'Library'),
                  _navItem(1, 'chart_trending_dark', 'Dashboard'),
                  _navItem(
                    3,
                    'tag_dark',
                    'Offers',
                    dot: showOfferDot && selectedIndex != 3,
                  ),
                  _navItem(2, 'settings_dark', 'Settings'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _navItem(
    int index,
    String iconAsset,
    String label, {
    bool dot = false,
  }) {
    final active = selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: active
                ? BoxDecoration(
                    gradient: AppTokens.brandGradient,
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            // FittedBox: with 4 tabs each item gets ~89dp on a 360dp screen;
            // the active item (icon + label + padding) can exceed that, so
            // scale down gracefully instead of overflowing.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      flatIcon(
                        iconAsset,
                        size: 18,
                        color: active
                            ? AppTokens.screenBg
                            : AppTokens.textFaint,
                      ),
                      if (active) const SizedBox(width: 6),
                      if (active)
                        Text(
                          label,
                          style: TextStyle(
                            color: AppTokens.screenBg,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  if (dot)
                    Positioned(
                      top: -2,
                      right: -6,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: AppTokens.brandStart,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
