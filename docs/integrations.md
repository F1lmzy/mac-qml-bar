# Full donor integration contract

Scope: every native/system integration in omacosy's bar, including
permission-gated controls. The donor source/revision and adaptations are listed
in third_party/omacosy/SOURCE.md. No donor process, configuration or shared hook
file changes. No donor helper has been executed during development.

## Boundary

Pill.MacOS.System exposes read-only maps for brightness, display, battery, wifi,
bluetooth, spotify, desktop, menus, weather, theme, outputDevices and windowManager.
Each carries available, lastErrorCode, lastError and capability-specific fields.
invoke(domain, action, argument) is a bounded dispatcher, never a shell or
AppleScript interface. Audio remains the normalized output volume/mute service.
Unknown values are gated by known flags; unsupported actions stay disabled.

Services own their main-thread snapshots, callbacks, observers and timers.
Blocking reads/actions use serial utility queues capturing drivers/values,
not service instances. Stop cancels pending operations, owned child processes,
timers/sources and generation-tagged deliveries. The Qt adapter converts
QML object arguments explicitly and posts context-bound property updates.

## Services and actions

| Map | State and bounded actions |
| --- | --- |
| brightness | Built-in displayId, known, value 0..1, canSet. set({value,displayId}); nonfinite rejection, finite clamp, display revalidation, coalesced requests, confirmed reads. |
| display | screens, nightShiftKnown/Enabled, canSetNightShift, shade, canShade. setNightShift(bool), setShade(0..1). |
| battery | Internal-battery known/charge/charging/onAC. No writes. No battery or UPS-only sources are unavailable. |
| wifi | power, interface, IP/router, RSSI/rate/channel/security and separately permitted SSID. requestPermission, openSettings. No coordinate requests. |
| bluetooth | permission, paired devices, connected state and optional power read. requestPermission, connect/disconnect({id}), openSettings. No classic API access before authorization. |
| spotify | running, known title/artist/album, playback state. requestPermission, refresh, previous, playPause, next. Notifications prime metadata without Apple Events; actions/queries may request Automation. |
| desktop | Remembered non-Pill front app, system capability flags. openSettings; confirmed lock/sleep/restart/shutDown. |
| menus | AX permission, frontPid, navigable items and breadcrumb. requestPermission, refresh, open({index,pid}), back, press({index,title,pid,confirmed:true}). Unknown/disabled leaves cannot be activated. |
| weather | Opt-in wttr.in conditions and timestamp. refresh is explicit initial consent; enable(false) cancels future requests. Provider receives the client's public IP. |
| theme | Observed mac-themer name, slug, variant, validated palette, themes (with pack swatch colours), wallpapers (with a cached `thumb` URL), backgroundPath/backgroundUrl, catalogLoading/catalogError, thumbnailsReady and busy. Read-only catalog; confirmed next, select({slug}), nextBackground, setBackground({path,slug}) and resyncWallpaper. |
| outputDevices | Current output rows and settable default-output capability. select(id), revalidated before write and reread/listened afterward. Input gain/selection has no donor implementation. |
| windowManager | Backend, global focused workspace/window, real workspace/monitor/window rows and explicit switchWorkspace(id)/focusWindow(id). AeroSpace and donor-shaped OmniWM snapshots. OmniWM window focus is unsupported. |

The theme service reads mac-themer's schema-1 `current.json` from
`~/.config/macthemer/`, or `MACTHEMER_STATE` under the configured
`MACTHEMER_HOME`. It publishes the validated document as `theme.palette`.
Reads run on the worker and are capped at 64 KiB. Schema, required color roles,
`#RRGGBB` values and `alpha_byte` are validated before publication.
The directory watcher survives atomic file replacement; two-second reconciliation
handles a state directory that appears later. Stop cancels the watcher and reads.
Read failures preserve the last good palette with `available: true` and
`lastErrorCode`/`lastError`. A cold failure has `available: false` and an
empty palette, so QML uses the Ricelin fallback. No shell fragment is evaluated.

