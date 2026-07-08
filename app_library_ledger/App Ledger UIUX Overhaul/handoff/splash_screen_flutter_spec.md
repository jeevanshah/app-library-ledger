# App Ledger — SPLASH SCREEN — Flutter Build Spec (text-only)

Prereq: read `00_shared_tokens.md`. Uses brand colors + Space Grotesk.
Duration: ~2000ms, then navigate to Onboarding (first launch) or Library.

===============================================================================
## LAYOUT
===============================================================================
Full-bleed screen, NO app bar, NO nav.
Background: LinearGradient top->bottom, colors [ #6366F1, #8B5CF6 ]
  (brand purple; this is the ONE bright screen — everything after is dark).
Everything centered in the middle of the screen.

Center stack (aligned center):
1. EXPANDING RING RIPPLES (behind the icon): 3 concentric circles, white,
   drawn with a CustomPainter or 3 stacked AnimatedContainers. Each ring:
   - starts at diameter ~120, scales to ~320
   - opacity fades 0.35 -> 0.0 as it expands
   - staggered start (ring 2 delayed ~400ms, ring 3 ~800ms), loops.
   - strokeWidth ~2, color white.
2. APP ICON CONTAINER: 96x96, radius 28, bg white 16% over a subtle white
   border (1.5px white 30%), centered Material icon `Icons.subscriptions_rounded`
   (or `Icons.receipt_long_rounded`), 46px, white.
   - Entrance: elastic scale-in — AnimationController 900ms,
     Curves.elasticOut, Tween<double>(0.4 -> 1.0) on scale, opacity 0->1 first 200ms.
3. TITLE (below icon, gap 22): "App Ledger", Space Grotesk 30 w700, ls -0.5, white.
4. TAGLINE (gap 6): "Track. Save. Thrive.", Plus Jakarta 14 w600,
   white 82%, letterSpacing 0.5.
   - Title+tagline slide UP into place: translateY 18 -> 0 + opacity 0 -> 1,
     700ms easeOutCubic, starting ~300ms after the icon.

Optional footer (bottom 40, centered): tiny "v1.0" Plus Jakarta 11 w500 white 55%.

===============================================================================
## TIMELINE
===============================================================================
0ms     screen shows purple gradient
0-900   icon elastic scale-in; ring ripples begin looping
300-1000 title + tagline slide up + fade in
2000    fade/shared-axis transition to next screen (FadeThrough ~350ms)

===============================================================================
## ACCEPTANCE
===============================================================================
[ ] Full purple gradient background (#6366F1 -> #8B5CF6).
[ ] Icon pops with an elastic overshoot (not a plain fade).
[ ] At least one expanding, fading white ring behind the icon, looping.
[ ] Title in Space Grotesk, tagline "Track. Save. Thrive." below.
[ ] Auto-advances after ~2s with a fade transition (no manual tap needed).
