import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_tokens.dart';

class _Page {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  const _Page(this.title, this.subtitle, this.icon, this.color);
}

const _pages = [
  _Page(
    'Know What You Actually Pay',
    'Every subscription and bill in one place — including promo prices, before they quietly reset.',
    Icons.receipt_long_rounded,
    AppTokens.gold,
  ),
  _Page(
    'Catch the Promo Cliff',
    'Get a heads-up 7 days and 1 day before a promo ends or a bill hits — before the price jumps on you.',
    Icons.hourglass_bottom_rounded,
    AppTokens.gold,
  ),
  _Page(
    'Compare Real Market Offers',
    'See live NBN and mobile plans from real providers, matched against what you pay. We show the data — you decide.',
    Icons.compare_arrows_rounded,
    AppTokens.gold,
  ),
  _Page(
    '100% Private',
    'Detection and matching happen entirely on your device. Your subscriptions never leave your phone.',
    Icons.lock_rounded,
    AppTokens.gold,
  ),
];

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _page = 0;
  late final AnimationController _bgCtrl;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _bgCtrl.forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _page = i);
    HapticFeedback.selectionClick();
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      HapticFeedback.mediumImpact();
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pages[_page];
    return Scaffold(
      backgroundColor: AppTokens.screenBg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip
            SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.topRight,
                child: _page == _pages.length - 1
                    ? const SizedBox.shrink()
                    : TextButton(
                        onPressed: widget.onComplete,
                        child: Text(
                          'Skip',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ),
            // Content
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: _onPageChanged,
                itemCount: _pages.length,
                itemBuilder: (_, i) {
                  final pg = _pages[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Glow + animated icon container
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 600),
                          tween: Tween(begin: 0.85, end: 1.0),
                          curve: Curves.easeOutBack,
                          builder: (_, v, child) => Transform.scale(
                            scale: v,
                            child: Transform.rotate(
                              angle: (v - 1.0) * 0.15,
                              child: child,
                            ),
                          ),
                          child: SizedBox(
                            width: 260,
                            height: 260,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 260,
                                  height: 260,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        pg.color.withValues(alpha: 0.22),
                                        pg.color.withValues(alpha: 0.0),
                                      ],
                                    ),
                                  ),
                                ),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(31),
                                  child: Image.asset(
                                    'assets/images/logo.png',
                                    width: 140,
                                    height: 140,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          pg.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.playfairDisplay(
                            color: AppTokens.textStrong,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            pg.subtitle,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTokens.textMuted,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Dots + Button
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 30),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _page == i ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _page == i ? p.color : const Color(0xFF2A2A36),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            p.color,
                            Color.lerp(p.color, Colors.white, 0.18)!,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: p.color.withValues(alpha: 0.4),
                            blurRadius: 30,
                            offset: const Offset(0, 16),
                            spreadRadius: -10,
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _next,
                          child: Center(
                            child: Text(
                              _page == _pages.length - 1
                                  ? 'Get Started'
                                  : 'Continue',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 16,
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
            ),
          ],
        ),
      ),
    );
  }
}
