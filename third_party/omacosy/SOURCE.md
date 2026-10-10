# omacosy donor audit

Upstream: https://github.com/paulsp94/omacosy
Read-only local donor: ~/.local/share/omacosy
Checkout HEAD: beb5816a95907f867d75a5b8e92a5050b28cd19f
Last commit changing helper/bar.swift: 59f669463c7e03f0512dc12c7ac6133f258eccfd
Source: helper/bar.swift, 3752 lines, 167809 bytes
SHA-256: 218ce96cf149d12d320667e6a4addc98fdbf9c9406e6ec8d8b4eb6bd3411d693
License: MIT, Copyright (c) 2026 Paul Spende. See LICENSE alongside this file.

## Local modifications

At audit time, helper/bar.swift and LICENSE match checkout HEAD byte for byte.
The checkout is not globally pristine. Tracked modifications are in README.md,
bin/theme-set, config/aerospace/aerospace.template.toml, config/ghostty/config
and config/omniwm/settings.toml. Untracked files are bin/__pycache__/ and
bin/omacosy-ghostty-theme.py. None change the audited Swift source.

This is a local-source audit, not a claim that upstream HEAD has the same code.
No donor files, agents, AeroSpace hooks or shared /tmp files were changed.

## Copied sections

Only LICENSE has been copied so far. The minimal Swift/Qt boundary proof is new
code; it does not copy the bar Model or a hardware service. Add source ranges
and destination symbols here as each service is actually extracted.

## Extraction map

All ranges below refer to helper/bar.swift at the recorded SHA-256. They are
candidates for later extraction, not a list of already-copied code.

| Service | Native logic / state | Presentation and adaptation to exclude |
| --- | --- | --- |
| Audio | 672–733: defaultOutputDevice, volumeAddress, readVolume, writeVolume. 736–779: device enumeration/default selection, deferred. 3619–3648: volume/mute listeners and default-output reattachment. | updateVolume, 781–794, chooses glyphs and calls set. volumeRows, 1547–1578, builds popup UI. Replace set/repaint with an explicit observed state callback. |
| Brightness | 39–50: DisplayServices ABI. 840–869: builtinDisplayID and read. 3652–3658: native notification. Setter is called by brightnessRows, 1516–1545. | Do not copy shade/gamma, night shift or popup rows. builtinDisplayID falls back to the main display; remove that fallback for a built-in-only contract. |
| AeroSpace | 88–99: CLI discovery/invocation. 387–440: Snapshot and aerospaceSnapshot. 161–167: workspace action. 2877–2896: monitor name mapping. 3289–3299: focused-workspace query. | Snapshot depends on global surfaces, and filters floating windows. Pass monitor associations explicitly and count all managed windows. Replace pipe output with validated JSON and synchronous Process waits with async transport. |
| Battery | 646–668: IOKit power-source reads. 3608–3613: notification run-loop source. | Remove icon/color/set calls. Empty power-source lists must publish unavailable rather than retain the previous value. Retain and remove the run-loop source on teardown. |
| Spotify | 539–591: running check, metadata notification parsing, startup query and playback. 3701–3712: distributed playback/app lifecycle observers. | Remove bar drawing and button UI, 2722–2735. Do not copy primeMedia's startup AppleScript, which can prompt for Automation. Explicit actions must report denial and termination must clear stale metadata. |
| Wi-Fi, later | 984–999: CoreWLAN reads. 1580–1591: IP lookup. 3663–3677: SCDynamicStore notifications. LocationGate, 880–906, documents SSID permission dependencies. | Exclude wifiRows, 1605–1650, and the OMACOSY_MANAGED auto-prompt gate. Define a UI need and permission policy before extraction. |
| Bluetooth, later | 1008–1022: reads. 1027–1092: BluetoothWatcher. 3683: startup. 52–53: private power ABI. | Exclude popup UI and automatic manager creation. Donor gates IOBluetooth calls on existing authorization because unauthorized access can abort the process. |

Shared utility candidates are shellOut, 120–134, shell, 625–637, and screenID,
2868–2870. The process helpers swallow failures or block; do not copy them
unchanged. The CLI transport needs timeouts, cancellation and exit-status checks.

The monolithic executable owns file-scope model/surfaces/rightItems/palette
state and ends in app.run(). It cannot be imported as a library. Exclude all
AppKit bar/popups, Palette, set, repaint, drawing helpers, gamma shade, weather,
cheatsheet and top-level initialization. The tlog utility writes a shared /tmp
log and is not suitable for this host.

## Native integration hazards

- Audio reads round to integer percent and conflate unreadable volume with no
  device. Writes ignore OSStatus. Mute and scalar-volume support need separate
  read/write probes, and each listener must retain its exact removal block.
- Brightness uses hard-linked private symbols. Use isolated dynamic symbol
  resolution so missing DisplayServices APIs cannot stop the host from loading.
  Re-resolve displays and notification registrations after screen changes.
- AeroSpace monitor IDs change after hotplug. Donor joins by display name,
  not CoreGraphics ID or Qt index. Ambiguous names need an unavailable mapping.
- The donor does not use AeroSpace subscribe. Its /tmp/omacosy-bar-ws watcher,
  3129–3132, uses create: true; that behavior is forbidden here. Optional reads
  must never create, truncate or write shared hook files.
- Donor reconciliation, 3301–3379, uses background queries and bounded retry
  delays. Extract the policy without bar redraws, private SkyLight subscriptions
  or OmniWM event paths.
- Spotify AppleScript and Wi-Fi/Bluetooth require separate privacy review.
  Do not add permissions or prompts as a side effect of importing the library.

The audit found installed AeroSpace CLI/server 0.21.3-Beta,
d56e1637c3a1ed660d0cadd7534e94fb3218d1c3. Read-only subscribe --all produced
newline-delimited JSON with _event keys for focused-workspace-changed,
focus-changed, mode-changed and focused-monitor-changed. This is an observation
of this installation, not a permanent framing or coverage guarantee. Recheck
before task 5. Hidden-workspace moves still require reconciliation.
