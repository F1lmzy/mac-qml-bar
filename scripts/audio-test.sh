#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/audio-tests build/audio-bridge-tests
# This executable only uses property fixtures; it never instantiates CoreAudio.
xcrun swiftc -swift-version 5 src/native/AudioHardware.swift \
    src/native/FakeAudioHardware.swift src/native/AudioController.swift \
    tests/audio/main.swift -o build/audio-tests/audio-test
build/audio-tests/audio-test
(cd build/audio-bridge-tests && qmake ../../tests/audio.pro && make -j4 && ./audio-bridge-test)
