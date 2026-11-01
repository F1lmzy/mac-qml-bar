#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
maccer_source="${MACCER_SOURCE:-$HOME/Documents/maccer}"
bundle="build/app/PillSpike.app"
library="$bundle/Contents/Frameworks/libPillNative.dylib"
launcher_library="$bundle/Contents/Frameworks/liblauncher_agent.dylib"
test -f "$library"
test -f "$launcher_library"
cmp build/native/libPillNative.dylib "$library"
cmp build/launcher/liblauncher_agent.dylib "$launcher_library"
cmp "$maccer_source"/crates/launcher-agent/include/maccer_agent.h build/launcher/include/maccer_agent.h
cmp third_party/omacosy/LICENSE "$bundle/Contents/Resources/licenses/omacosy/LICENSE"
cmp third_party/ricelin/LICENSE "$bundle/Contents/Resources/licenses/ricelin/LICENSE"
cmp "$maccer_source"/LICENSE "$bundle/Contents/Resources/licenses/maccer/LICENSE"
cmp Info.plist "$bundle/Contents/Info.plist"
/usr/bin/codesign --verify --strict "$bundle"
for key in NSLocationWhenInUseUsageDescription NSBluetoothAlwaysUsageDescription NSAppleEventsUsageDescription; do
    /usr/libexec/PlistBuddy -c "Print :$key" "$bundle/Contents/Info.plist" >/dev/null
done
otool -L "$bundle/Contents/MacOS/PillSpike" | grep -q '@rpath/libPillNative.dylib'
otool -L "$bundle/Contents/MacOS/PillSpike" | grep -q '@rpath/liblauncher_agent.dylib'
otool -L "$launcher_library" | grep -q '@rpath/liblauncher_agent.dylib'
# Launch a relocated bundle, without build-directory library search overrides.
mkdir -p build/packaging
rm -rf build/packaging/PillSpike.app
ditto "$bundle" build/packaging/PillSpike.app
env -u DYLD_LIBRARY_PATH -u DYLD_FRAMEWORK_PATH \
    -u DYLD_FALLBACK_LIBRARY_PATH -u DYLD_FALLBACK_FRAMEWORK_PATH \
    "$root/build/packaging/PillSpike.app/Contents/MacOS/PillSpike" \
    --top-offset 2 --test-audio --self-test "$root/build/screenshots"
