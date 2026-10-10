#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?native output directory required}"
deployment="${2:-26.0}"
arch="${3:-$(uname -m)}"
# This project builds one native architecture, matching its Homebrew Qt.
if [[ "$arch" == *" "* ]]; then
    echo "The Swift bridge currently requires a single target architecture." >&2
    exit 2
fi
mkdir -p "$output"
xcrun swiftc -swift-version 5 -O -emit-library -emit-module \
    -module-name PillNative -target "$arch-apple-macosx$deployment" \
    -emit-objc-header -emit-objc-header-path "$output/PillNative-Swift.h" \
    -emit-module-path "$output/PillNative.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libPillNative.dylib \
    src/native/NativeBackend.swift -o "$output/libPillNative.dylib"
