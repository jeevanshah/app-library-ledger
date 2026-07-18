# App Ledger — DASHBOARD TAB — Flutter Build Spec (text-only)

Prereq: read `00_shared_tokens.md` (colors, type, sample data, GlassBottomNav).
This is the second tab of the main screen (same Scaffold as Library). Scrollable.
Background screenBg #0B0B11. Bottom: GlassBottomNav with "Dashboard" active +
(in production) an AdMob banner sitting ABOVE the nav.

Scroll content, screen padding 18 horizontal, section gap 18:

===============================================================================
## A. HEADER (padding 22 h, 6 top / 12 bottom)
===============================================================================
- eyebrow "APP LEDGER" over title "Dashboard" (Space Grotesk 25 w700 ls -0.5).
- right: a segmented range toggle pill (optional) — [ Month | Year ] , bg fieldBg,
  radius 12, active segment brandGradient. Default "Month".

===============================================================================
## B. 4 METRIC CARDS — 2x2 GRID
===============================================================================
GridView (2 columns, mainAxisSpacing 11, crossAxisSpacing 11, childAspectRatio ~1.35),
shrinkWrap, non-scrolling (parent scrolls).
Each tile: bg cardBg, radius 20, padding 16, 1px hairline border, Column:
  - top row: a 34x34 rounded-11 icon chip (tinted bg = accent 14%, icon = accent),
    plus (right) a tiny trend delta pill (e.g. "+4.2%") in success/danger.
  - value (gap 10): Space Grotesk 26 w700 ls -0.8, textPrimary, tabular.
  - label (gap 2): Plus Jakarta 12.5 w600, textMuted.

The 4 tiles (order + accent):
  1. Monthly Total   | value "$147.43" | label "This month"     | accent brandEnd #8B5CF6 | icon payments_rounded | delta "+4.2%" success
  2. Avg / App       | value "$18.43"  | label "Per subscription"| accent #06B6D4          | icon tag_rounded
  3. Active Subs     | value "8"       | label "Subscriptions"   | accent #34D399          | icon apps_rounded
  4. Yearly Proj.    | value "$1,769"  | label "Projected / yr"  | accent #F59E0B          | icon calendar_month_rounded
(Animate each value counting up from 0, staggered 60ms apart, ~900ms easeOutCubic.)

===============================================================================
## C. SPENDING BREAKDOWN — DONUT CARD  (glassmorphism)
===============================================================================
Card: bg cardBg (or a subtle white-6% glass over screenBg with BackdropFilter),
radius 26, padding 20, 1px hairline. Title row: "Spending by category"
(Plus Jakarta 15.5 w700) + right "This month" caption textFaint.

DONUT (fl_chart PieChart, centerSpaceRadius ~58, sectionsSpace 3, radius ~26):
  sections (color = category base, value = monthly $):
    Productivity      74.99  #6366F1  (50.9%)
    Media / Streaming 41.47  #EC4899  (28.1%)
    Shopping          14.99  #F59E0B  (10.2%)
    Health / Fitness  12.99  #10B981  ( 8.8%)
    Utilities          2.99  #06B6D4  ( 2.0%)
  Center overlay (Stack): "$147.43" Space Grotesk 22 w700 tabular over
    "per month" micro textMuted.
  Interaction: on section touch, expand that slice (+6 radius) and show its % in center.

LEGEND (below donut, gap 16): a 2-column wrap or Column of rows, one per category:
  Row: [ 10px rounded-3 color chip ] [ category name Plus Jakarta 13 w600 textPrimary ]
       [ spacer ] [ "$74.99" Space Grotesk 13 w700 tabular ] [ "50.9%" micro textFaint ].

===============================================================================
## D. HEALTH SCORE — RING GAUGE CARD
===============================================================================
Card bg cardBg radius 26 padding 20 hairline. Row layout:
  LEFT — circular gauge (CustomPaint or fl_chart): a 96px ring, track color
    #23232E (width 10), progress arc = 68% sweep, gradient stroke
    [ #F59E0B -> #F87171 ] (amber->red because score is low), rounded cap.
    Center: "68" Space Grotesk 26 w700 over "/100" micro textFaint.
  RIGHT (Expanded, gap 16):
    - "Health Score" Plus Jakarta 15.5 w700 textPrimary.
    - status pill "Needs Attention" — bg rgba(245,158,11,0.14), fg #F59E0B, radius 8.
    - one-line hint Plus Jakarta 12.5 w500 textMuted:
      "3 streaming apps overlap — trimming one could save ~$14/mo."
  Score bands: >=80 green "Great", 60-79 amber "Needs Attention", <60 red "At Risk".

===============================================================================
## E. SMART INSIGHTS CARD
===============================================================================
Card bg cardBg radius 26 padding 18 hairline. Title "Smart insights"
(Plus Jakarta 15.5 w700) + small sparkle/AI icon (auto_awesome_rounded) in brandEnd.
Then a Column of insight ROWS (gap 12), each row:
  [ 36x36 rounded-11 tinted icon chip ] [ Expanded 2-line text ] [ chevron_right faint ]
  text = title (Plus Jakarta 13.5 w700 textPrimary) over detail (12 w500 textMuted).

Insight rows (in order):
  1. icon payments_rounded / brandEnd tint
     "Monthly spend"  — "$147.43/mo · $1,769.16/year"
  2. icon event_upcoming_rounded / warning #F59E0B tint
     "3 renewals this week" — "$90.48 due — Netflix, ChatGPT, Adobe CC"
  3. icon content_copy_rounded / danger #F87171 tint
     "Possible duplicate" — "Media / Streaming: 3 apps, $41.47/mo. Consolidate?"
  4. icon trending_up_rounded / #EC4899 tint
     "Price increase soon" — "Adobe CC promo ends in 6 days"
  5. icon workspace_premium_rounded / success #34D399 tint
     "Most expensive" — "Adobe CC at $54.99/mo"

===============================================================================
## F. BOTTOM
===============================================================================
- (production) AdMob banner container height ~50, bg cardBg, hairline top, sitting
  just above the nav — text placeholder "Ad" centered if not loaded.
- GlassBottomNav with index=1 (Dashboard active).
- Ensure ~130 bottom padding on the scroll so content clears nav + banner.

===============================================================================
## ANIMATIONS
===============================================================================
- Metric values + donut sweep + gauge arc animate in on first build (staggered).
- Pull-to-refresh: RefreshIndicator that re-runs the count-up animations.

===============================================================================
## ACCEPTANCE
===============================================================================
[ ] 2x2 metric grid: $147.43, $18.43, 8, $1,769 — each with a tinted icon chip.
[ ] Donut with 5 category slices, center shows "$147.43 / per month", legend with $ + %.
[ ] Category $ in legend sum to $147.43; shares match (Productivity biggest at ~51%).
[ ] Health ring at 68/100, amber->red arc, "Needs Attention" pill.
[ ] 5 insight rows with correct icons, colors, and the exact copy above.
[ ] Glass bottom nav with Dashboard active; content clears the nav.
