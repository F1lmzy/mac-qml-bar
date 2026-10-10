# Ricelin pill on macOS

A selected-component port of Gakuseei/Ricelin's pill running in a native Cocoa window through public Qt Quick APIs. This is step 2 after the original window spike. It is **not upstream Quickshell** and does not run arbitrary rices unchanged.

## Run

Requires Homebrew Qt 6.11.2, Xcode command-line tools, and macOS 26. This installed Qt itself targets macOS 26.

```sh
cd ~/pill-macos-spike
./scripts/build.sh
./scripts/run.sh --top-offset 2
```

The existing local 2-pixel default in src/main.cpp is preserved as your uncommitted edit. Use --top-offset 0 for a flush screen-top position or 44 to stack below omacosy. AppKit's menu-bar constraint is overridden for this window only. Nothing changes omacosy, AeroSpace gaps, or launchd.

Hover the clock to widen into workspace dots, date and media preview. Click to pin/open the mixer. Escape, the close button, or an outside click dismisses it. The exit-arrow button quits. Left/Right selects an enabled fader; Up/Down adjusts its local preview value. Mouse dragging works too.

Workspace dots and media are placeholders. The mixer is labelled PREVIEW. Brightness, volume and mic faders change only local values, never hardware. Linux vibrance, device selection, DND, keep-awake and night-light controls are disabled.

## What is reused

Ricelin's palette, motion durations/curve, vector glyphs, filament faders and PillSurface are reused. Pill.qml and Mixer.qml are reduced adaptations, not unchanged upstream files. The rest clock is 160x38, hover is content-width x58, and mixer is 372x214, with original 18/22 px corners. Fonts fall back to macOS families.

See third_party/ricelin/SOURCE.md and LICENSE for upstream commit, source blocks, changes and Gakuseei's MIT notice. Runtime resources are embedded; /tmp/ricelin is not needed.

The flame-bead effect, tray, notifications, launcher, settings, recording, wallpaper and other surfaces are omitted.

## Native service checkpoint

PLAN.md tasks 1 and 2 are complete. The omacosy donor revision, local changes,
service extraction map and Paul Spende's MIT notice are recorded in
third_party/omacosy. No hardware service code has been copied or connected.

The app now loads an in-process Swift library through an Objective-C++ Qt
adapter. Pill.MacOS 1.0 exports only Bridge.ready, a callback-health property,
not simulated system state. All visible controls retain their preview/disabled
behavior. See docs/native-services.md for ownership rules and the proposed
Audio contract for the next checkpoint.

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

Anchor declarations are validated at startup. The host supports one bounded top panel on the primary screen; anchors are not a dynamic layout API. No exclusive zones, full-screen input masks, Variants, Io, Hyprland, Wayland or service modules are implemented. Static theme mode is read-only; upstream Theme's unused Dyn branches are unreachable. No fake Linux services are exposed.

## Verify

```sh
./scripts/test.sh
# Quit any running pill before the real-input test:
./scripts/native-input-test.sh
```

The first command runs Swift/Qt callback and teardown tests, geometry, module-import and QML interaction tests, then native Cocoa geometry/stacking checks from a relocated app bundle without DYLD search-path overrides. It requires a logged-in GUI session. Screenshots of this app alone are written to build/screenshots/{collapsed,hover,mixer}.png and wait for visible content, not just final frame size.

The second command uses a disposable native fixture and real WindowServer input. It restores pointer/focus afterward and never requests permissions. It exits 77 without existing event-posting permission, or 2 if another PillSpike instance is running. It verifies corner click-through while the hovered pill is above the fixture, actual Qt fader hover/click delivery, consumed outside dismissal, resumed desktop clicks and actual Escape.

The native self-test does not inject WindowServer input. Negative-level idle windows are absent from CGWindowList, so idle geometry is checked in-process while real-input tests observe the raised window. The offscreen QML runner may print Qt's generic Sans Serif font-alias timing warning; the native app uses an explicit installed font.

Use --trace-preview to log local mixer focus/value changes to stderr for input diagnostics. Nothing is logged by this option unless enabled; no system-state data is collected.

## Window/input limits

The window covers only the current pill rectangle. A 16 ms sampler toggles ignoresMouseEvents for rounded corners using the animated radius. Pointer entry followed immediately by a click can race that sample. Hover raises the panel without keyboard activation. Opening takes focus; restoration on close is best effort.

Idle level is -20, hover/open level is 3. The host keeps it raised through sizing and content fades because Qt can pause animations on occluded Cocoa windows. An open-only transparent level-2 catcher consumes the outside dismissal click rather than replaying it into another app.

Primary display only. The notch branch sits left of the notch and is not tested on notched hardware. Omacosy remains running, so the two bars can overlap. No launch agent is installed.
