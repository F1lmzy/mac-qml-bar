# Native service boundary

## Implemented checkpoint

PLAN.md tasks 1 and 2 are implemented. The donor audit and MIT notice are in
third_party/omacosy. No donor service code has been copied yet.

src/native/NativeBackend.swift builds as libPillNative.dylib. qmake bootstraps
the generated Objective-C header during configuration because its dependency
scanner misresolves missing generated headers. Subsequent Swift source changes
rebuild through make. All generated outputs live in build/native. The app
copies the library into Contents/Frameworks and loads it through @rpath.
Homebrew Qt remains an installed prerequisite; this is not a portable Qt bundle.
The Swift compiler uses Swift 5 language mode and the configured macOS target.
One architecture matching Qt is supported; universal builds are not implemented.

Pill.MacOS 1.0 currently exports only the Bridge singleton with a read-only
ready boolean. This means the asynchronous native callback reached Qt, not that
audio, brightness or another system service is available. shell.qml observes it
without changing the visible UI. All mixer controls remain preview-only or
disabled. Quickshell compatibility wrappers remain separate.

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
- No native observers exist in this proof. Each later service must implement and
  test its own subscription removal before releasing the facade.

Verified with a clean parallel build, source-change rebuild/bundle recopy,
deleted-header recovery, nine bridge test cases including test setup/cleanup,
five geometry cases, fifteen QML cases, and the relocated app's native checks.
The native-input harness also passes using the unchanged preview faders. The
packaging check launches without DYLD library/framework search overrides.
Tests require a logged-in GUI session; the bridge tests use QGuiApplication so
the Cocoa dispatcher drains the main dispatch queue.

## Proposed Audio contract for task 3

This is a proposal, not an exported API. Implement output volume and mute only,
after fake-backend tests. Device selection and input gain remain out of scope.

Pill.MacOS.Audio would expose read-only observed properties:

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

Actions are setVolume(real) and setMuted(bool). They return no optimistic state.
Reject non-finite volume inputs, clamp finite values to 0..1, and check current
capabilities again at write time. Emit errorOccurred(operation, code, message)
for invalidInput, unavailable, unsupported or nativeFailure. Check every
OSStatus, reread after writes, and publish only confirmed observed state.
Donor percent rounding must not lose precision in the normalized contract.
Read volume and mute independently; do not report volume zero just because mute
is on, as the donor's display-oriented readVolume does.

Capability probes must distinguish master scalar from supported per-channel
fallbacks, readability from settability, and transient read failures from absent
properties. available alone must never enable a fader or mute control.

Default-device replacement must detach exact listener blocks, clear old known
values/capabilities, attach the new listeners and publish one coherent state.
Tag callbacks with a device generation so stale notifications cannot restore
the previous device. Coalesce writes during dragging without read/write feedback
loops; QML keeps drag feedback separate from volume and reconciles on release.

Required fake tests cover callback thread/lifetime, capability combinations,
non-finite/clamped inputs, OSStatus failures, device replacement and stale
events. Keep fader regression/input tests on a test-only fake backend before
connecting writes. Hardware verification must be explicit opt-in, capture and
restore original volume/mute, and never run from scripts/test.sh or startup.
