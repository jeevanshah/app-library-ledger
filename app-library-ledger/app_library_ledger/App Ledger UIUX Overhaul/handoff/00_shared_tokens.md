# App Ledger — SHARED DESIGN TOKENS (paste once, applies to ALL screens)

Flutter 3.9+, Material 3, dark theme. All screens share this foundation.
Define these as constants (e.g. an `AppTokens` class) and reuse everywhere.
All numbers are logical pixels (dp).

===============================================================================
## COLORS
===============================================================================
### Surfaces
- screenBg        = #0B0B11   (near-black app background — NOT pure black)
- cardBg          = #14141C   (cards)
- fieldBg         = #15151D   (search / chips / inputs / icon buttons)
- cardBgRaised    = #17171F   (secondary buttons, metric tiles base)
- navBg           = 0xD1181820  (rgba(24,24,32,0.82) frosted nav)
- hairline        = 0x0DFFFFFF  (rgba(255,255,255,0.05) 1px inset borders)
- hairlineStrong  = 0x14FFFFFF  (rgba(255,255,255,0.08))

### Text
- textStrong      = #F6F6FB
- textPrimary     = #F2F2F8
- textMuted        = #7C7C92
- textFaint        = #6B6B82
- textPlaceholder = #5C5C72
- eyebrow         = #6B6B82

### Brand
- brandStart = #6366F1  (indigo)
- brandEnd   = #8B5CF6  (violet)
- brandGradient = LinearGradient(begin: topLeft, end: bottomRight,
    colors: [brandStart, brandEnd])
