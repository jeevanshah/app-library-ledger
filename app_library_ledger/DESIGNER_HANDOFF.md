# App Ledger — Designer Handoff Document

> **Purpose**: Give this document to your UI/UX designer so they can completely reimagine the app's visual design. It contains everything they need: what the app does, who uses it, every screen, every component, current design language, inspiration references, and what's working vs. what needs improvement.

---

## 1. Executive Summary

**App Ledger** is an Android subscription tracker. Users catalog their paid subscriptions (Netflix, Spotify, iCloud, ChatGPT, etc.) to see total monthly spending, get renewal reminders, spot duplicate services, and save money.

**Tagline**: "Track. Save. Thrive."

**Business Model**: Free with ads (banner + interstitial). $2.99 one-time IAP to remove ads.

**Current Status**: Fully functional app with all features working. The UI has been iterated multiple times but needs a professional designer's eye to become truly premium and Play Store ready.

---

## 2. Target Audience & Context

| Attribute | Detail |
|---|---|
| **Age** | 25-45 |
| **Behavior** | Has 5-15+ digital subscriptions across streaming, productivity, cloud, fitness |
| **Pain Point** | "I think I'm spending ~$50/month but I'm not sure. I had a free trial that just billed me $120." |
| **Usage Pattern** | Opens app 2-3x/week to check upcoming renewals and monthly spend |
| **Device** | Android phone (primary), portrait mode |
| **Competitors** | Bobby, Hiatus, Truebill (all require bank linking — App Ledger is manual, private, offline) |
| **Key Differentiator** | 100% offline. No accounts. No bank linking. No tracking. All data on device. |

---

## 3. App Flow (All Screens)

```
┌─────────┐     ┌──────────────┐     ┌─────────────────────────┐
│  SPLASH  │────▶│  ONBOARDING  │────▶│   LIBRARY / DASHBOARD   │
│  (2 sec) │     │  (4 pages,   │     │   (main screen — 2 tabs) │
│          │     │  first launch │     │                         │
└─────────┘     │  only)        │     └──────────┬──────────────┘
                └──────────────┘                │
                                        ┌───────┴───────┐
                                        │               │
                                   ┌────▼────┐    ┌─────▼──────┐
                                   │ ADD/EDIT │    │ CATEGORIES │
                                   │   APP    │    │  MANAGER   │
                                   └─────────┘    └────────────┘
```

### Screen 1: Splash (2 seconds)
- Purple gradient background
- Elastic scale-in app icon animation
- Expanding ring ripples behind icon
- "App Ledger" title + "Track. Save. Thrive." tagline
- Auto-transitions to Onboarding (first launch) or Library

### Screen 2: Onboarding (4 pages, first launch only)
- Dark background with per-page accent glow
- 4 pages, horizontally swipeable, skippable
- Page 1: "Know Your Spend" (blue accent)
- Page 2: "Never Miss a Renewal" (cyan accent)
- Page 3: "Save Smarter" (green accent)
- Page 4: "100% Private" (pink accent)
- Each page: large gradient icon container (140x140), title, description, dots + CTA

### Screen 3: Library Tab (Main Screen — Tab A)
**This is the most important screen. Users spend 90% of time here.**

Components from top to bottom:
1. **Header**: "YOUR LIBRARY" eyebrow + "$N subscriptions" title + "⦿ DEVICE LOCAL" trust badge
2. **Hero Total Card**: Large card showing monthly spend (animated counter), gold serif number (52px), active count + yearly projection pills
3. **Search Bar**: Dark field with search icon
4. **Sort + Grid Toggle**: Sort icon (cycles Name→Price→Renewal→Recent) + List/Grid toggle
5. **Category Chips**: Horizontal scrollable FilterChips with colored dots and counts
6. **Subscription List**: Cards showing:
   - Gradient avatar (first letter of app name)
   - App name + optional PROMO badge
   - Category with colored dot
   - Urgency pill (red ≤3 days, amber ≤7 days, green >7 days)
   - Price (right-aligned) with billing cycle
   - Chevron for tap-to-edit
   - Swipe-to-delete
7. **Grid View** (alternate): 2-column cards with avatar, price, name, category
8. **FAB**: Solid gold "+" button
9. **Bottom Nav**: Glass blur bar with Library/Dashboard tabs

### Screen 4: Dashboard Tab (Main Screen — Tab B)
Components from top to bottom:
1. **Header**: "DASHBOARD" eyebrow + "Overview" title + "⦿ DEVICE LOCAL" badge
2. **4 Metric Cards** (2×2 grid): Monthly Total, Avg/App, Active Subs, Yearly Projection — each with tinted icon chip
3. **Smart Insights Card**: AI-generated insights list with colored icon chips, title + detail text

### Screen 5: Add/Edit Subscription
- **Quick Add Grid** (horizontal scroll, 12 popular apps with brand colors)
- **Form Fields** with staggered slide-in animations
  - App Name (required)
  - App Store Link (optional)
  - Category dropdown (10 defaults + custom)
  - "Paid Subscription" toggle
  - Cost ($) + billing cycle (monthly/yearly)
  - Next Renewal Date picker
  - "Promotional Price" toggle
  - Regular Price + Promotion End Date
  - Notes (multi-line)
