# Native service boundary

## Implemented checkpoint

PLAN.md tasks 1 and 2 and the Audio service for task 3 are implemented. The
donor audit, copied Audio ranges and MIT notice are in third_party/omacosy.
Real-device write and UI input verification remain opt-in.

src/native/*.swift builds as libPillNative.dylib. qmake bootstraps
the generated Objective-C header during configuration because its dependency
scanner misresolves missing generated headers. Subsequent Swift source changes
rebuild through make. All generated outputs live in build/native. The app
copies the library into Contents/Frameworks and loads it through @rpath.
Homebrew Qt remains an installed prerequisite; this is not a portable Qt bundle.
The Swift compiler uses Swift 5 language mode and the configured macOS target.
One architecture matching Qt is supported; universal builds are not implemented.

Pill.MacOS 1.0 exports Bridge.ready for callback health and the Audio singleton
described below. Bridge.ready does not imply hardware availability. Audio
performs all HAL reads, writes and observer management on a serial utility
queue. Its facade delivers immutable snapshots to main, then the Qt adapter
queues context-bound updates to its owner thread. Quickshell wrappers remain
separate.

## Ownership and delivery contract

- Construct/destroy the facade and adapter on the macOS main / Qt owner thread.
  Preconditions enforce this. QObject parenting prevents moving the adapter to
  another thread.
- Worker work forwards a closure created on main. The worker must not resolve
  a weak facade reference, even to create another weak capture, because that
  can temporarily retain it and cause final release on the worker.
- Native callback delivery and stop are serialized on main. stop advances a
  generation and clears the callback. A pending older delivery cannot invoke it,
  including when the facade is still retained.
- The adapter posts a context-bound queued Qt invocation. Destruction removes
  pending invocations; stop clears the native block before releasing the facade.
  A raw adapter pointer is safe only under this main-thread callback contract.
  Future worker-thread callbacks must be marshalled to main before invoking it.
- Audio invalidates native deliveries on stop, then queues removal of the exact
  CoreAudio observer blocks on its worker. Listener callbacks weakly reference
  the controller and reject obsolete device generations. Removal failures are
  logged without keeping the controller alive.

The automated suite includes 40 property-fixture assertions, eight Audio bridge
cases, nine boundary-proof cases, five geometry cases and 22 QML cases.
The relocated app checks callback health and labelled test Audio state without
DYLD search overrides. Tests need a logged-in GUI session; QGuiApplication
drains the Cocoa main dispatch queue.
A real-device read-only probe succeeded. Hardware writes/restoration and real
device switching have not been exercised. The input harness now uses test Audio
and waits for a confirmed fixture update; it has not been rerun because a user's
PillSpike instance is running. Nothing stops that instance automatically.

## Audio contract

Output volume and mute only. Device selection and input gain remain out of scope.

Pill.MacOS.Audio exposes read-only observed properties:

| Property | Type | Meaning |
| --- | --- | --- |
| available | bool | A current default output device is resolved. |
| outputDeviceId | string | Current CoreAudio device ID, empty when unavailable; not a durable ID. |
| volumeKnown | bool | A successful scalar volume read exists for this device. |
| volume | real | Observed 0..1 volume; NaN when unknown. Consumers must gate on volumeKnown. |
| muteKnown | bool | A successful mute read exists for this device. |
| muted | bool | Observed mute state, meaningful only when muteKnown. |
| canSetVolume | bool | A supported scalar property exists and is settable. |
| canMute | bool | A supported mute property exists and is settable. |
| lastErrorCode | string | Stable code or empty after successful recovery. |
| lastError | string | Diagnostic message, empty when no current error. |
| testBackend | bool | Constant; true only in explicitly labelled fixture mode. |

Actions are setVolume(real) and setMuted(bool). They return no optimistic state.
Reject non-finite volume inputs, clamp finite values to 0..1, and check current
capabilities again at write time. Emit errorOccurred(operation, code, message)
for invalidInput, unavailable, unsupported or nativeFailure. Check every
OSStatus, reread after writes, and publish only confirmed observed state.
The contract preserves normalized precision instead of the donor's rounded
display percent. Volume and mute are independent; mute never forces volume zero.
The donor's updateVolume display label is not copied.

Capability probes must distinguish master scalar from supported per-channel
fallbacks, readability from settability, and transient read failures from absent
properties. available alone must never enable a fader or mute control.

Default-device replacement must detach exact listener blocks, clear old known
values/capabilities, attach the new listeners and publish one coherent state.
Tag callbacks with a device generation so stale notifications cannot restore
the previous device. Coalesce writes during dragging without read/write feedback
loops; QML keeps drag feedback separate from volume and reconciles on release.

The master scalar is preferred when present; a failed master read does not
silently fall back to channels. Without a master, all output channels must have
readable scalar controls before an average is exposed, and all must be settable
before writes are enabled. Mute support is probed independently.

A failed subscription still permits an initial read. While degraded, one
one-second retry is scheduled at a time to refresh state and reattach observers.
Successful recovery stops retrying. Teardown invalidates pending retry tokens.
Finite volume requests coalesce for 20 ms; invalid input always reports an error.
Actions also carry the Qt adapter's observed device ID internally and reject a
changed default rather than writing to a newly selected output.

The app supports --test-audio explicitly and labels the volume TEST. Self-test
mode always uses that fixture. Automated tests never instantiate real hardware.
scripts/audio-live-test.sh --read-only probes actual capabilities without writes.
The separate command below briefly lowers volume, toggles mute, then restores
individual channel values and mute in a defer block. It is not run automatically:

    PILL_AUDIO_HARDWARE_TEST=1 ./scripts/audio-live-test.sh --write-and-restore

Do not switch devices during that test. A disconnected original device cannot
be restored; restoration errors cause a failing exit and an explicit diagnostic.
External keyboard updates, hotplug and the real UI still need manual validation.

API behavior is checked against the installed CoreAudio SDK's AudioHardware.h:
AudioObjectAdd/RemovePropertyListenerBlock retain the exact queue and block;
StreamConfiguration returns a variable-length AudioBufferList; scalar writes
may be quantized and must be confirmed by reads/notifications.
Reference: https://developer.apple.com/documentation/coreaudio