`Theme.qml` maps mac-themer's bar label/icon/muted/accent/item colors and
semantic elevation/outline roles to existing component tokens. Search selection
uses the published ANSI selection pair. The pill applies the published bar alpha
without changing its geometry. Confirmed `next` calls `mac-themer next`;
`resyncWallpaper` calls `macthemer-wallpaper resync` with mac-themer's
remembered background. Missing helpers or background disable the control.
Helper locations honor `MACTHEMER_BIN` and `MACTHEMER_RUN`; palette reads
alone never apply a theme or wallpaper. Fixture mode uses an in-memory palette,
not personal files.

The Appearance surface opens from the hover palette icon or system header and
shows the installed packs as a 3x2 card grid. Each card is filled from the
pack's own background colour and carries its accent and ANSI swatches, read
from `themes/<slug>/theme.toml` `[palette]`, falling back to the generated
`colors.toml`; `MACTHEMER_THEMES` overrides the pack directory. A pack whose
palette cannot be read publishes empty colour strings, and the card falls back
to the live `Theme` tokens rather than a guessed value.

Backgrounds have their own filmstrip surface, reached from the grid's
`Backgrounds` button. Both surfaces take arrow keys for selection and Enter to
apply; Escape cancels a staged confirmation before it steps back or dismisses.
It requests `catalog`, which runs `mac-themer list --json` only on demand.
The catalog validates unique slugs and names, up to 512 entries and 64 KiB.
Wallpaper rows contain `path`, local file `url`, `name` and a cached `thumb`
URL, enumerated on the worker from the `current` symlink's pack/backgrounds
folder. Supported suffixes match mac-themer: jpg, jpeg, png, webp, heic and
tiff. The UI displays at most 256 sorted backgrounds; unavailable image
decoders show a placeholder.
`backgroundPath`/`backgroundUrl` describe mac-themer's remembered symlink, not
an independent query of each display. Background changes reconcile every two
seconds and immediately after a successful command.

Carousel previews come from a persistent cache under
`~/Library/Caches/local.pill.macos-spike/wallpaper-thumbs/`, with
`PILL_THUMB_CACHE` overriding the location. The key covers the source path,
mtime and size, so a wallpaper replaced in place yields a new preview instead
of a stale one. Keys use SHA-256 rather than Swift's per-process-seeded
`Hasher`, so the cache survives a relaunch. Previews are 512 px JPEGs, measured
at 27-42 KB against 306-492 KB sources, and are generated on the reconciliation
path rather than on surface open, so the strip is normally warm before it is
shown. A pass skips files that already have a preview and remembers failed
attempts by cache key, so a repeat poll is stats and no writes. Unreferenced
previews are pruned after each pass and the directory is capped at 128 MiB,
oldest first. `thumbnailsReady` reports whether every row has a preview; an
empty `thumb` means the carousel falls back to the full-size file for that row.
JPEG drops alpha, which is fine for wallpapers and keeps the cache small.

Every mutation requires `{confirmed:true}`. `select` calls `mac-themer set <slug>`;
`nextBackground` calls `mac-themer bg-next`; `setBackground` supplies an exact
catalog path and pins the active slug. A stale theme, removed image or path
outside the active catalog is rejected before execution. Busy state blocks
concurrent mutations. Command failures remain visible until a later successful
mutation; success refreshes observed state rather than optimistically marking
selection. Closing cancels an unconfirmed choice, not an already running command.
The helper environment prepends `/opt/homebrew/bin` and `/usr/local/bin` to PATH
so LaunchServices can find Python 3.11+ rather than Apple's Python 3.9. No shell
interpolation is used. The mac-themer checkout and daemon are unchanged.

AeroSpace uses a bounded single-read NDJSON subscription. Confirmed focus events
publish the workspace highlight immediately and start background reconciliation;
older in-flight snapshots cannot revert it. Non-focus events coalesce over 120 ms.
Reconnect backoff is 1–30 seconds, with 15-second reconciliation for hidden moves.
OmniWM's watch stream was not verified and is not claimed supported; its
snapshots reconcile every 15 seconds. Model changes cancel queued action leases;
AeroSpace actions requery target IDs before executing. Named/empty workspaces
are preserved and floating windows count. AeroSpace's specific `No window is focused` response from `list-windows --focused` is normal absence, not a failed workspace snapshot. The workspace rows remain available on an empty workspace; previous-app focus is retained only within the same workspace. Timeouts, permission errors and other CLI failures still invalidate the snapshot. OmniWM IDs are monitor-scoped, and
ambiguous duplicate raw workspace names are unavailable unless a window row
supplies its monitor association. The UI shows global workspaces and monitor associations, not a guessed
Qt/CoreGraphics-to-WM monitor mapping. It renders at most five resting dots and eight hover dots;
the details panel lists the remaining rows.

