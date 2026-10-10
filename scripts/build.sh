#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
QMAKE="${QMAKE:-$(command -v qmake)}"
mkdir -p build/app
cd build/app
"$QMAKE" ../../pill.pro
make -j"$(sysctl -n hw.logicalcpu)"
