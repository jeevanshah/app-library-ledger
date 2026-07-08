import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/offer.dart';
import '../services/offers_matcher.dart';
import '../theme/app_tokens.dart';

class OffersScreen extends StatelessWidget {
  final List<MatchedOffer> matches;

  const OffersScreen({super.key, required this.matches});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dateFmt = DateFormat('MMM d');

    return Scaffold(
      backgroundColor: AppTokens.screenBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTokens.fieldBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTokens.hairline),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Color(0xFFC9C9D6),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Savings Offers',
                    style: GoogleFonts.playfairDisplay(
                      color: AppTokens.textStrong,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'Matched to what you already track — your data never leaves your device.',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                itemCount: matches.length,
                itemBuilder: (_, i) {
                  final m = matches[i];
                  final o = m.offer;
                  final totalCost = o.promoPrice * o.promoMonths;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTokens.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTokens.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.provider,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          o.title,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          o.description,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _stat('Promo', '${fmt.format(o.promoPrice)}/mo'),
                            const SizedBox(width: 16),
                            _stat('Then', '${fmt.format(o.regularPrice)}/mo'),
                            const SizedBox(width: 16),
                            _stat(
                              'Length',
                              '${o.promoMonths} month${o.promoMonths == 1 ? '' : 's'}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _stat('Total cost', fmt.format(totalCost)),
                            const SizedBox(width: 16),
                            _stat('You save', fmt.format(m.savingsOverPromo)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              'Offer ends ${dateFmt.format(o.validUntil)}',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTokens.textFaint,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Affiliate link',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTokens.textFaint,
                                fontSize: 9,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppTokens.goldGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => launchUrl(
                                  Uri.parse(o.url),
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: Center(
                                  child: Text(
                                    'View offer',
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
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(
                'Prices verified at time of listing. Always confirm current pricing with the provider.',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTokens.textFaint,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: AppTokens.textFaint,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: GoogleFonts.spaceGrotesk(
          color: AppTokens.textPrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}