## Privacy and private APIs

Permission requests occur only on explicit buttons. The bundle declares its
own Location, Bluetooth and Apple Events purpose strings. Accessibility opens
the native trust prompt only on request. Bluetooth and Location requests require
LaunchServices launch, not a Terminal child, to avoid the donor's documented
responsible-process/TCC hazards. scripts/run.sh uses open for normal launch;
--test-services/--test-audio/--self-test execute directly with every service fake.
The bundle is locally ad-hoc signed; it is not notarized. Privacy grants may
need renewal after rebuilding and are not inherited from omacosy.

DisplayServices/CoreBrightness are dynamically resolved and restricted to
macOS major version 26. Missing symbols disable controls. Private ABI is still
a maintenance risk, not a public API promise. Brightness and Night Shift refresh
every 2–3 seconds plus display/wake events because safe private unsubscribe
contracts were unavailable. Bluetooth uses app-activation refresh and ten-second
authorized reconciliation instead of unmanaged classic callbacks. Wi-Fi retains
dynamic-store notifications plus five-second reconciliation.

Gamma shade is separate from brightness. It captures exact RGB transfer tables,
checks topology and ownership, reads back writes, rolls back partial failure and
restores only tables unchanged since Pill's last write. Another color filter can
invalidate ownership; Pill refuses to overwrite that change. Restoration errors
are logged. Normal quit allows a bounded two-second worker drain; a timeout is
logged rather than blocking shutdown indefinitely. No shade is applied or persisted at startup. Do not use this alongside
other gamma controllers, and restore shade before quitting or force-killing Pill.

Power and AX leaf actions require a second confirmation, cleared on close or
menu-model change. A confirmed WM focus/workspace change drops the host's old
application restoration so dismissal does not jump back to an earlier workspace.
All external text renders as plain text, not rich markup.

DND, keep-awake, mic gain and Linux vibrance have no donor implementation.
SkyLight private window-event hooks are not needed for supported WM events and
are not imported. Bar drawing, cheatsheet, icon palettes, calendar popup and
automatic workspace-fold/wallpaper startup behavior are donor presentation or
side effects, not additional macOS APIs. The local clock/date remain native Qt.

## Verification and limits

scripts/test.sh passes property/policy/parsing fixtures, stale-WM/backend-change
fixtures, 8 Audio bridge, 10 System bridge, 9 boundary, 5 geometry and 61 QML
cases, plus a relocated signed bundle's fake-service/native geometry checks.
Pending deletion, repeated stop/start and deletion during delivery are covered.
The system and Appearance panels are captured in build/screenshots/system.png
and build/screenshots/appearance.png. Appearance fixtures cover confirmation,
cancellation, observed selection, stale theme changes, busy/unavailable states
and local-file thumbnail decoding. Helper argv and GUI-launch PATH are verified
with temporary owned helpers, never live desktop writes. A read-only live
appearance probe under the minimal GUI PATH loaded Gruvbox Dark, four themes
and five backgrounds from the installed mac-themer. It did not invoke mutations.

scripts/system-read-test.sh successfully received a read-only snapshot from all
12 real integrations without invoking actions, prompting or fetching weather.
It checks integration cleanup. Standalone permission state belongs to the probe's
responsible process, so it does not prove grants for the actual app.

Real permission grants/denials, Bluetooth connections, power/helper actions,
private Night Shift/gamma writes/restoration, display hotplug, WM writes/restarts
and multi-display interactions still need manual validation. The real-input
harness remains deferred while the user's PillSpike instance is running.
No live writes have been exercised or claimed verified. Separate opt-in audio
and brightness commands capture/restore settings; they never run from test.sh.
