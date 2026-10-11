#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${PILL_DISPLAY_HARDWARE_TEST:-}" != 1 || "${1:-}" != --write-and-restore ]]; then
    echo "Opt-in only: PILL_DISPLAY_HARDWARE_TEST=1 $0 --write-and-restore" >&2
    exit 2
fi
mkdir -p build/brightness-live
xcrun swiftc -swift-version 5 src/native/*.swift tests/brightness-live/main.swift -o build/brightness-live/probe
exec build/brightness-live/probe "$@"
