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

The pages are in [`mods/client_gallery/pages/`](../../mods/client_gallery/pages),
one file per page or group of pages, loaded in file name order (the order of
the report). Each page says what it shows in its `about` text, which the
report shows next to its name (and the report lists them all). There is no
list of pages anywhere else, so pull requests that add pages don't touch the
same lines.

### Adding a page

Add a file to `mods/client_gallery/pages/` (a new number, so it sorts where
you want it in the report), and nothing else: `gallery.js` asks the client
for its pages (`gallery = '@list'`), and no image goes into the pull request.

```lua
-- pages/110-messages.lua
return function(G)
    G.page('messages', { about = 'what the page shows' }, function(page)
        local c = G.column(page, 560)
        -- ...
    end)
end
```

- `G.page(name, options, build)`: `options.about` says what the page shows;
  `options.keyboard = true` shows it with the on-screen keyboard open, on
  touch devices only (below). `build(page)` fills the page; it may return
  windows of its own that existed before it, and `true` to skip the fit
  checks on them (a whole game screen).
- Helpers: `G.widget`, `G.section`, `G.button`, `G.holder`, `G.centered`,
  `G.column`, `G.roundFace`, `G.receive` (what the server would send on an
  extended opcode), `G.tap`, `G.findByText`, `G.openHub`, `G.FIXED_TIME`.
- Styles of the page's own: `pages/<same name>.otui` (every `.otui` there
  is imported with `gallery.otui`), so they don't go into the shared file.
- `mods/` is in `.gitignore`: add new files with `git add -f`.

The `layout-*` pages are portrait on `iphone-portrait` and landscape on the
other phones and the tablet; desktop devices show a note (the desktop layout
has no touch pieces). They have no gallery backdrop behind the game screen,
so they show what the device shows (the stone around the game view).

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

The keyboard pages set `keyboardVisibleTop/Bottom` the way the page does
while the keyboard is open (`browser/shell.html`), for a keyboard 300 px high
in portrait and 210 px in landscape. Real keyboard heights vary by phone.

## Text and widgets that don't fit

After a page is ready, the gallery checks every visible widget twice, a
second apart, and logs `[gallery] clipped ...` or `[gallery] outside ...` for
what both checks find:

- **Cut off:** text wider than its widget (minus padding), when the widget
  doesn't wrap its text.
- **Covered:** text drawn under a button or switch it doesn't belong to, such
  as a setting's name under its row of choices.
- **Outside:** a widget that sticks out of its parent, or off the screen,
  such as a row of buttons wider than its sheet. The rows of a scrolled list
  are left out: the list cuts them off on purpose.

Widgets scrolled out of sight are skipped. A finding fails the check, image
changed or not, unless the baseline has it already:
`baseline/doesnt-fit.txt` lists the findings of the last run on
web-client-792 (`device/page: finding`, numbers left out, since widget ids
and positions move when anything else does). So a pull request fails only on
what it adds; ones already on the base branch are listed in the summary
without failing. Fix the layout (shorter text, a wider widget, wrap, or move
the control).

## In CI

The "UI screenshots" job in `.github/workflows/web-build.yml` runs after the
browser build. It uses the build's artifact and needs no game server or
sprites.

- **On a pull request** the screenshots are compared with the base branch's
  `baseline/` (pull requests carry no baseline images; one that does gets a
  warning, and its images are not used). The job summary lists changed and
  new pages; the `ui-gallery-<sha>` artifact has `report.html` with the new
  image, the baseline and a diff (red).
- **Changed or new images do not fail the check.** Look at them in the
  summary and the report.
- **The check fails** on a page that fails to load or doesn't render, a page
  that has a baseline image but is no longer in the run (a page file that
  failed to load, or a removed page), and a doesn't-fit finding that
  `baseline/doesnt-fit.txt` doesn't have.
- **After a push to web-client-792** (a merge), the run saves its images
  (changed and new ones), its findings and the removal of gone pages as the
  new baseline, and commits them to web-client-792 as github-actions[bot].
  That commit starts no workflow (it is pushed with the workflow's token),
  so there is no second run and no new pre-release. If web-client-792 moved
  on during the run, it commits nothing: the newer push's run does it.
- **By hand:** Actions › Web Build › Run workflow with **update_baselines**
  ticked does the same on the branch it runs on (meant for web-client-792,
  for instance after a run that failed).

Baselines come from CI only. Software rendering can differ slightly on
another machine, so a local run can report small differences.

## Locally

```sh
cd tools/ui-gallery
npm install && npx playwright install chromium
node gallery.js --bundle <browser build folder> --out out
node gallery.js --bundle <folder> --pages touch --devices phone-big   # a subset
```

`out/summary.md` says what was found; the exit code is 1 when the check
would fail.

The browser build folder holds `otclient.html`, `.js`, `.wasm` and `.data`
(the Web Build artifact, or `bin/` of a local build).
