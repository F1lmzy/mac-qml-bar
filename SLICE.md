# Ricelin compatibility slice

Source: Gakuseei/Ricelin at 210975402418bb5eed60a40b5bc89c006c7d741e, configs/quickshell/pill.
Keep the local --top-offset default of 2 pixels. Do not modify omacosy.

## Scope

- Load shell.qml with a real top-level Quickshell.PanelWindow. This local module wraps Qt Quick Window and the existing Cocoa host; it is not upstream Quickshell.
- Implement only PanelWindow, Singleton, SystemClock and Quickshell.screens. No Process, FileView, Hyprland, Wayland, exclusive zones or other services.
- Reuse Ricelin's Theme, Motion, GlyphIcon, VFader and PillSurface. Adapt Pill.qml's geometry, body, rest/hover clock and cross-fade blocks, Workspaces.qml's dot drawing and Mixer.qml's header/fader layout.
- Preserve rest 160x38, hover height 58 with content-derived width, mixer 372x214, 18/22 px corners, glide/morph duration and bezier curve. Window geometry and input rounding follow these values.
- Static flame/washi palette. macOS font fallback only. Placeholder workspace dots and media metadata. Mixer explicitly marked PREVIEW; brightness/audio faders change only local preview values. Vibrance, device switching, DND, keep-awake and night light disabled.
- Keyboard close and fader adjustment, outside-click dismissal, click-through and Quit must continue to work.

## Acceptance

- QML import smoke test creates a PanelWindow, verifies default content parenting and sizes, uses screens/SystemClock/Singleton; unsupported declarations must fail or have an explicit error rather than silently simulate services.
- QML tests cover original dimensions/motion, hover/leave, pin/close/Escape, preview fader steps and clamping, disabled Linux controls, theme identity and placeholder models.
- Native test verifies screen-top offset, negative idle level, raised morph/open, synchronized sizing, content fade completion and catcher lifecycle using QML geometry, with collapsed/hover/mixer images.
- Real WindowServer test checks rounded corner pass-through above the fixture, actual Qt fader hover/click delivery, consumed dismissal and Escape. Optional --trace-preview logs only local preview transitions for that check.
- Resource build loads without import/type/binding errors. Images are inspected. README describes this exact subset and third_party/ricelin records provenance and modifications.

This is a selected-component port. The original 2,481-line Pill.qml and 626-line Mixer.qml will not load unchanged. No claims of arbitrary rice compatibility.