- **Save Button**: Full-width at bottom

### Screen 6: Categories Manager
- ReorderableListView with drag handles
- Each row: tappable color swatch, name, "X apps · $X/mo" subtitle, 3-dot menu
- Color picker dialog (12 colors)
- Add category dialog

---

## 4. Data Models

### AppEntry (what a subscription looks like)
| Field | Type | Example |
|---|---|---|
| id | String (UUID) | "abc-123" |
| name | String | "Netflix" |
| appStoreLink | String | "https://apps.apple.com/app/netflix" |
| category | String | "Media / Streaming" |
| notes | String? | "Family plan, shared" |
| isActiveSubscription | bool | true |
| subscriptionCost | double? | 15.49 |
| billingCycle | String? | "monthly" or "yearly" |
| nextRenewalDate | DateTime? | 2026-07-15 |
| isPromotionalPrice | bool | false |
| regularPrice | double? | 19.99 |
| promotionEndsDate | DateTime? | null |

### Category
| Field | Type | Example |
|---|---|---|
| name | String | "Productivity" |
| color | Color | #6366F1 |
| isCustom | bool | false |

### 10 Default Categories
Productivity, Notes / Journaling, Finance, Health / Fitness, Media / Streaming, Utilities, Social, Education, Shopping, Travel

---

## 5. Key User Flows

### Flow 1: First Launch
Splash → Onboarding (4 swipes) → Empty Library → Tap FAB → Quick Add "Netflix" → Auto-fill → Save → Confetti → See Netflix in Library → Monthly spend appears

### Flow 2: Check Upcoming Renewals
Open app → See "Netflix — Renews in 3 days" with red/orange alert → Tap Dashboard → See "3 Renewals This Week: $90.48"

### Flow 3: Get Push Notification
Phone buzzes: "Renewal tomorrow: Netflix — $15.49" → Tap notification → Opens app to Library

### Flow 4: Export Data
Tap share icon → Choose CSV or JSON → System share sheet → Email to self

---

## 6. Current Design System

### Colors
| Token | Hex | Usage |
|---|---|---|
| screenBg | #0B0B11 | App background (near-black) |
| cardBg | #14141C | Cards |
| fieldBg | #15151D | Input fields, chips, icon buttons |
| textPrimary | #F2F2F8 | Primary text |
| textMuted | #7C7C92 | Secondary text |
| textFaint | #6B6B82 | Tertiary/caption text |
| hairline | rgba(255,255,255,0.05) | 1px borders |
| brandStart | #6366F1 | Purple (primary) |
| brandEnd | #8B5CF6 | Violet (gradient end) |
| gold | #C8A96E | Gold accent (hero numbers, FAB) |
| success | #34D399 | Green |
| warning | #F59E0B | Amber |
| danger | #F87171 | Red |

### Category Colors
| Category | Color |
|---|---|
| Productivity | #6366F1 (purple) |
| Media / Streaming | #EC4899 (pink) |
| Utilities | #06B6D4 (cyan) |
| Shopping | #F59E0B (amber) |
| Health / Fitness | #10B981 (green) |
| Finance | #22C55E (green) |
| Notes / Journaling | #A855F7 (violet) |
| Social | #3B82F6 (blue) |
| Education | #EAB308 (yellow) |
| Travel | #14B8A6 (teal) |

### Typography
| Role | Font | Size | Weight |
|---|---|---|---|
| Hero total | Playfair Display | 52px | 700 |
| Screen titles | Playfair Display | 28px | 700 |
| App names | Plus Jakarta Sans | 14.5px | 600 |
| Prices | Space Grotesk | 15-22px | 700 |
| Category labels | Plus Jakarta Sans | 11.5-12px | 500-600 |
| Eyebrows (headers) | Plus Jakarta Sans | 11px | 600 |

### Spacing & Radii
- Content padding: 22px horizontal
- Card padding: 14-16px
- Item gap: 14px
- Card radius: 16-20px
- Input radius: 12-14px
- Chip radius: 10px

---

## 7. What's Working Well

1. **Color-coded urgency system** — red/amber/green pills for renewal deadlines are effective
2. **Category color coding** — each category has a distinct color, making cards scannable
3. **Horizontal category chips** — great for filtering
4. **Gold hero number** — the Playfair Display serif total is distinctive
5. **DEVICE LOCAL trust badge** — reinforces the privacy promise
6. **Swipe-to-delete** — natural gesture

---

## 8. What Needs Improvement (Designer's Brief)

### Critical
1. **The app feels "dark purple" everywhere** — needs more personality. The gold accent is a start but isn't used enough throughout. Consider: gold category dots, gold-accented metric cards, gold divider lines.
2. **Cards feel dense** — list items need more breathing room between text elements. Current spacing is tight.
3. **Dashboard has no data visualization** — just 4 metric cards + text insights. Missing: pie/donut chart, spending trend line, health score gauge.
4. **Empty state is boring** — just grey text "No subscriptions yet". Need an illustration + CTA.
5. **Add screen is overwhelming** — too many fields visible at once. Consider a wizard/step flow or progressive disclosure.
6. **Onboarding is static** — no illustrations, no micro-animations beyond a scale effect.

