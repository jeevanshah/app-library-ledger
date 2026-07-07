import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_tokens.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final AnimationController _textCtrl;
  late final AnimationController _ringCtrl;
  late final Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppTokens.screenBg,
      ),
    );

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _logoScale = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic);

    _logoCtrl.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _textCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _ringCtrl.repeat();
    });
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppTokens.screenBg,
      ),
      child: Scaffold(
        backgroundColor: AppTokens.screenBg,
        body: Stack(
          children: [
            // Subtle radial glow behind logo
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTokens.brandStart.withValues(alpha: 0.06),
                        AppTokens.screenBg.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Faint ripple rings
            AnimatedBuilder(
              animation: _ringCtrl,
              builder: (_, __) => CustomPaint(
                size: Size.infinite,
                painter: _RingPainter(_ringCtrl.value),
              ),
            ),
            // Center content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo mark
                  ScaleTransition(
                    scale: Tween(begin: 0.92, end: 1.0).animate(_logoScale),
                    child: Opacity(
                      opacity: _logoCtrl.value,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: AppTokens.cardBg,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: AppTokens.hairlineStrong,
                            width: 1,
                          ),
                        ),
                        child: ShaderMask(
                          shaderCallback: (bounds) =>
                              AppTokens.goldGradient.createShader(bounds),
                          child: const Icon(
                            Icons.subscriptions_rounded,
                            size: 46,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Label + wordmark + tagline
                  AnimatedBuilder(
                    animation: _textCtrl,
                    builder: (_, child) =>
                        Opacity(opacity: _textCtrl.value, child: child),
                    child: Column(
                      children: [
                        Text(
                          'EVERY DOLLAR ACCOUNTED FOR',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'App Ledger',
                          style: GoogleFonts.playfairDisplay(
                            color: AppTokens.textStrong,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Track. Save. Thrive.',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTokens.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  static const double _startRadius = 80;
  static const double _endRadius = 200;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 0; i < 3; i++) {
      final phase = (progress + i * 0.33) % 1.0;
      final eased = Curves.easeOutCubic.transform(phase);
      final radius = _startRadius + eased * (_endRadius - _startRadius);
      final opacity = 0.10 * (1 - eased);

      canvas.drawCircle(
        center,
        radius,
        paint..color = AppTokens.gold.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => progress != old.progress;
}
