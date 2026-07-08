# App Ledger — Library Screen — Flutter Build Spec (text-only)

Build the **Library (main) screen** of a subscription-tracking app in Flutter 3.9+ (Material 3),
dark theme. Reproduce EXACTLY the values below. Do not invent colors, sizes, or spacing.
This is a single scrollable screen with a pinned status bar, a pinned bottom nav, and a
floating action button. All numbers are logical pixels (dp).

===============================================================================
## 0. DESIGN TOKENS (define these as constants)
===============================================================================

### Colors
- screenBg            = #0B0B11   (near-black app background)
- cardBg              = #14141C   (subscription card background)
- fieldBg             = #15151D   (search + chip + icon-button background)
- navBg               = 0xD1181820  (rgba(24,24,32,0.82) — frosted nav bar)
- textPrimary         = #F2F2F8
- textStrong          = #F6F6FB
- textMuted           = #7C7C92
- textFaint           = #6B6B82
- textPlaceholder     = #5C5C72
- hairline            = 0x0DFFFFFF  (rgba(255,255,255,0.05) — 1px inset borders)

### Brand gradient (used on banner, FAB, "JD" avatar, active nav pill, "All" chip)
- brandGradient = LinearGradient(
    begin: topLeft(150°-ish), end: bottomRight,
    colors: [ #6366F1, #8B5CF6 ])
  For the big summary banner use 3 stops:
  colors: [ #6D5BF5 (0.0), #8B5CF6 (0.46), #A855C9 (1.0) ]

### Category colors + per-category gradients (leading avatar)
- Media / Streaming : base #EC4899 ; gradient [#EC4899, #F472B6]
- Productivity      : base #6366F1 ; gradient [#6366F1, #8B5CF6]
- Utilities         : base #06B6D4 ; gradient [#06B6D4, #22D3EE]
- Shopping          : base #F59E0B ; gradient [#F59E0B, #FBBF24]
- Health / Fitness  : base #10B981 ; gradient [#10B981, #34D399]

### Urgency colors (based on days until next renewal)
- days <= 3  : fg #F87171 , bg rgba(248,113,113,0.14) , label "Renews in N day(s)"
- days <= 7  : fg #F59E0B , bg rgba(245,158,11,0.14)  , label "Renews in N days"
- else       : fg #34D399 , bg rgba(52,211,153,0.12)  , label "Renews in N days"

### Typography
- Use TWO Google fonts (google_fonts package):
  - "Space Grotesk"  -> ALL numbers, the big total, screen title, avatar letters,
                        card prices, nav labels feel. (display / numeric font)
  - "Plus Jakarta Sans" -> all other UI text (labels, category names, body).
- Enable tabular figures on every money value:
    fontFeatures: [FontFeature.tabularFigures()]
- Key text styles:
  - Eyebrow "APP LEDGER": 12sp, w600, letterSpacing 1.5, uppercase, color textFaint
  - Screen title "Your Library": Space Grotesk, 25sp, w700, letterSpacing -0.5, textStrong
  - Banner label "Monthly spend": 12.5sp, w600, white 82%
  - Banner total "$147.43": Space Grotesk, 44sp, w700, letterSpacing -1.5, height 1.0, white, tabular
  - Card name: 15.5sp, w700, textPrimary
  - Card category: 12sp, w500, textMuted
  - Card price: Space Grotesk, 17sp, w700, textPrimary, tabular
  - Card cycle "/mo": 11sp, w600, textFaint
  - Chip label: 13sp, w600 ; chip count: 11sp, w600, opacity 0.7
  - Urgency pill text: 11sp, w600
  - Nav label: 10.5sp (active w700, inactive w600)

### Radii
- Phone/card outer feel: cards 20, banner 26, chips 12, search field 15,
  icon buttons 14, FAB 20, nav bar 22, avatar 15 (leading), category avatar 15.

### Spacing
- Screen horizontal padding: 18 for banner/list/chips, 22 for header/status/nav.
- Vertical gaps: banner bottom margin 18, search row bottom 14, chips row bottom 18,
  list item gap 11.
- List bottom padding: 130 (so FAB + nav don't cover last card).

===============================================================================
## 1. DATA MODEL (for the sample list)
===============================================================================

class Sub {
  final String name;         // "Netflix"
  final String category;     // full category name e.g. "Media / Streaming"
  final double price;        // 15.49
  final String cycle;        // "/mo"
  final int days;            // days until renewal
  final bool promo;          // shows amber "PROMO" badge
}

Sample list (render in THIS order):
1. Netflix      | Media / Streaming | 15.49 | days 2  | promo false
2. ChatGPT Plus | Productivity      | 20.00 | days 5  | promo false
3. Adobe CC     | Productivity      | 54.99 | days 6  | promo TRUE
4. Spotify      | Media / Streaming | 11.99 | days 12 | promo false
5. iCloud+      | Utilities         |  2.99 | days 18 | promo false
6. Amazon Prime | Shopping          | 14.99 | days 21 | promo false
7. Headspace    | Health / Fitness  | 12.99 | days 24 | promo false
8. Disney+      | Media / Streaming | 13.99 | days 28 | promo false

- Monthly total = sum of prices = 147.43
- Active count = 8
- Leading avatar letter = first character of name (uppercase).

Category chips (horizontal, in order): All(8), Media(3), Productivity(2),
Utilities(1), Health(1), Shopping(1). "All" is selected by default.

6-month trend values (Feb..Jul), used only for the mini bar chart heights:
[139, 144, 133, 152, 141, 147]. Last bar (Jul) is the "current" one.

===============================================================================
## 2. SCREEN STRUCTURE (top to bottom)
===============================================================================

Scaffold(backgroundColor: screenBg)
  body: a CustomScrollView OR SingleChildScrollView with:

(A) STATUS BAR ROW — you can skip this if using the real device status bar; the mock
    shows "9:41" left, signal/wifi/battery right. In production use SafeArea instead.

(B) HEADER ROW  (padding 22 horizontal, 6 top / 12 bottom)
    - Left column: eyebrow "APP LEDGER" over title "Your Library".
    - Right: two 42x42 buttons, radius 14, gap 10:
        * hamburger icon button, bg fieldBg, icon color #C9C9D6, 1px hairline inset border.
        * "JD" avatar button, brandGradient bg, white text, Space Grotesk 15sp w700.

(C) SUMMARY BANNER  (margin: 0 18; radius 26; padding: 22 22 18 22; brandGradient 3-stop;
    boxShadow: color rgba(124,92,246,0.75), blur 44, offset (0,24), spread -20)
    Contents:
    - Decorative soft white radial circle in top-right corner (optional; ~180px, low opacity).
    - Row (space-between, cross-start):
        Left column:
          * "Monthly spend" label
          * BIG TOTAL: animate from $0.00 -> $147.43 over ~1100ms, easeOutCubic,
            formatted "$#,##0.00" (intl NumberFormat), tabular figures. Use
            AnimatedBuilder + AnimationController + Tween<double>.
          * Row of two pills (gap 8, marginTop 10), each: bg white 18%, radius 20,
            padding 4x10, 11.5sp w600 white, single line (no wrap):
              - "• 8 active"  (leading 6px white dot)
              - "↑ 4.2%"
        Right: a 38x38 chevron-right button, bg white 20%, radius 13 (navigates to Dashboard tab).
    - MINI BAR CHART (marginTop 16): a Row, height 40, 6 columns, gap 7.
        Each column = a bottom-aligned Column: [ bar, 5px gap, month label ].
        Bar: width = full column width, radius 5, height = mapped px in range 11..34
          via: h = 11 + ((v - min) / (max - min)) * 23   (min=133, max=152).
          Fill: last column (Jul) white 95%; all others white 34%.
        Month label: 9sp w600 white 60%.
        Bars grow from bottom with a 600ms scaleY 0->1 animation (optional flourish).

(D) SEARCH ROW  (padding 0 18; bottom 14; Row gap 10)
    - Expanded search field: height 46, bg fieldBg, radius 15, 1px hairline inset,
      padding 0 14, Row [ search icon #6B6B82 17px, 10 gap, placeholder text
      "Search subscriptions" 14sp w500 color textPlaceholder ].
    - Trailing 46x46 grid/list toggle icon button, bg fieldBg, radius 15, icon #C9C9D6
      (4-square grid icon).

(E) CATEGORY CHIPS  (horizontal scroll, padding 0 18; bottom 18; gap 9)
    Each chip: height 36, radius 12, padding 0 15, Row [ 8px colored dot , 7 gap ,
      name , 7 gap , count ].
    - Selected chip ("All"): brandGradient bg, white text, dot #8B5CF6,
      boxShadow rgba(124,92,246,0.8) blur 18 offset(0,8) spread -8.
    - Unselected chips: bg fieldBg, text #C9C9D6, dot = that category's base color,
      1px hairline inset border, no shadow.

(F) SUBSCRIPTION LIST  (padding 0 18; bottom 130; Column, item gap 11)
    Each card: Stack/Container, bg cardBg, radius 20, padding 14, 1px hairline inset border,
      clipped (overflow hidden). Layout = Row (cross-center, gap 14):
      - LEFT ACCENT: a 3px-wide vertical bar pinned to the card's left edge, full height,
        color = category base color. (Positioned.fill left strip inside a Stack, or a
        Container(width:3) as first row child with negative-ish alignment — simplest is
        a Stack with a left-aligned Container(width:3).)
      - LEADING AVATAR: 52x52, radius 15, category gradient, centered letter
        (Space Grotesk 22sp w700 white), soft colored shadow (category color, blur ~18, y8, spread -8).
      - MIDDLE (Expanded):
          * Row: name (15.5 w700) + optional PROMO badge.
              PROMO badge: 9.5sp w700 uppercase letterSpacing 0.4, fg #F59E0B,
              bg rgba(245,158,11,0.16), padding 2x6, radius 6.
          * Row (marginTop 5, gap 7): 7px category dot + full category name (12sp w500 textMuted).
          * Urgency pill (marginTop 8, inline, radius 8, padding 3x8): bg = urgency bg,
              Row [ 6px dot (urgency fg) , 5 gap , label (11sp w600 urgency fg) ].
      - RIGHT (trailing, right-aligned): price (Space Grotesk 17 w700 tabular) over
          cycle "/mo" (11sp w600 textFaint, marginTop 2).
    Recommended interaction (optional): wrap each card in Dismissible — swipe left =
      red delete background, swipe right = edit.

(G) FLOATING ACTION BUTTON
    - 60x60, radius 20, brandGradient, white "+" icon (strokeWidth ~2.4, 26px),
      shadow rgba(124,92,246,0.8) blur 30 offset(0,16) spread -10, plus a subtle
      inset top highlight. Position: bottom-right, sitting ABOVE the nav bar
      (in the mock: right 22, bottom 104). Use Scaffold.floatingActionButton with
      custom padding, or a Stack.

(H) BOTTOM NAV  (pinned; padding 12 22 22; gradient fade from transparent to screenBg behind it)
    - A pill bar: height 64, radius 22, bg navBg with BackdropFilter blur 18
      (ImageFilter.blur sigma ~18), 1px hairline inset border, top shadow.
    - Two items spaced around:
        * Library (active): a 44x32 rounded-12 brandGradient pill containing the grid icon
          (white), label "Library" 10.5sp w700 white below.
        * Dashboard (inactive): grid/chart icon 20px color textFaint, label "Dashboard"
          10.5sp w600 textFaint.

===============================================================================
## 3. ANIMATIONS
===============================================================================
- Total counter: AnimationController(duration 1100ms), CurvedAnimation easeOutCubic,
  Tween<double>(0 -> 147.43); rebuild text each tick via AnimatedBuilder.
- Banner + first cards: optional slide-up + fade (translateY 14 -> 0, opacity 0 -> 1,
  ~500ms) on first build.
- Bars: optional scaleY 0 -> 1 from bottom, ~600ms, cubic(0.2,0.8,0.3,1).
- Add haptic feedback (HapticFeedback.selectionClick) on chip tap and card tap.

===============================================================================
## 4. HELPERS
===============================================================================
String renewLabel(int days) {
  return "Renews in $days day${days == 1 ? '' : 's'}";
}
({Color fg, Color bg}) urgencyOf(int days) {
  if (days <= 3) return (fg: Color(0xFFF87171), bg: Color(0x24F87171));
  if (days <= 7) return (fg: Color(0xFFF59E0B), bg: Color(0x24F59E0B));
  return (fg: Color(0xFF34D399), bg: Color(0x1F34D399));
}
// Money: NumberFormat.currency(locale:'en_US', symbol: '\$', decimalDigits: 2)

===============================================================================
## 5. ACCEPTANCE CHECKLIST
===============================================================================
[ ] Background is #0B0B11, not pure black.
[ ] Total animates $0.00 -> $147.43 and rests at $147.43 with tabular figures.
[ ] Banner uses the 3-stop purple gradient + soft purple drop shadow.
[ ] 6 trend bars visible, Jul bar is white, others translucent, varying heights.
[ ] Each card shows a 3px left accent in its category color + gradient letter avatar.
[ ] Urgency pill color matches the day thresholds (Netflix=red, ChatGPT/Adobe=amber, rest=green).
[ ] Adobe CC shows the amber PROMO badge.
[ ] Chips: "All" is the gradient/selected style; others are dark with a colored dot.
[ ] Bottom nav is frosted (blur) with the Library item in a gradient pill.
[ ] FAB is a rounded-square gradient "+" floating above the nav.
[ ] Space Grotesk on all numbers/title; Plus Jakarta Sans elsewhere.

### Packages
google_fonts, intl. (Optional: flutter_animate for the entrance flourishes.)
