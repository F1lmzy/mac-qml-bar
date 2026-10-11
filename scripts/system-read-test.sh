#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/system-read
xcrun swiftc -swift-version 5 src/native/*.swift tests/system-live/main.swift -o build/system-read/probe
exec build/system-read/probe
