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
    'Know Your Spend',
    'See every subscription and your true monthly total in one clean view.',
    Icons.insights_rounded,
    Color(0xFF38BDF8),
  ),
  _Page(
    'Never Miss a Renewal',
    'Get a heads-up 7 days and 1 day before anything bills you again.',
    Icons.notifications_active_rounded,
    Color(0xFF06B6D4),
  ),
  _Page(
    'Save Smarter',
    'Spot duplicates and waste with a health score that tells you where to cut.',
    Icons.savings_rounded,
    Color(0xFF10B981),
  ),
  _Page(
    '100% Private',
    'Your data is yours. Detection runs entirely on-device. Your subscriptions never leave your phone.',
    Icons.lock_rounded,
    Color(0xFFEC4899),
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
                  final lighter = Color.lerp(pg.color, Colors.white, 0.18)!;
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
                                Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [pg.color, lighter],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(36),
                                    boxShadow: [
                                      BoxShadow(
                                        color: pg.color.withValues(alpha: 0.45),
                                        blurRadius: 40,
                                        offset: const Offset(0, 18),
                                        spreadRadius: -12,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    pg.icon,
                                    size: 62,
                                    color: Colors.white,
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
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTokens.textStrong,
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
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
