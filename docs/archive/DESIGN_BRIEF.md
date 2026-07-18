# App Ledger — Complete Design Brief for UI/UX Overhaul

## 1. What Is This App?

**App Ledger** is a **subscription tracking app** for Android. It helps users catalog all their paid subscriptions (Netflix, Spotify, iCloud, ChatGPT, etc.) in one place — see total monthly spending, get renewal reminders, spot duplicate services, and make smarter financial decisions.

**Tagline**: "Track. Save. Thrive."

**Core Promise**: Know exactly what you're paying for, never get surprised by a renewal, and save money by finding waste.

---

## 2. Target Audience

- **Primary**: 25-45 year olds with 5-15+ digital subscriptions (streaming, productivity, cloud, fitness)
- **Secondary**: Anyone experiencing "subscription creep" — signed up for free trials, forgot to cancel, now paying for things they don't use
- **Pain Point**: "I think I'm spending ~$50/month on subscriptions but I'm not sure. I had a free trial that just billed me $120 for the year."
- **Use Case**: Opening the app 2-3 times per week to check upcoming renewals and monthly spend

---

## 3. Business Model

- **Free with Ads**: Banner ad at bottom, interstitial after saving a subscription
- **Remove Ads IAP**: One-time purchase ($2.99) to remove all ads
- **Future**: Premium features (cloud sync, family sharing, PDF reports)

---

## 4. Current Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.9+ (Dart) |
| State Management | setState (no provider/bloc — simple) |
| Local Storage | SharedPreferences (JSON serialized) |
| Charts | fl_chart (pie chart for spending breakdown) |
| Notifications | flutter_local_notifications (7-day + 1-day renewal alerts) |
| Ads | google_mobile_ads (banner + interstitial) |
| IAP | in_app_purchase |
| Export | share_plus + path_provider (CSV + JSON backup) |
| URL Launching | url_launcher |
| Date Formatting | intl |
| Icons | Material Icons + hugeicons |

---

## 5. App Architecture & Screens

### Screen Flow
```
Splash → Onboarding (first launch only) → Library/Dashboard
                                            ↕
                                        Add/Edit App
                                        Categories Manager
```

### Screen 1: Splash Screen
- Purple gradient background (`#6366F1` → `#8B5CF6`)
- App icon (subscriptions icon) with elastic scale animation
- Expanding ring ripples behind the icon
- "App Ledger" title slides up with "Track. Save. Thrive." tagline
- **Duration**: 2 seconds, then transitions to Library (or Onboarding if first launch)

### Screen 2: Onboarding (4 pages, first launch only)
- Each page has a distinct background color
- Page 1: "Know Your Spend" — dashboard overview, light blue bg
- Page 2: "Never Miss a Renewal" — notification alerts, cyan bg
- Page 3: "Save Smarter" — health score & savings, green bg
- Page 4: "100% Private" — offline/private, pink bg
- Large gradient icon containers (140x140), title, description
- Animated dots + "Skip" and "Continue" buttons
- Color palette: Each page has its own `(iconColor, backgroundColor)` pair

### Screen 3: Library (Main Screen)
**Two tabs with bottom NavigationBar:**

#### Tab A: Library
- **Summary Banner** (top): Shows monthly total with large number + active subscription count. Tapping it navigates to Dashboard tab. Shown only when there are active subscriptions.
- **Search Bar**: Rounded text field with search icon
- **Grid/List Toggle**: Icon button to switch between views
- **Horizontal Category Chips**: Scrollable row of FilterChips (colored dots + category name + count). Selecting one filters the list.
- **List View**: Cards with gradient app icon (first letter), name, category dot, days-until-renewal countdown, price, promo badge
- **Grid View**: 2-column cards with circular avatar, price, name, category
- **Swipe-to-Delete**: Swipe left on any card to reveal red delete background
- **Empty State**: Gradient circle with inbox icon, "No subscriptions yet" text
- **FAB**: "+" Floating Action Button to add new subscription

#### Tab B: Dashboard
- **4 Metric Cards** (2x2 grid): Monthly Total ($), Avg per App, Active Subs count, Yearly Projection. Each is a gradient container with icon + value + label.
- **Pie Chart** (glassmorphism card): Spending breakdown by category. Shows colored slices with dollar amounts, legend below with category name + monthly cost.
- **Smart Insights** (glassmorphism card): AI-generated insights:
  - "Monthly Spend: $X/month ($Y/year)" 
  - "X Renewal(s) This Week: $Z due"
  - "Duplicate: Media/Streaming — 3 apps, $45/mo. Consolidate?"
  - "Price Increase Alert: Netflix promo ends in X days"
  - "Health Score: X/100 — Good/Needs Attention"
- **Glass Bottom Bar**: Frosted glass (BackdropFilter) with NavigationBar + AdMob banner above it

