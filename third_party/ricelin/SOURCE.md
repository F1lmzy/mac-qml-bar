# Ricelin source and license

Upstream: https://github.com/Gakuseei/Ricelin
Commit: 210975402418bb5eed60a40b5bc89c006c7d741e
License: MIT, copyright 2026 Gakuseei. See LICENSE in this directory.

The source paths below are relative to configs/quickshell/pill.

- qml/ricelin/GlyphIcon.qml, VFader.qml, PillSurface.qml: upstream copies.
- qml/ricelin/Singletons/Motion.qml: upstream copy.
- qml/ricelin/Singletons/Theme.qml: upstream palette and helpers; Japanese font adapted to an available macOS family.
- qml/Pill.qml: reduced adaptation of upstream Pill.qml, particularly geometry/morph blocks at lines 158-176 and 545-630, body/sheens at 698-738, rest clock at 1264-1350, hover clock at 1352-1433. Linux surfaces, notifications, drag/install, tray, flame-bead effects and other services are omitted.
- qml/ricelin/Workspaces.qml: upstream dot drawing/layout; Hyprland/rule model replaced by explicit placeholder data; switching disabled.
- qml/ricelin/Mixer.qml: adapted upstream header/divider/fader layout and focus logic; hardware/Pipewire commands removed, local preview values substituted, unsupported actions disabled.

qml/modules/Quickshell is our public-Qt subset, not copied upstream Quickshell.
No files depend on the temporary /tmp checkout at runtime.
