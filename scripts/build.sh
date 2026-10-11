#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
QMAKE="${QMAKE:-$(command -v qmake)}"
mkdir -p build/app
cd build/app
"$QMAKE" ../../pill.pro
make -j"$(sysctl -n hw.logicalcpu)"
# qmake leaves an existing Info.plist untouched; refresh reviewed purpose strings.
/bin/cp ../../Info.plist PillSpike.app/Contents/Info.plist
# Give TCC a bundled identity. This is local ad-hoc signing, not notarization.
/usr/bin/codesign --force --sign - PillSpike.app