### Important
7. **No pull-to-refresh indicator** — data loads silently
8. **No skeleton loading** — just a spinner during load
9. **Tab transition is instant** — no animation between Library/Dashboard
10. **FAB is lonely** — could be a speed dial with quick actions
11. **No confirmation/success animation** when saving a subscription
12. **Categories screen is plain** — simple list, could show spending comparisons

### Nice to Have
13. **No dark/light toggle** — app is dark-only
14. **No search history or recent filters**
15. **No keyboard shortcuts or swipe-back gesture polish**
16. **Ad placement feels tacked-on** — not integrated into the design

---

## 9. Design Inspiration & References

### Apps to Study
| App | What to Learn From |
|---|---|
| **VaultSub** (fictional) | "Ink & Depth" dark luxury editorial — serif hero numbers, gold accents, generous whitespace, 1px separators |
| **YNAB** (You Need A Budget) | Clean financial dashboard, progress bars, color-coded categories |
| **Robinhood** | Green/red color coding, line charts, card-based layout, number animations |
| **Things 3** | Clean typography, minimal cards, smooth transitions |
| **Apple Health** | Ring charts, summary cards, color-coded categories |
| **Headspace** | Onboarding illustrations, calming colors, micro-animations |

### Design Direction We Want
- **Premium/Professional** — not playful or childish
- **Data-rich but clean** — numbers prominent and scannable
- **Trustworthy** — feels secure and accurate (financial app)
- **Delightful micro-interactions** — small animations that make data entry satisfying
- **Distinctive** — should NOT look like a generic Material 3 app

### Keywords for Designer
"Dark luxury editorial" · "Financial ledger" · "Warm gold accents" · "Serif + sans-serif contrast" · "Generous whitespace" · "Subtle 1px separators" · "Confidence-inspiring" · "Not a generic purple app"

---

## 10. Technical Constraints

| Constraint | Detail |
|---|---|
| Framework | Flutter 3.9+ (Dart) |
| Target Platform | Android (API 21+, 99% of devices) |
| Theme | Dark-first (no light mode for now) |
| Storage | SharedPreferences (key-value, offline) |
| Charts | fl_chart package (pie, line, bar available) |
| Fonts | Google Fonts package (any Google Font available) |
| Animations | Flutter's built-in animation system |
| AdMob | Banner ad at bottom of screen |
| Offline | 100% local — no network calls at all |

---

## 11. What the Designer Should Deliver

1. **Complete visual redesign** of all 6 screens in Figma (or similar)
2. **Design system** with tokens: colors, typography scale, spacing system, component library
3. **Component states**: default, hover, active, disabled, error for all interactive elements
4. **Micro-interaction specs**: entrance animations, transition animations, feedback animations
5. **Empty/loading/error states** for every screen
6. **Dark theme** only (light theme optional for future)
7. **Export-ready assets**: icons, illustrations if any

---

## 12. Screen Inventory (What to Design)

| # | Screen | Priority | Notes |
|---|---|---|---|
| 1 | **Library** (main) | 🔴 Critical | 90% of user time. Must be stunning. |
| 2 | **Dashboard** | 🔴 Critical | Needs charts + health score visualization |
| 3 | **Add/Edit App** | 🟡 High | Most interaction-heavy screen |
| 4 | **Onboarding (×4)** | 🟡 High | First impression. Needs illustrations. |
| 5 | **Splash** | 🟢 Medium | 2-second brand moment |
| 6 | **Categories** | 🟢 Medium | Management screen, less frequent |
| 7 | **Empty States** | 🟡 High | Shown to every new user |
| 8 | **Loading States** | 🟡 High | Skeleton screens for all data-loading |
| 9 | **Error States** | 🟢 Medium | Rare but needed |
| 10 | **Bottom Sheets** (filter, export) | 🟢 Medium | Modal overlays |
| 11 | **Dialogs** (delete confirm, color picker) | 🟢 Medium | Standard modals |

---

## 13. Reference: Current APK

The latest APK with the luxury hybrid design is at:
```
build\app\outputs\flutter-apk\app-debug.apk
```

Install it on an Android phone to see the current state. Screenshots can be taken from a running device.

---

## 14. Summary for the Designer

> App Ledger is a subscription tracker for Android. It's dark-themed, offline-only, and privacy-first. The current design is functional but needs a professional reimagining — think **"VaultSub meets YNAB"** with a dark luxury editorial feel. Gold serif hero numbers, generous whitespace, subtle 1px separators, and data visualizations that inspire confidence. The target user is a 25-45 year old professional managing 5-15+ digital subscriptions who wants to feel in control of their monthly spend.

> We're looking for a fresh, distinctive visual identity that stands out from generic Material 3 apps and makes subscription tracking feel premium.