# UI gallery: screenshot tests

Screenshots of our UI components on phones, a tablet and desktop, compared
with saved baseline images on every pull request (ot-client#70).

- **The gallery** is `mods/client_gallery`. When the page sets
  `window.otclientConfig.gallery = '<page>'`, the client shows that page of
  components instead of the login, then logs `[gallery] ready <page>`.
  Without that setting the mod does nothing.
- **The script** (`gallery.js`) serves a browser build, opens every page on
  every device in headless Chromium and saves a screenshot. It compares each
  one with `baseline/` and writes `report.html`, a grid of pages by
  devices. Changed pages show the new image, the baseline and a diff (red).

## Pages and devices

| Page | Shows |
|---|---|
| `buttons` | `OtButton` states, primary, danger, icon and help buttons, tabs |
| `controls` | checks, progress bars, a stepper, setting rows in a panel, contrast panel |
| `text` | title, heading, label, text, hint, the colour tokens |
| `touch` | round hotbar slots at 32–64 px, chat, P1 and pencil buttons, health/mana bars, toolbar |
| `hub` | the hub's front page |
| `journal` | Journal › Quests, with sample quests |
| `achievements` | Journal › Achievements: unlocked, in progress, hidden |
| `npc` | the NPC dialog with a sample NPC (text, keywords, shop) |
| `hotbar` | the hotbar settings sheet |
| `outfit` | the outfit screen for touch screens, with sample outfits |
| `settings-gameplay` … `settings-optimization` | the hub's Settings, one page per tab |
| `layout-panels` | the touch layout (no game) with Containers and Equipment open in their default places |
| `layout-lists` | the touch layout with the Map, Skills and the Hunt analyzer open (the oldest gives way when they do not all fit) |
| `layout-edit` | Edit layout with Containers and Equipment open: outlines, - and +, the "Customize Layout" window |

The `layout-*` pages are portrait on `iphone-portrait` and landscape on the
other phones and the tablet; desktop devices show a note (the desktop layout
has no touch pieces).

Screen pages get their data the way the game would, through the extended
opcodes (`ProtocolGame.onExtendedOpcode`), with fixed sample data. The clock
is pinned to 2026-01-01 12:00 so the hub's time never changes a screenshot.

Devices:

| Device | Screen | Pixel ratio | Notes |
|---|---|---|---|
| `phone-small` | 667×375 | 2 | |
| `phone-big` | 932×430 | 3 | |
| `phone-big-sharp` | 932×430 | 3 | Sharpness High |
| `tablet` | 1180×820 | 2 | |
| `iphone-portrait` | 393×660 | 3 | iPhone in portrait (the page area under Safari's toolbars) |
| `iphone-rotated` | 393×660 → 852×375 | 3 | opened in portrait, turned to landscape before the screenshot |
| `desktop` | 1366×768 | 1 | |
| `desktop-scale-1.5` | 1366×768 | 1 | interface scale 1.5 |

Add a page in `mods/client_gallery/gallery.lua` (`PAGES` and `PAGE_ORDER`)
and in `PAGES` in `gallery.js`.

## Text that doesn't fit

After a page is ready, the gallery checks every visible widget twice, a
second apart, and logs `[gallery] clipped ...` for what both checks find:

- **Cut off:** text wider than its widget (minus padding), when the widget
  doesn't wrap its text.
- **Covered:** text drawn under a button or switch it doesn't belong to, such
  as a setting's name under its row of choices.

Widgets scrolled out of sight are skipped. A page with such text fails, even
when it matches its baseline, and the report lists the widgets. Fix the
layout (shorter text, a wider widget, wrap, or move the control) rather than
updating the baseline.

## In CI

The "UI screenshots" job in `.github/workflows/web-build.yml` runs after the
browser build. It uses the build's artifact and needs no game server or
sprites.

- **Nothing changed:** the check passes.
- **A page changed:** the check fails. Download the `ui-gallery-<sha>`
  artifact and open `report.html` to see what changed.
- **The change is intended:** run the Web Build workflow on the branch
  (Actions › Web Build › Run workflow) with **update_baselines** ticked. It
  commits the new images to the branch.
- **A new page or device** has no baseline yet: it shows as "new" and passes.
  Update the baselines the same way.

Baselines come from CI only. Software rendering can differ slightly on
another machine, so a local run can report small differences.

## Locally

```sh
cd tools/ui-gallery
npm install && npx playwright install chromium
node gallery.js --bundle <browser build folder> --out out
node gallery.js --bundle <folder> --pages touch --devices phone-big   # a subset
```

The browser build folder holds `otclient.html`, `.js`, `.wasm` and `.data`
(the Web Build artifact, or `bin/` of a local build).
