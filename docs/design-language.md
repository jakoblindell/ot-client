# Design language (ot-ui)

Our own windows and touch screens share one look, so new modules start out
looking finished and old ones change in one place. The styles live in
`data/styles/50-ot-ui.otui` and load globally.

## Look

Classic Tibia materials, nothing new to draw:

- **Stone** for every surface: panels use the bevelled stone frame
  (`/images/ui/2pixel_up_frame_borderimage`), buttons the shaded stone button
  (`button-9grid-idle` / `-pressed`).
- **Gold means "selected" or "on"**: the chosen tab, the chosen option, a
  checked box all get a gold edge and gold text. Nothing else is gold except
  section headings and the "?" marks.
- **The main action** of a screen (Done, Confirm, Buy) is a stone button
  with a gold edge and bright gold text.
- **Red means leaving or destroying**: Logout, Delete, Reset. It is the
  stone button tinted red.
- **High contrast** (a panel's `on` state): darker stone with a gold edge,
  for sunlight. Screens with a Contrast switch set it on their `OtPanel`.

## Building blocks

| Style | Use |
|---|---|
| `OtBackdrop` | Full-screen dim layer under a sheet; a tap on it closes the sheet |
| `OtPanel` | A window or sheet (stone, bevelled edge, 12 px padding) |
| `OtInset` | A sunken area inside a panel: lists, previews |
| `OtTitle` | A screen's title (13 px bold, white) |
| `OtHeading` | A section heading: gold capitals over a line (set `text`) |
| `OtLabel` | A setting's or field's name (11 px bold) |
| `OtText` / `OtHint` | Body text / quieter grey help text (wrap) |
| `OtButton` | Any button, 40 px high; `checked`/`on` = selected |
| `OtButtonPrimary` | The main action of a screen (Confirm, Buy, Done): gold edge, gold text |
| `OtButtonDanger` | Logout, Delete, Reset: red |
| `OtIconButton` | 40×40: close X, -, +, < |
| `OtTab` in `OtTabRow` | Tabs; the selected one is checked |
| `OtCheck` | On/off: a 28 px box with a gold tick, in a 40×40 touch area |
| `OtValue` | A value between - and + |
| `OtHelpButton` | The "?" beside a setting; opens a short explanation |
| `OtProgress` | A bar for how far along something is (gold fill, the count on it: `setPercent`, `setText`) |
| `OtSettingRow` | Title + "?" on the left, controls on the right (`controls` takes `OtButton`s, an `OtCheck`, or `-` `OtValue` `+`) |

Tokens (`&ot-…` in the same file): fonts `$ot-font-title`, `$ot-font-label`,
`$ot-font-text`, `$ot-font-small`; colours `$ot-text`, `$ot-text-strong`,
`$ot-text-muted`, `$ot-gold`, `$ot-positive` (green: you can afford it),
`$ot-negative` (red: you cannot), `$ot-backdrop`.

## Rules

1. Build from `Ot*` styles. Do not give single widgets their own colours,
   fonts or images; if something is missing, add a style or token to
   `50-ot-ui.otui` and use it.
2. Touch targets are at least 40 px. Rows are 52 px.
3. One primary (gold) button per screen at most; red only for leaving or
   destroying.
4. Every setting gets a "?" with one or two plain sentences, shown in a popup:
   touch screens have no hover tooltips.
5. Sheets: `OtBackdrop` > `OtPanel` with the title centred at the top, close
   (`X`) top right, back (`< Name`) top left when there is a parent screen.
6. Text says what happens in plain words ("Buy anyway?", "Reset UI"), not
   internal names.
7. Pieces keep their proportions: scale whole pieces (- and +), never stretch
   art. A box may only grow where its content fills it (more rows in a list,
   more columns in a grid).
8. Images are drawn for the size they are shown at. The classic UI images
   are tiny (a 12 px checkbox) and turn blurry and blocky when enlarged, so a
   touch-sized control gets its own art in `data/images/ui/ot/`, made at twice
   its size (phones draw the interface at 2x).
9. Compact: no more space between things than the eye needs. Every gap is
   paid for in game view, so pieces that stay open while playing (containers,
   hotbar, bars) use tight spacing: item slots touch (their frame is the
   separation) and padding is a few pixels, not 8 or 12. Classic item slots
   (34 px, `Item`) show sprites at their own size, so they stay crisp; the
   40 px touch-target rule is for buttons, not slots.
10. Check new screens at phone size in both orientations (1024×600 and
   600×1024) and on desktop before merging.

## Status

Built with ot-ui: the touch hub and settings, the hotbar sheet and hotbar
settings, the layout editor's bars and frames (`mods/client_mobile`), the
controller bind window (`mods/client_gamepad`), and the NPC dialog's
buttons, offers and travel rows (`mods/client_npcdialog`; the dialog keeps
the classic movable window).
