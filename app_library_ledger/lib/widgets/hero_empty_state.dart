import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_tokens.dart';

/// Reusable empty-state block: a glossy hero illustration, Playfair title,
/// supporting subtitle, an optional brand-gradient CTA and an optional
/// underline link. One component so empty states stop drifting apart and
/// stop hardcoding Playfair/gold decisions independently.
class HeroEmptyState extends StatelessWidget {
  final String illustration;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final String? linkLabel;
  final VoidCallback? onLink;
  final double illustrationSize;
  final bool compact;
  final bool center;

  const HeroEmptyState({
    super.key,
    required this.illustration,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.linkLabel,
    this.onLink,
    this.illustrationSize = 96,
    this.compact = false,
    this.center = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppTokens.padCard : AppTokens.padContent,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          heroIllustration(
            illustration,
            width: illustrationSize,
            height: illustrationSize,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              color: AppTokens.textStrong,
              fontSize: compact ? 17 : 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              color: AppTokens.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppTokens.brandGradient,
                  borderRadius: BorderRadius.circular(AppTokens.rInput),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTokens.rInput),
                    onTap: onCta,
                    child: Center(
                      child: Text(
                        ctaLabel!,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTokens.screenBg,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (linkLabel != null && onLink != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onLink,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  linkLabel!,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: AppTokens.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return center ? Center(child: content) : content;
  }
}
