# Ricelin pill on macOS

A selected-component port of Gakuseei/Ricelin's pill running in a native Cocoa window through public Qt Quick APIs. It is **not upstream Quickshell** and does not run arbitrary rices unchanged.

## Run

Requires Homebrew Qt 6.11.2, Xcode command-line tools, Rust/Cargo, the modified maccer checkout at `~/Documents/maccer`, and macOS 26. Set `MACCER_SOURCE` when building from another maccer checkout. This installed Qt itself targets macOS 26.

```sh
cd ~/pill-macos-spike
./scripts/build.sh
./scripts/run.sh --top-offset 2
```

The default top offset in src/main.cpp is 2 pixels. Use --top-offset 0 for a flush screen-top position or 44 to stack below omacosy. AppKit's menu-bar constraint is overridden for this window only. Nothing changes omacosy, AeroSpace gaps, or launchd.

At rest, the first five available workspace dots sit to the left of the clock and track the focused workspace. Hover the clock to widen into workspace switching, date, Spotify metadata and battery state. Click the clock or mixer glyph to pin/open the mixer. Escape, the close button, or an outside click dismisses it. The exit-arrow button quits. Left/Right selects an enabled fader; Up/Down adjusts it. Mouse dragging works too.

Volume LIVE and the brightness fader control supported hardware; the first speaker chip toggles mute. The second speaker chip opens a scrollable system panel with output selection, Wi-Fi/Bluetooth permission controls, Spotify actions, Accessibility menus, display shade, weather and confirmed power/theme/wallpaper actions. Night Shift is enabled only when its optional private API is available. Unsupported controls stay disabled. DND, keep-awake, microphone gain and Linux vibrance have no donor implementation.

## Shared Maccer service

