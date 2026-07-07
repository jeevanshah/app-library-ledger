import 'dart:ui';
import 'package:flutter/material.dart';

/// App Ledger — Shared Design Tokens
/// Based on the handoff spec: 00_shared_tokens.md
abstract class AppTokens {
  // ── Surfaces ──────────────────────────────────────────────────────
  static const Color screenBg = Color(0xFF0B0B11);
  static const Color cardBg = Color(0xFF14141C);
  static const Color fieldBg = Color(0xFF15151D);
  static const Color cardBgRaised = Color(0xFF17171F);
  static const Color navBg = Color(0xD1181820);
  static const Color hairline = Color(0x0DFFFFFF);
  static const Color hairlineStrong = Color(0x14FFFFFF);

  // ── Text ──────────────────────────────────────────────────────────
  static const Color textStrong = Color(0xFFF6F6FB);
  static const Color textPrimary = Color(0xFFF2F2F8);
  static const Color textMuted = Color(0xFF7C7C92);
  static const Color textFaint = Color(0xFF6B6B82);
  static const Color textPlaceholder = Color(0xFF5C5C72);

  // ── Brand ─────────────────────────────────────────────────────────
  static const Color brandStart = Color(0xFF6366F1);
  static const Color brandEnd = Color(0xFF8B5CF6);
  static const Color brandMid = Color(0xFFA855C9);

  // ── Gold accent (luxury ledger) ──────────────────────────────────
  static const Color gold = Color(0xFFC8A96E);
  static const Color goldLight = Color(0xFFD4BC8B);
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC8A96E), Color(0xFFDFC896)],
  );
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandStart, brandEnd],
  );
  static const LinearGradient brandGradient3 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6D5BF5), Color(0xFF8B5CF6), Color(0xFFA855C9)],
    stops: [0.0, 0.46, 1.0],
  );
  static BoxShadow get brandGlowShadow => BoxShadow(
    color: const Color(0xBF7C5CF6),
    blurRadius: 44,
    offset: const Offset(0, 24),
    spreadRadius: -20,
  );

  // ── Category Palette ──────────────────────────────────────────────
  static const Map<String, _CatDef> categories = {
    'Productivity': _CatDef(Color(0xFF6366F1), [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
    ]),
    'Media / Streaming': _CatDef(Color(0xFFEC4899), [
      Color(0xFFEC4899),
      Color(0xFFF472B6),
    ]),
    'Utilities': _CatDef(Color(0xFF06B6D4), [
      Color(0xFF06B6D4),
      Color(0xFF22D3EE),
    ]),
    'Shopping': _CatDef(Color(0xFFF59E0B), [
      Color(0xFFF59E0B),
      Color(0xFFFBBF24),
    ]),
    'Health / Fitness': _CatDef(Color(0xFF10B981), [
      Color(0xFF10B981),
      Color(0xFF34D399),
    ]),
    'Finance': _CatDef(Color(0xFF22C55E), [
      Color(0xFF22C55E),
      Color(0xFF4ADE80),
    ]),
    'Notes / Journaling': _CatDef(Color(0xFFA855F7), [
      Color(0xFFA855F7),
      Color(0xFFC084FC),
    ]),
    'Social': _CatDef(Color(0xFF3B82F6), [
      Color(0xFF3B82F6),
      Color(0xFF60A5FA),
    ]),
    'Education': _CatDef(Color(0xFFEAB308), [
      Color(0xFFEAB308),
      Color(0xFFFACC15),
    ]),
    'Travel': _CatDef(Color(0xFF14B8A6), [
      Color(0xFF14B8A6),
      Color(0xFF2DD4BF),
    ]),
  };

  static Color categoryColor(String name) =>
      categories[name]?.base ?? Colors.grey;
  static List<Color> categoryGradient(String name) =>
      categories[name]?.gradient ?? [Colors.grey, Colors.grey.shade400];

  // ── Semantic ──────────────────────────────────────────────────────
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFF87171);
  static const Color info = Color(0xFF38BDF8);

  // ── Urgency thresholds ────────────────────────────────────────────
  static ({Color fg, Color bg}) urgency(int days) {
    if (days <= 3)
      return (fg: const Color(0xFFF87171), bg: const Color(0x24F87171));
    if (days <= 7)
      return (fg: const Color(0xFFF59E0B), bg: const Color(0x24F59E0B));
    return (fg: const Color(0xFF34D399), bg: const Color(0x1F34D399));
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

  // ── Shadows ───────────────────────────────────────────────────────
  static BoxShadow cardShadow(Color accent) => BoxShadow(
    color: accent.withValues(alpha: 0.18),
    blurRadius: 18,
    offset: const Offset(0, 8),
    spreadRadius: -8,
  );
}

class _CatDef {
  final Color base;
  final List<Color> gradient;
  const _CatDef(this.base, this.gradient);
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
  final Widget? adBanner;
  const GlassBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    this.adBanner,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (adBanner != null) adBanner!,
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
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navItem(0, Icons.grid_view_rounded, 'Library'),
                  _navItem(1, Icons.show_chart_rounded, 'Dashboard'),
                  _navItem(2, Icons.settings_rounded, 'Settings'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final active = selectedIndex == index;
    // Expanded + opaque hit-testing: each item owns a full third of the
    // bar at full height, so taps register anywhere in its zone — not
    // just on the icon's painted pixels.
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Center(
          child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: active
            ? BoxDecoration(
                gradient: AppTokens.brandGradient,
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? Colors.white : AppTokens.textFaint,
            ),
            if (active) const SizedBox(width: 6),
            if (active)
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
          ),
        ),
      ),
    );
  }
}
