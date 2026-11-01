# Ricelin source and license

Upstream: https://github.com/Gakuseei/Ricelin
Commit: 210975402418bb5eed60a40b5bc89c006c7d741e
License: MIT, copyright 2026 Gakuseei. See LICENSE in this directory.

The source paths below are relative to configs/quickshell/pill.

- qml/ricelin/GlyphIcon.qml, VFader.qml, PillSurface.qml: upstream copies.
- qml/ricelin/Singletons/Motion.qml: upstream copy.
- qml/ricelin/Singletons/Theme.qml: upstream palette retained as the cold-start fallback and font/helpers adapted to macOS; normal colors now follow mac-themer's published semantic palette.
- qml/Pill.qml: reduced adaptation of upstream Pill.qml, particularly geometry/morph blocks at lines 158-176 and 545-630, body/sheens at 698-738, rest clock at 1264-1350, hover clock at 1352-1433. Linux surfaces, notifications, drag/install, tray, flame-bead effects and other services are omitted.
- qml/ricelin/Workspaces.qml: upstream dot drawing/layout; Hyprland/rule model replaced by explicit placeholder data; switching disabled.
- qml/ricelin/Mixer.qml: adapted upstream header/divider/fader layout and focus logic; hardware/Pipewire commands removed, local preview values substituted, unsupported actions disabled.
- qml/ricelin/SearchField.qml: adapted upstream search layout and signals; visible native caret retained, composition keys left to the IME, input object name added for testing.
- qml/ricelin/Launcher.qml: reduced adaptation of upstream Launcher.qml search/list layout and stationary-pointer selection guard. DesktopEntries, JS fuzzy ranking, usage-file writes, Linux processes, calculator JS and AppImage editing/install are replaced by the embedded maccer provider service. Fixed body is 480x380 instead of upstream 360x332.
- qml/ricelin/WallpaperCarousel.qml: adapted from upstream Wallpaper.qml, keeping the filmstrip geometry and motion (slotW/slotH/slotCX/slotBright/slotSat, the `pos` chase through FrameAnimation, per-tile brightness/saturation/corner/edge-fade and wheel stepping). DuckDuckGo search and SearchField, trash/HeatHold, the per-screen mini-map, MediaPlayer/AnimatedImage previews, ffprobe dimension probes, inline folder editing, the kanji glyph, all Quickshell.Io processes and the Walls singleton are omitted. Wallpaper data comes from the native theme service, and tiles bind a cached preview before the full-size file.
- qml/ricelin/Appearance.qml: not reused from upstream. Upstream Appearance.qml is a settings row list for palette mode, scale and motion; this surface is a mac-themer theme card grid, so only the shared PillSurface/ActionButton chrome style is common.

qml/modules/Quickshell is our public-Qt subset, not copied upstream Quickshell.
No files depend on the temporary /tmp checkout at runtime.
