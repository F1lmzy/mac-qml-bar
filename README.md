# macOS pill spike

Step 1 only: a small Qt Quick pill in a native macOS window. No Quickshell dependency, no system controls, no changes to omacosy or AeroSpace.

## Run

Requires the installed Homebrew Qt 6.11.2, Xcode command-line tools, and macOS 26. This Qt installation itself targets macOS 26.

```sh
cd ~/pill-macos-spike
./scripts/build.sh
./scripts/run.sh
```

Default top offset is **0**, matching omacosy's 0..34 screen strip. A per-instance native `constrainFrameRect` override prevents AppKit pushing the window below the menu bar. It stays centred on flat displays. The notch branch places it left of the notch, but that branch has not been tested on a notched display.

Hover to widen. Click to pin/open the mixer. Escape, the close button, or an outside click dismisses it. The Quit button exits. Sliders are demos and do not change system settings. Existing omacosy remains running, so both bars may overlap.

Optional stacking for comparison:

```sh
./scripts/run.sh --top-offset 44
```

No launch agent is installed. Stop a terminal-launched instance with Ctrl+C. Quit a background instance through the mixer.

## Verify

```sh
./scripts/test.sh
```

Includes two geometry tests, six QML interaction tests, plus setup/cleanup cases, and native Cocoa checks. Native checks require a logged-in GUI session and render `build/screenshots/{collapsed,hover,mixer}.png`. The screenshots contain only this app's pixels.

The native self-test verifies window placement, level changes, resizing, catcher lifetime, and delivery from native callbacks into QML. It does **not** inject WindowServer input. For actual native input, quit any running pill and run:

```sh
./scripts/native-input-test.sh
```

This briefly moves the pointer and opens a disposable click-observation window, then restores pointer/focus. It requires existing event-posting permission and exits 77 if unavailable. It never requests new permissions. It verifies real hover, corner click-through while the pill is above another window, click-to-pin, outside-click consumption, resumed desktop clicks, and real Escape. Negative-level windows don't appear in CGWindowList, so the test observes hovered/open windows and relies on the in-process checks for idle geometry.

## Input/window decisions

The window covers only the current pill rectangle. A 16 ms pointer sampler toggles `ignoresMouseEvents` for transparent rounded corners. This has a small first-click race if pointer entry and click happen between samples. Hover raises the panel to floating level without taking keyboard focus. The Cocoa host prevents tool-window auto-hiding and restores stacking if Qt resets the level when another app activates. Clicking open activates it so Escape and Tab can work.

Idle level is -20, like omacosy. Hover/open level is 3. Qt can pause animations when a Cocoa window is occluded; raising and ordering it forward before animation, and lowering it only after closing finishes, avoids that stall.

An open-only transparent full-screen catcher at level 2 consumes an outside dismissal click. It does not replay the click into another app. It disappears immediately on dismissal. Focus restoration is best effort.

Single primary display only. No multi-display panels, real audio, workspace IPC, tray, clipboard history, or Quickshell API compatibility yet.
