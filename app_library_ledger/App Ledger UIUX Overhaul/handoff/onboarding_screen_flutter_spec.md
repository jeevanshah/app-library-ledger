# App Ledger — ONBOARDING — Flutter Build Spec (text-only)

Prereq: read `00_shared_tokens.md`.
4 pages, first launch only, horizontally swipeable (PageView). Skippable.

DESIGN DECISION: to stay consistent with the premium DARK app, onboarding pages
are dark (screenBg #0B0B11) with a large per-page ACCENT color used for the icon
gradient + a soft radial GLOW behind it. (This replaces the original "each page a
light pastel background" idea, which would clash with the dark app.)

===============================================================================
## PER-PAGE CONTENT + ACCENT
===============================================================================
Page 1 — accent #38BDF8 (sky/blue)
  icon: Icons.insights_rounded (or bar_chart_rounded)
  title: "Know Your Spend"
  body: "See every subscription and your true monthly total in one clean view."
Page 2 — accent #06B6D4 (cyan)
  icon: Icons.notifications_active_rounded
  title: "Never Miss a Renewal"
  body: "Get a heads-up 7 days and 1 day before anything bills you again."
Page 3 — accent #10B981 (green)
  icon: Icons.savings_rounded (or trending_down_rounded)
  title: "Save Smarter"
  body: "Spot duplicates and waste with a health score that tells you where to cut."
Page 4 — accent #EC4899 (pink)
  icon: Icons.lock_rounded (or shield_rounded)
  title: "100% Private"
  body: "All your data lives on your device. No account, no cloud, no tracking."

===============================================================================
## PAGE LAYOUT (same for all 4; only accent/icon/copy change)
===============================================================================
Column, centered, screen padding 28 horizontal:

TOP BAR (row, space-between, top 12):
  - left: empty spacer (or a subtle page number "01 / 04" micro textFaint)
  - right: "Skip" TextButton, Plus Jakarta 14 w600, color textMuted
    (hidden on page 4; replaced by nothing). Tapping Skip -> Library.

CENTER (Expanded, centered):
  1. GLOW: a soft radial gradient circle ~260px, color = accent at ~22% ->
     transparent, sitting behind the icon container (use a Container with
     RadialGradient or a blurred circle).
  2. ICON CONTAINER: 140x140, radius 36, gradient = [accent, lighter accent]
     (use the 2-stop pattern like category gradients — e.g. accent -> accent
     lightened ~18%), centered white icon 62px, soft accent shadow
     (accent 45%, blur 40, y18, spread -12).
     - Micro-animation on page enter: scale 0.85 -> 1.0 + a gentle 3° tilt
       settle, ~600ms easeOutBack; icon can also do a tiny bounce.
  3. TITLE (gap 34): Space Grotesk 27 w700 ls -0.5, textStrong, centered.
  4. BODY (gap 12): Plus Jakarta 15 w500, textMuted, centered, max width ~300,
     line height 1.5, textAlign center, text-wrap balance feel.

BOTTOM ZONE (padding bottom 30):
  - PAGE DOTS (row centered, gap 8): 4 dots. Active dot = a 22x8 rounded-4 pill
    in the CURRENT page's accent color; inactive dots = 8x8 circles, color
    #2A2A36. Animate width/color on page change (~250ms).
  - CTA BUTTON (gap 24): full-width PrimaryButton, but tinted with the CURRENT
    page accent instead of brand (gradient [accent, lighter accent], accent glow).
      * Pages 1-3 label: "Continue"  -> PageController.nextPage(300ms, easeInOut)
      * Page 4 label: "Get Started"  -> mark onboarding done, route to Library
        (FadeThrough).

===============================================================================
## BEHAVIOR
===============================================================================
- PageView with physics; swipe advances pages and the accent/dots/button retint.
- Parallax (optional): icon translates slightly slower than the page during swipe.
- HapticFeedback.selectionClick() on each page settle.
- Persist a bool `onboardingDone=true` (SharedPreferences) so it shows once.

===============================================================================
## ACCEPTANCE
===============================================================================
[ ] 4 swipeable pages, dark bg, each with its own accent (blue/cyan/green/pink).
[ ] 140x140 gradient icon container with a soft accent glow behind it.
[ ] Titles in Space Grotesk, bodies muted + centered.
[ ] Active page dot is an elongated pill in the page accent; others small circles.
[ ] CTA button retints per page; page 4 says "Get Started" and finishes onboarding.
[ ] "Skip" in the top-right on pages 1-3.