- brandGradient3 (banners) = colors: [ #6D5BF5(0.0), #8B5CF6(0.46), #A855C9(1.0) ]
- brandGlowShadow = BoxShadow(color: rgba(124,92,246,0.75), blurRadius: 44,
    offset: (0,24), spreadRadius: -20)

### Category palette  (base color + 2-stop avatar gradient)
- Productivity      : #6366F1  | [#6366F1, #8B5CF6]
- Media / Streaming : #EC4899  | [#EC4899, #F472B6]
- Utilities         : #06B6D4  | [#06B6D4, #22D3EE]
- Shopping          : #F59E0B  | [#F59E0B, #FBBF24]
- Health / Fitness  : #10B981  | [#10B981, #34D399]
- Finance           : #22C55E  | [#22C55E, #4ADE80]   (extra defaults below)
- Notes / Journaling: #A855F7  | [#A855F7, #C084FC]
- Social            : #3B82F6  | [#3B82F6, #60A5FA]
- Education         : #EAB308  | [#EAB308, #FACC15]
- Travel            : #14B8A6  | [#14B8A6, #2DD4BF]

### Semantic
- success #34D399 | warning #F59E0B | danger #F87171 | info #38BDF8

### Urgency (days to renewal) — used on cards & insights
- days <= 3 : fg #F87171 , bg rgba(248,113,113,0.14)
- days <= 7 : fg #F59E0B , bg rgba(245,158,11,0.14)
- else      : fg #34D399 , bg rgba(52,211,153,0.12)

===============================================================================
## TYPOGRAPHY  (google_fonts)
===============================================================================
- "Space Grotesk"     -> numbers, big totals, screen titles, avatar letters,
                         prices, metric values, nav feel.
- "Plus Jakarta Sans" -> all other UI text.
- Money ALWAYS tabular: fontFeatures:[FontFeature.tabularFigures()].
- Scale:
    display   Space Grotesk 44 w700 ls -1.5   (hero totals)
    title     Space Grotesk 25 w700 ls -0.5   (screen titles)
    metricVal Space Grotesk 26 w700 ls -0.8   (metric cards)
    price     Space Grotesk 17 w700
    h-card    Plus Jakarta 15.5 w700
    body      Plus Jakarta 14 w500
    label     Plus Jakarta 12.5 w600
    caption   Plus Jakarta 12 w500  (muted)
    micro     Plus Jakarta 11 w600
    eyebrow   Plus Jakarta 12 w600 ls 1.5 UPPERCASE

===============================================================================
## SHAPE / SPACING
===============================================================================
- Radii: banner/hero 26, card 20, metric tile 20, chip 12, field 15, input 14,
  icon button 14, avatar 15, FAB 20, nav bar 22, pill 20, small pill/badge 6-8.
- Screen horizontal padding: 18 (content) / 22 (header, status, nav).
- Standard card padding 14; hero/banner padding 22.
- 1px inset hairline border on every dark card/field:
    Border.all(color: hairline, width: 1)  (or boxShadow inset trick).
- List item gap 11; section gap 18-22.

===============================================================================
## SHARED COMPONENTS (build once, reuse)
===============================================================================
1. GradientAvatar(letter, categoryColor): 52x52 (or size param), radius 15,
   category gradient, centered Space Grotesk letter white, soft colored shadow
   (category color, blur 18, y8, spread -8).
2. IconTile(icon): 42x42 or 46x46, radius 14, bg fieldBg, icon #C9C9D6,
   1px hairline border.
3. Pill(text, {fg, bg, dot}): radius 20 (or 8 for small), padding, optional
   leading dot; single line (no wrap).
4. GlassBottomNav(activeIndex): height 64, radius 22, navBg + BackdropFilter
   blur 18, 1px hairline, top shadow. Items: "Library" (grid icon) + "Dashboard"
   (line-chart icon). Active item sits in a 44x32 rounded-12 brandGradient pill,
   white icon + label w700; inactive icon+label textFaint w600. Behind the bar,
   a vertical gradient fade transparent -> screenBg.
5. PrimaryButton: full-width, height 54, radius 16, brandGradient bg, white
   Plus Jakarta 16 w700, brandGlowShadow (softer: blur 30 y16 spread -10).
6. GradientFab: 60x60 radius 20 brandGradient "+" white, glow shadow.

===============================================================================
## GLOBAL BEHAVIOR
===============================================================================
- HapticFeedback.selectionClick() on chip/tab/toggle taps; .lightImpact() on save.
- Page routes: FadeThrough / shared-axis (animations package) — never instant.
- All money via NumberFormat.currency(locale:'en_US', symbol:'\$', decimalDigits:2).
- SafeArea top+bottom; the mock status bar (9:41) is illustrative only.

===============================================================================
## CANONICAL SAMPLE DATA (use across ALL screens so totals reconcile)
===============================================================================
8 active subscriptions:
| name         | category           | price | cycle | daysToRenew | promo |
|--------------|--------------------|-------|-------|-------------|-------|
| Netflix      | Media / Streaming  | 15.49 | /mo   | 2           | no    |
| ChatGPT Plus | Productivity       | 20.00 | /mo   | 5           | no    |
| Adobe CC     | Productivity       | 54.99 | /mo   | 6           | YES   |
| Spotify      | Media / Streaming  | 11.99 | /mo   | 12          | no    |
| iCloud+      | Utilities          |  2.99 | /mo   | 18          | no    |
| Amazon Prime | Shopping           | 14.99 | /mo   | 21          | no    |
| Headspace    | Health / Fitness   | 12.99 | /mo   | 24          | no    |
| Disney+      | Media / Streaming  | 13.99 | /mo   | 28          | no    |

Derived (must match everywhere):
- Monthly total .......... $147.43
- Active subscriptions ... 8
- Avg per app ............ $18.43   (147.43 / 8)
- Yearly projection ...... $1,769.16 (147.43 * 12)
- Most expensive ......... Adobe CC $54.99
- Category monthly totals:
    Productivity ....... $74.99  (ChatGPT 20.00 + Adobe 54.99)   share 50.9%
    Media / Streaming .. $41.47  (Netflix + Spotify + Disney+)   share 28.1%
    Shopping ........... $14.99                                  share 10.2%
    Health / Fitness ... $12.99                                  share  8.8%
    Utilities .......... $ 2.99                                  share  2.0%
- Renewals this week (<=7 days): Netflix (2), ChatGPT (5), Adobe (6) = 3 items,
    $90.48 due.
- Duplicate flag: Media / Streaming has 3 apps = $41.47/mo.
- Promo ending: Adobe CC promo ends in 6 days.
- Health score: 68 / 100 -> "Needs Attention" (penalized for 3-app duplicate +
    Adobe's high cost + expiring promo).
- 6-month trend (Feb..Jul): [139, 144, 133, 152, 141, 147]  (Jul = current).
