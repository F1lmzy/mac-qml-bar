# Step 1: macOS pill spike

An isolated, disposable Qt Quick prototype, not a Quickshell port.

- A warm dark, top-centred capsule morphs on hover, pins on click, and grows into a mixer demo.
- The QML rectangle and native window resize together with a fixed top-centre anchor.
- Collapsed Cocoa window uses level -20 and joins all Spaces. Expanded panel rises above ordinary app windows.
- Window covers only the pill bounds. Native pointer sampling makes transparent rounded corners click-through. Sampling has a small first-click race; this spike measures the approach, not production input routing.
- An expanded-only transparent catcher below the pill dismisses it on outside click. The dismissing click is consumed, not replayed into another app.
- Escape closes the panel, Quit exits. No global key interception or elevated permissions.
- Default position avoids the notch. --top-offset allows stacking below an existing bar. No gap/config/launchd changes.
- Primary display only. Real system widgets, Quickshell API compatibility, automatic launch and multi-display panels are out of scope.

Verification: geometry unit tests, QML interaction/animation tests, native self-test, screenshots, and a live run. Demo sliders do not change system volume/brightness.
