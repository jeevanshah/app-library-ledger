# App Ledger — ADD / EDIT SUBSCRIPTION — Flutter Build Spec (text-only)

Prereq: read `00_shared_tokens.md`.
A full-screen form pushed over Library (shared-axis transition). Background screenBg.
Title "Add subscription" (add mode) or "Edit subscription" (edit mode, fields prefilled).
Scrollable; Save button pinned at the bottom.

===============================================================================
## APP BAR (custom, padding 22 h, 14 v)
===============================================================================
Row: [ 42x42 IconTile back arrow (Icons.arrow_back_rounded) ]  title (Space Grotesk
22 w700, centered-ish or left)  [ spacer ]  [ optional 42x42 IconTile delete
(trash, danger tint) — edit mode only ].

===============================================================================
## QUICK ADD  (ADD MODE ONLY — hide entirely in edit mode)
===============================================================================
Section label "Quick add" (eyebrow style) padding 18 h.
Horizontal scroll Row, height ~92, gap 11, padding 18 h. 12 brand tiles.
Each tile: width ~78, radius 18, padding 12, background = that brand's color at
full or a 2-stop brand gradient, Column:
  - top: 30x30 rounded-9 white 22% chip with the brand's first letter (white w700)
    (use letters, NOT real logos, to avoid trademark issues).
  - name (gap 8): Plus Jakarta 12 w700 white, 1 line ellipsis.
  - price (gap 2): Space Grotesk 11 w600 white 85%.
Tapping a tile auto-fills name, category, cost, cycle (monthly) with a soft
scale-tap feedback + HapticFeedback.selectionClick().

Suggested 12 (name | brandColor | price | category):
  Netflix #E50914 15.49 Media / Streaming
  Spotify #1DB954 11.99 Media / Streaming
  Disney+ #113CCF 13.99 Media / Streaming
  YouTube Premium #FF0000 13.99 Media / Streaming
  ChatGPT Plus #10A37F 20.00 Productivity
  Notion #111111 8.00 Productivity   (render tile bg #2A2A32 since black is invisible)
  Adobe CC #FA0F00 54.99 Productivity
  iCloud+ #3693F3 2.99 Utilities
  Amazon Prime #FF9900 14.99 Shopping
  Headspace #F47D31 12.99 Health / Fitness
  Dropbox #0061FF 11.99 Utilities
  HBO Max #7B2BF9 15.99 Media / Streaming

===============================================================================
## FORM  (padding 18 h, field gap 16)
===============================================================================
Each field = a labeled block: label above (Plus Jakarta 12.5 w600 textMuted, mb 8),
then the control. Inputs: bg fieldBg, radius 14, 1px hairline, height 52,
padding 0 16, text Plus Jakarta 15 w500 textPrimary, cursor brandEnd,
focus border = brandEnd 1.5px. Placeholder textPlaceholder.

Fields IN ORDER (each slides in staggered: translateY 12 -> 0 + fade, 60ms apart):
  1. App Name  (required) — text field, placeholder "e.g. Netflix".
     Show a red helper "Name is required" if empty on save.
  2. App Store Link (optional) — text field, placeholder "https://…",
     keyboardType url. Helper caption textFaint: "Auto-generated if left empty."
  3. Category — dropdown / bottom-sheet picker. Field shows a leading colored dot
     (selected category color) + name + trailing chevron. Tapping opens a bottom
     sheet list of categories, each row = colored dot + name; includes a
     "+ New category" row at the bottom.
  4. "Paid subscription" — a ROW: label "Paid subscription" (Plus Jakarta 15 w600
     textPrimary) + subtitle "Track cost & renewals" (12 textMuted) + a Switch on
     the right (active track brandEnd, thumb white). Default ON.

  --- The following appear ONLY when "Paid subscription" is ON (AnimatedSize +
      fade so they expand/collapse smoothly): ---
  5. Cost + Billing cycle — a ROW of two fields:
       * Cost (Expanded): prefix "$", numeric keyboard, placeholder "0.00",
         Space Grotesk value, tabular.
       * Billing cycle (width ~130): segmented pill [ Monthly | Yearly ], bg fieldBg,
         active segment brandGradient, default Monthly.
  6. Next renewal date — tappable field, leading calendar icon, shows formatted
     date (e.g. "Aug 12, 2026") or placeholder "Select date"; opens showDatePicker
     with a dark themed picker (brandEnd as primary).
  7. "Promotional price" — same Switch-row pattern as #4. subtitle
     "Currently on a discounted rate". Default OFF.

  --- The following appear ONLY when "Promotional price" is ON: ---
  8. Regular price — "$"-prefixed numeric field, placeholder "0.00",
     helper caption: "Price after the promo ends."
  9. Promotion end date — date picker field (same pattern as #6).

  10. Notes (optional) — multiline TextField (minLines 3), radius 14, bg fieldBg,
      placeholder "e.g. Family plan, shared with 3 people".

===============================================================================
## SAVE BAR (pinned bottom)
===============================================================================
Container padding 18, bg = gradient fade transparent -> screenBg, with a top hairline.
PrimaryButton full-width: label "Save subscription" (add) / "Save changes" (edit).
On tap: validate name; if a paid sub, require cost + renewal date; then
HapticFeedback.lightImpact(), persist, pop back to Library.

===============================================================================
## DELIGHT
===============================================================================
- FIRST subscription ever saved -> a brief confetti burst over the Library on return
  (e.g. `confetti` package or a simple particle overlay ~1.2s).
- Toggling switches uses AnimatedSwitcher/AnimatedSize so dependent fields glide.

===============================================================================
## ACCEPTANCE
===============================================================================
[ ] Add mode shows the horizontal Quick-Add row of 12 brand-colored tiles; edit mode hides it.
[ ] Tapping a Quick-Add tile fills name/category/cost/cycle.
[ ] Fields use dark inputs (bg #15151D, radius 14, hairline, brandEnd focus).
[ ] Cost/cycle, renewal date appear only when "Paid subscription" is ON.
[ ] Regular price + promo end date appear only when "Promotional price" is ON.
[ ] Expand/collapse of conditional fields is animated (AnimatedSize), not a hard jump.
[ ] Category picker shows colored dots + a "+ New category" row.
[ ] Pinned gradient Save button; validates required fields before saving.
[ ] Edit mode prefills all fields and title reads "Edit subscription".