### Screen 4: Add/Edit Subscription
- **Quick Add Grid** (horizontal scroll, shown only when adding new): 12 popular apps (Netflix, Spotify, Disney+, etc.) each with brand-colored tiles showing name + price. Tap to auto-fill.
- **Form Fields** (staggered slide-in animations):
  - App Name (required)
  - App Store Link (optional, auto-generated if empty)
  - Category dropdown (10 default + custom, with colored dots)
  - "Paid Subscription" toggle switch
  - Cost field ($) + billing cycle dropdown (Monthly/Yearly) — shown when toggle is ON
  - Next Renewal Date picker — shown when toggle is ON
  - "Promotional Price" toggle switch — shown when subscription toggle is ON
  - Regular Price field — shown when promo toggle is ON
  - Promotion End Date picker — shown when promo toggle is ON
  - Notes field (multi-line, optional)
- **Save Button**: Full-width FilledButton at bottom
- **Edit Mode**: Same screen pre-filled with existing data, title changes to "Edit"

### Screen 5: Categories Manager
- **List of Categories**: ReorderableListView (drag handles)
- Each row: color square (tap to change color), name, "X apps · $Y/mo" subtitle, 3-dot menu (Rename, Delete)
- **Color Picker Dialog**: 12 predefined colors in a grid, tap to select
- **Add Button**: Opens dialog to create new category
- **Gradient Background**: Subtle gradient matching other screens

---

## 6. Data Models

### AppEntry (subscription)
```dart
{
  id: String (UUID),
  name: String,          // "Netflix"
  appStoreLink: String,  // "https://apps.apple.com/app/netflix"
  category: String,      // "Media / Streaming"
  notes: String?,        // "Family plan, shared with 3 people"
  createdAt: DateTime,
  isActiveSubscription: bool,
  subscriptionCost: double?,  // 15.49
  billingCycle: String?,      // "monthly" | "yearly"
  nextRenewalDate: DateTime?,
  isPromotionalPrice: bool,
  regularPrice: double?,      // 19.99 (price after promo ends)
  promotionEndsDate: DateTime?,
}
```

### Category
```dart
{
  name: String,
  color: Color,
  isCustom: bool,  // true if user-created
}
```

### Default Categories (10)
Productivity, Notes / Journaling, Finance, Health / Fitness, Media / Streaming, Utilities, Social, Education, Shopping, Travel

---

## 7. Key User Flows

### Flow 1: First Launch
1. App opens → Splash screen (2 seconds)
2. Onboarding (4 pages, skippable)
3. Empty Library → "Tap + to add your first"
4. User taps FAB → Add screen opens
5. User types "Netflix" → Quick Add suggestion appears → taps it → all fields auto-fill
6. User taps Save → confetti animation → returns to Library showing Netflix card
7. Monthly spend banner now shows "$15.49"

### Flow 2: Check Upcoming Renewals
1. User opens app → sees Library with "Monthly spend" banner
2. Scrolls through list → sees "Netflix — Renews in 3 days" with orange alert icon
3. Switches to Dashboard → sees "1 Renewal This Week: $15.49"
4. Gets push notification: "Renewal tomorrow: Netflix — $15.49"

### Flow 3: Find Waste
1. User adds 3 streaming services
2. Dashboard shows insight: "Duplicate: Media/Streaming — 3 apps, $45/mo"
3. Health score drops to "Needs Attention"
4. User reviews and removes one service

### Flow 4: Export Data
1. User taps share icon in app bar
2. Bottom sheet: "CSV Export" or "JSON Backup"
3. System share sheet opens → user emails themselves the file

---

## 8. Current Design Language

### Colors
- **Primary**: `#6366F1` (Indigo/Purple)
- **Secondary**: `#06B6D4` (Cyan/Teal)
- **Accent**: `#EC4899` (Pink)
- **Success**: `#10B981` (Green)
- **Warning**: `#F59E0B` (Amber)
- **Error**: `#EF4444` (Red)

### Typography
- **Headlines**: 22-28px, Bold (w700-w800), letter-spacing -0.5
- **Body**: 13-15px, Regular/Medium
- **Captions**: 11-12px, grey
- **Font**: System default (Roboto on Android, SF Pro on iOS)

### Shapes
- **Cards**: Rounded corners 18-20px
- **Buttons**: Rounded corners 14-16px
- **Input fields**: Rounded corners 14px
- **Icons**: Rounded variant (Icons.* _rounded)

### Effects Currently Used
- Linear gradients on cards, buttons, backgrounds
- Box shadows with colored opacity
- BackdropFilter blur for glassmorphism
- Hero transitions on app icons
- Haptic feedback on interactions
- AnimatedSwitcher for toggles
- FadeTransition for page routes
- ScaleTransition on empty states

---

## 9. What Needs Improvement (Pain Points)

