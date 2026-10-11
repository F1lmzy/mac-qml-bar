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
| theme | Read-only donor theme name and helper availability. Confirmed next and resyncWallpaper. These alter the donor-managed desktop only after user confirmation. Pill retains the Ricelin palette. |
| outputDevices | Current output rows and settable default-output capability. select(id), revalidated before write and reread/listened afterward. Input gain/selection has no donor implementation. |
| windowManager | Backend, global focused workspace/window, real workspace/monitor/window rows and explicit switchWorkspace(id)/focusWindow(id). AeroSpace and donor-shaped OmniWM snapshots. OmniWM window focus is unsupported. |

AeroSpace uses bounded NDJSON subscription, 120 ms event coalescing, 1–30 second
reconnect backoff and 15-second reconciliation for hidden-workspace moves.
OmniWM's watch stream was not verified and is not claimed supported; its
snapshots reconcile every 15 seconds. Model changes cancel queued action leases;
AeroSpace actions requery target IDs before executing. Named/empty workspaces
are preserved and floating windows count. OmniWM IDs are monitor-scoped, and
ambiguous duplicate raw workspace names are unavailable unless a window row
supplies its monitor association. The UI shows global workspaces and monitor associations, not a guessed
Qt/CoreGraphics-to-WM monitor mapping. It renders at most eight hover dots;
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
fixtures, 8 Audio bridge, 10 System bridge, 9 boundary, 5 geometry and 30 QML
cases, plus a relocated signed bundle's fake-service/native geometry checks.
Pending deletion, repeated stop/start and deletion during delivery are covered.
The system panel is captured in build/screenshots/system.png.

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
