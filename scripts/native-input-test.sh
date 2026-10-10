#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x PillSpike >/dev/null; then
    echo "Quit the running pill first; this test needs an isolated instance." >&2
    exit 2
fi
./scripts/build.sh
swiftc -swift-version 6 tests/native_input.swift -o build/native-input
exec build/native-input "$PWD/build/app/PillSpike.app/Contents/MacOS/PillSpike"