Pill can be the only native frontend of the independent [Maccer backend](https://github.com/F1lmzy/maccer). Build against the matching Maccer checkout, quit existing GPUI/Pill instances, and configure the backend:

```toml
[launcher]
hotkey = "alt-space"

[service.frontend]
kind = "pill"
path = "~/pill-macos-spike/build/app/PillSpike.app"
```

Start `maccer-service --apps --socket PATH` with an existing private socket parent. Option-Space opens/refocuses Pill and launches it with the service environment when absent. No separate frontend launch is needed. Both service-mode native apps share a lifetime process lock; unselected GPUI and duplicate native processes refuse startup. Closing Pill leaves the backend and clipboard capture running. Restart frontends after a backend restart.

Shared mode supplies applications, Google/configured web search, scoped RAM-only clipboard history, rich previews, active theme state, catalog browsing and explicitly confirmed Apply. Direct Paste, files, calculator, shell and wallpaper changes have not migrated. Pill retains rows/icons/previews while typing but immediately revokes old action authority. It does not construct embedded Maccer providers or its native theme helper in this mode.

Follow the [Maccer setup and operations guide](https://github.com/F1lmzy/maccer/blob/main/docs/shared-service.md) for build/start commands, helper requirements and privacy limits, or [the local launcher contract](docs/launcher.md) for the Qt bridge. `scripts/run.sh` without `MACCER_SERVICE_SOCKET` still starts embedded mode. Quit an embedded Pill before using the backend shortcut because an existing process cannot receive a replacement environment through LaunchServices.

## Theme and embedded Appearance

In shared mode, Maccer owns the active palette and theme catalog. Pill's separate Appearance catalog and mutations are disabled; use Themes in the launcher. The following Appearance and wallpaper controls describe embedded mode.

The pill follows mac-themer's active palette from `~/.config/macthemer/current.json`, including text, accents, surfaces, selection colors and bar opacity. Rest, hover, mixer, launcher and system controls share it. Theme changes update the running UI through a directory watcher, with two-second reconciliation as a fallback. Nothing is copied from the mac-themer checkout or applied on startup.

A missing or invalid replacement keeps the last valid colors and reports a theme read error. Before any valid palette has loaded, Ricelin's original palette is the fallback. `MACTHEMER_STATE` and `MACTHEMER_HOME` can override the state location. Confirmed theme/wallpaper buttons use mac-themer's own installed helpers.

Open **Appearance** from the hover row's palette icon or the system panel for a 3x2 grid of the installed mac-themer packs. Each card is filled from its pack's background colour and shows that pack's accent and ANSI swatches with the name below; the active pack is ringed. Its **Backgrounds** button opens a filmstrip carousel of the active pack's images, focused on the one currently on screen. Arrow keys move the selection and Enter applies it; Escape cancels a staged confirmation, steps back from the carousel, then dismisses. Mouse selection keeps the two-step Apply/Cancel flow. Next cycles themes or backgrounds and Resync restores the current background on every display. Themes load on opening or Refresh; external palette and wallpaper changes reconcile automatically. Missing helpers, empty background folders and command errors are shown without inventing state.

Carousel previews are cached, so the strip paints immediately instead of decoding 300-500 KB originals. Previews are 512 px JPEGs generated in the background and stored under `~/Library/Caches/local.pill.macos-spike/wallpaper-thumbs/` (`PILL_THUMB_CACHE` overrides the location); a preview is keyed on the source path, mtime and size, so replacing an image in place refreshes it. `MACTHEMER_BIN`, `MACTHEMER_RUN` and `MACTHEMER_THEMES` override helper, background-state and theme-pack locations. Installed helpers are used through `~/.local/bin`, so the pill has no hardcoded dependency on the checkout path.

## Embedded launcher

Option-Space or your configured maccer shortcut opens a 480x380 launcher that morphs from the pill. Click the app-window glyph in the hovered pill to open it without a shortcut. After quitting the older pill instance, use `./scripts/run.sh --show-launcher` to open it immediately. Quit standalone maccer if it owns the same shortcut; registration failures appear in the launcher footer.

The app links maccer's Rust providers through a C ABI and a QML singleton, with no GPUI window or daemon. Search, ranking, provider prefixes, history and actions reuse maccer's configuration. Return activates, arrows navigate, Tab uses the secondary action, Cmd-K opens actions, and Cmd-P opens the provider picker. Escape returns from actions/output, then clears the query, then closes.

Clipboard capture follows maccer configuration and runs while the pill is resident. Unmarked passwords may enter its in-memory history; disable `[providers.clipboard].enabled` and restart to opt out. Paste, file previews and dragging are not integrated yet. Real IME input and native app activation still need interactive verification. See [the launcher contract and verification](docs/launcher.md).

## What is reused

Ricelin's motion durations/curve, vector glyphs, filament faders and PillSurface are reused. Its original palette remains the fallback; normal colors come from mac-themer. Pill.qml and Mixer.qml are reduced adaptations, not unchanged upstream files. The resting pill is 160x32 with up to five workspace dots beside the unchanged clock; hover is content-width x58, and mixer is 372x214, with original 18/22 px corners. Decorative kanji have been removed. Fonts fall back to macOS families.

See third_party/ricelin/SOURCE.md and LICENSE for upstream commit, source blocks, changes and Gakuseei's MIT notice. Runtime resources are embedded; /tmp/ricelin is not needed.

The flame-bead effect, tray, notifications, settings, recording and other unrelated upstream surfaces are omitted. The launcher uses a reduced Ricelin layout with maccer results.

## Native integrations

The full omacosy native/system integration set is connected through the Swift/Qt boundary. The
omacosy donor revision, copied Audio ranges and Paul Spende's MIT notice are
recorded in third_party/omacosy. The omacosy, Ricelin and maccer licenses are packaged with the app.

Pill.MacOS 1.0 exports Bridge.ready, Audio, System and Maccer. Audio uses native notifications,
reprobes on default-device changes and reports independent read/write support.
Reads/writes run off the UI thread; drag feedback is separate from observed
state and a device/display change cancels the current drag. See docs/native-services.md
for Audio and docs/integrations.md for all service contracts, permission policies,
notification/reconciliation fallbacks and verification limits.

Real-device reads and fake-service regressions have passed. Real
writes/restoration, hotplug and native-input acceptance remain manual.
Read-only snapshots from every real service have passed; permission
grants, private display writes, Bluetooth/WM/helper actions remain manual checks.
Normal scripts/run.sh now launches through LaunchServices for app-owned privacy
prompts. Permissions are requested only through buttons, never startup or tests.

The build generates the Swift library/header under build/native and packages
the library inside PillSpike.app/Contents/Frameworks. It supports one native
architecture matching Homebrew Qt.

## Local Quickshell subset

qml/modules/Quickshell exports only:

- PanelWindow, a real Qt Quick Window with top-only panelAnchors, implicitWidth/implicitHeight and transparent tool-window flags.
- Singleton, a QtObject container supporting child objects.
- SystemClock, with Seconds/Minutes precision and date.
- Quickshell.screens, using Qt's screen objects.

The native host attaches to the single root PanelWindow in qml/shell.qml. That root exposes its pill Item through an alias. Loading PanelWindow in another ordinary Qt app does not supply our Cocoa panel behavior.

Anchor declarations are validated at startup. The host supports one bounded top panel on the primary screen; anchors are not a dynamic layout API. No exclusive zones, full-screen input masks, Variants, Io, Hyprland, Wayland or service modules are implemented. The active mac-themer palette is observed; explicit confirmed theme/background changes go through its CLI. Upstream wallpaper-to-palette Dyn generation is not included. No fake Linux services are exposed.

## Verify

```sh
./scripts/test.sh
# Quit any running pill before the real-input test:
./scripts/native-input-test.sh
```

The first command runs Audio property fixtures, Swift/Qt callback and teardown tests, geometry, module-import and QML interaction tests, then native Cocoa geometry/stacking checks from a relocated app bundle without DYLD search-path overrides. Every service is explicitly fake in all automated checks, including self-test mode. It requires a logged-in GUI session. Screenshots of this app alone are written to build/screenshots/{collapsed,hover,mixer,system,launcher,appearance}.png and wait for visible content, not just final frame size.

The second command uses a disposable native fixture and real WindowServer input. It restores pointer/focus afterward and never requests permissions. It exits 77 without existing event-posting permission, or 2 if another PillSpike instance is running. It verifies corner click-through while the hovered pill is above the fixture, actual Qt fader hover/click delivery, consumed outside dismissal, resumed desktop clicks and actual Escape.

The native self-test does not inject WindowServer input. Negative-level idle windows are absent from CGWindowList, so idle geometry is checked in-process while real-input tests observe the raised window. The offscreen QML runner may print Qt's generic Sans Serif font-alias timing warning; the native app uses an explicit installed font.

Use --test-services for labelled in-memory fixtures instead of real hardware.
--test-audio remains a legacy alias that now makes every service fake.
The real-input harness supplies this flag and waits for confirmed fixture
updates. --trace-preview logs mixer focus and local feedback; in fixture mode
it also logs confirmed test values. Normal startup does not log system state.

Read-only native snapshots, with no actions or permission requests:

    ./scripts/system-read-test.sh

A separate Audio probe is safe to run without changing audio:

    ./scripts/audio-live-test.sh --read-only

Real-device write verification is opt-in and temporarily changes volume/mute:

    PILL_AUDIO_HARDWARE_TEST=1 ./scripts/audio-live-test.sh --write-and-restore

It captures individual channel values and restores them and mute on failure
or success. Do not disconnect/switch devices during the test. A failed restore
is reported explicitly and exits nonzero.

Built-in brightness has a separate opt-in change/restore check:

    PILL_DISPLAY_HARDWARE_TEST=1 ./scripts/brightness-live-test.sh --write-and-restore

Do not change displays during this test. Private Night Shift/gamma, permission
flows and destructive/helper actions are never exercised automatically.

## Window/input limits

The window covers only the current pill rectangle. A 16 ms sampler toggles ignoresMouseEvents for rounded corners using the animated radius. Pointer entry followed immediately by a click can race that sample. Hover raises the panel without keyboard activation. Opening takes focus; restoration on close is best effort.

Idle level is -20, hover/open level is 3. The host keeps it raised through sizing and content fades because Qt can pause animations on occluded Cocoa windows. An open-only transparent level-2 catcher consumes the outside dismissal click rather than replaying it into another app.

Primary display only. The notch branch sits left of the notch and is not tested on notched hardware. Omacosy remains running, so the two bars can overlap. No launch agent is installed.