1. **Dashboard feels plain** — Metric cards are static, pie chart lacks interactivity, no trend lines or comparison data
2. **No spending trends over time** — Only shows current snapshot, no month-over-month
3. **Library cards are basic** — Could use swipe actions (edit left, delete right), checkmark animations, color-coded urgency
4. **No "quick glance" widget feeling** — Dashboard should feel like a financial dashboard (think Robinhood, Mint, YNAB)
5. **Onboarding is static** — Could use illustrations, micro-animations, progress indicator
6. **Categories screen is plain** — Could show category spending comparisons, most/least used categories
7. **No dark mode polish** — Dark theme could have deeper blacks, neon accents, proper contrast
8. **Transitions between tabs** — Currently IndexedStack (instant switch), no animation
9. **No empty state guidance** — First-time users see a blank "No subscriptions yet" — could show suggested first steps
10. **Ad placement is jarring** — Banner at bottom interrupts the UI flow

---

## 10. Design Inspiration & References

### Apps to Reference
- **YNAB** (You Need A Budget) — Clean financial dashboard, colored category icons, progress bars
- **Robinhood** — Green/red color coding, chart animations, card-based layout
- **Headspace** — Onboarding illustrations, calming colors, micro-animations
- **Duolingo** — Gamification elements, celebration animations, progress tracking
- **Things 3** — Clean typography, minimal cards, smooth transitions
- **Apple Health** — Ring charts, summary cards, color-coded categories

### Design Direction We Want
- **Premium/Professional** — Not playful/childish
- **Data-rich but clean** — Numbers should be prominent and easy to scan
- **Trustworthy** — Financial apps need to feel secure and accurate
- **Delightful micro-interactions** — Small animations that make data entry feel satisfying
- **Dark mode optimized** — Our audience checks their finances at night too

---

## 11. Feature Wishlist for UI/UX

### High Priority
- Animated number counters (spend increasing from $0)
- Pull-to-refresh with skeleton loading
- Swipe actions on cards (edit/delete)
- Bottom sheet filters (category + price range)
- Line chart for 6-month spending trend
- Health score gauge/ring
- Tab transition animations (slide between Library/Dashboard)

### Medium Priority
- Quick-add tap targets on empty state
- Progress towards savings goal
- "You've saved $X this year by canceling" counter
- Color-coded urgency states (green = good, yellow = soon, red = overdue)
- Empty state illustrations
- Skeleton loading shimmer effect
- Celebration/confetti on first subscription added

### Nice to Have
- Animated splash with brand animation
- Onboarding illustrations
- Haptic feedback on all interactions
- Parallax scrolling effects
- Glassmorphism cards with blur
- Floating speed-dial FAB

---

## 12. Technical Constraints
- Flutter 3.9+ (Dart)
- Must work on Android API 21+ (Android 5.0+)
- Offline-first (all data local in SharedPreferences)
- Must support light and dark theme
- AdMob banner must be integrated (bottom of screen)
- Push notifications for renewal reminders

---

## 13. Current File Structure
```
lib/
├── main.dart                         # Entry point, splash → onboarding → library flow
├── models/
│   ├── app_model.dart                # AppEntry data model with JSON serialization
│   └── category_model.dart           # Category data model
├── screens/
│   ├── splash_screen.dart            # Animated splash with ring ripples
│   ├── onboarding_screen.dart        # 4-page onboarding with colored backgrounds
│   ├── library_screen.dart           # Main screen: Library + Dashboard tabs, bottom nav
│   ├── add_app_screen.dart           # Add/Edit form with Quick Add grid
│   └── categories_screen.dart        # Categories manager with color picker
├── services/
│   ├── storage_service.dart          # SharedPreferences CRUD for apps + categories
│   ├── notification_service.dart     # 7-day + 1-day renewal push notifications
│   ├── ad_service.dart               # Google AdMob banner + interstitial
│   ├── backup_service.dart           # CSV/JSON export via share sheet
│   └── analytics_service.dart        # Spending metrics, health score, insights generator
└── theme/
    └── app_theme.dart                # Light/dark Material 3 themes, GlassmorphicContainer
```

---

## 14. Key Metrics the Dashboard Must Display
1. Total monthly spend (sum of all active subscriptions, yearly converted to monthly)
2. Average cost per app
3. Number of active subscriptions
4. Yearly projected spend
5. Spending breakdown by category (pie chart with legend)
6. Health Score (0-100, penalizes high spend, duplicates, unused subs, expiring promos)
7. Upcoming renewals this week (count + cost)
8. Duplicate category alerts
9. Promotional price expiring alerts
10. Most expensive subscription

---

This document is a complete specification of **App Ledger** as it exists today and the design direction we want to move toward. Use this to create a fresh, premium UI/UX design that makes subscription tracking beautiful and intuitive.