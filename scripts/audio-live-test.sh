#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:---read-only}"
if [[ "$mode" != "--read-only" && "$mode" != "--write-and-restore" ]]; then exit 2; fi
if [[ "$mode" == "--write-and-restore" && "${PILL_AUDIO_HARDWARE_TEST:-}" != "1" ]]; then
    echo "Opt in with PILL_AUDIO_HARDWARE_TEST=1; this changes audio briefly and restores it." >&2
    exit 2
fi
mkdir -p build/audio-live
xcrun swiftc -swift-version 5 src/native/AudioHardware.swift \
    src/native/CoreAudioHardware.swift src/native/AudioController.swift \
    tests/audio-live/main.swift -o build/audio-live/audio-live-test
exec build/audio-live/audio-live-test "$mode"
