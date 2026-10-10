#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
mkdir -p build/tests
(cd build/tests && qmake ../../tests/geometry.pro && make -j4 && ./geometry-test)
QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=Basic qmltestrunner -input tests -o -,txt
build/app/PillSpike.app/Contents/MacOS/PillSpike --top-offset 44 --self-test build/screenshots
