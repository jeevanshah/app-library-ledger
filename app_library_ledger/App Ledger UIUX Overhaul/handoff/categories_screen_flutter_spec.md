# App Ledger — CATEGORIES MANAGER — Flutter Build Spec (text-only)

Prereq: read `00_shared_tokens.md`.
Full screen pushed over Library. Background screenBg #0B0B11. Scrollable /
reorderable list. Title "Categories".

===============================================================================
## APP BAR (custom, padding 22 h, 14 v)
===============================================================================
Row: [ 42x42 IconTile back arrow ]  title "Categories" (Space Grotesk 22 w700)
  [ spacer ]  [ 42x42 gradient IconTile "+" (brandGradient, white) -> opens
  "New category" dialog ].
Optional subtitle line under title (padding 22 h): "Drag to reorder · tap a
color to change it" (Plus Jakarta 12.5 w500 textMuted).

===============================================================================
## SUMMARY STRIP (optional, padding 18 h, mb 14)
===============================================================================
A small card bg cardBg radius 20 padding 14 hairline, Row:
  - left: "5 categories" Space Grotesk 17 w700 + "in use" caption textMuted
    (only 5 of the 10 defaults currently have subscriptions).
  - right: mini stacked horizontal bar showing category share (same colors as
    donut): a single rounded-6 bar height 10, segments proportional to
    Productivity 50.9 / Media 28.1 / Shopping 10.2 / Health 8.8 / Utilities 2.0.

===============================================================================
## LIST (ReorderableListView, padding 18 h, item gap 11, bottom pad 40)
===============================================================================
Each ROW = a card: bg cardBg, radius 20, padding 14, 1px hairline, Row (gap 14):
  - DRAG HANDLE: Icons.drag_indicator_rounded, color textFaint, 22px
    (ReorderableDragStartListener). On the LEFT.
  - COLOR SWATCH: 34x34 rounded-11, filled with category color; TAPPABLE ->
    opens the Color Picker dialog. Add a faint 1px inner white 15% ring.
  - MIDDLE (Expanded): name (Plus Jakarta 15.5 w700 textPrimary) over subtitle
    "N apps · $X/mo" (Plus Jakarta 12.5 w500 textMuted, tabular for the money).
    If a default (non-custom) category, no extra badge; if custom, show a tiny
    "Custom" micro pill (bg white 6%, textFaint).
  - TRAILING: 3-dot menu IconButton (Icons.more_vert_rounded, textMuted) opening a
    dark popup menu: [ Rename ] , [ Delete (danger red text) ].
    (Deleting a category with apps -> confirm dialog: "Move N apps to
    Uncategorized?".)

Data (order = current sort; show apps + $ from shared sample data):
  Productivity      | #6366F1 | 2 apps · $74.99/mo
  Media / Streaming | #EC4899 | 3 apps · $41.47/mo
  Shopping          | #F59E0B | 1 app  · $14.99/mo
  Health / Fitness  | #10B981 | 1 app  · $12.99/mo
  Utilities         | #06B6D4 | 1 app  · $2.99/mo
  Finance           | #22C55E | 0 apps · $0.00/mo
  Notes / Journaling| #A855F7 | 0 apps · $0.00/mo
  Social            | #3B82F6 | 0 apps · $0.00/mo
  Education         | #EAB308 | 0 apps · $0.00/mo
  Travel            | #14B8A6 | 0 apps · $0.00/mo
(Rows with 0 apps render the subtitle in textFaint.)

===============================================================================
## COLOR PICKER DIALOG
===============================================================================
Dialog: bg cardBg (#14141C), radius 24, padding 22, title "Pick a color"
(Space Grotesk 18 w700). A GridView of 12 swatches (4 columns, spacing 12):
each 48x48 rounded-14 filled circle/square; the currently-selected one gets a
2px white ring + a check icon. Tap selects and closes.
12 colors:
  #6366F1 #8B5CF6 #EC4899 #F472B6 #06B6D4 #22D3EE
  #10B981 #34D399 #F59E0B #FBBF24 #EF4444 #3B82F6
Cancel (text button textMuted) + "Done" (brand text) at the bottom.

===============================================================================
## NEW CATEGORY DIALOG
===============================================================================
Dialog bg cardBg radius 24 padding 22, title "New category". A text field
(same input style, placeholder "Category name") + a compact 12-swatch color row
(reuse the picker). Buttons: Cancel + "Create" (PrimaryButton small). New
categories are marked isCustom = true.

===============================================================================
## BEHAVIOR
===============================================================================
- Reorder persists the category sort order (SharedPreferences).
- HapticFeedback.selectionClick() on drag start + color select.
- ReorderableListView proxyDecorator: lift the card with a stronger shadow +
  slight scale (1.03) while dragging.

===============================================================================
## ACCEPTANCE
===============================================================================
[ ] Reorderable list of categories with a left drag handle per row.
[ ] Each row: tappable color swatch + name + "N apps · $X/mo" subtitle.
[ ] The 5 in-use categories show correct app counts and $ (sum to $147.43).
[ ] Tapping a swatch opens a 12-color grid picker with the current color ringed.
[ ] "+" in the app bar opens a New Category dialog (name + color).
[ ] 3-dot menu offers Rename + Delete (Delete in red).
[ ] Dragging lifts the card (shadow + slight scale) and the order persists.
