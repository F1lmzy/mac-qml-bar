#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
./scripts/audio-test.sh
./scripts/integration-test.sh
./scripts/launcher-test.sh
mkdir -p build/tests build/nativebridge-tests
(cd build/nativebridge-tests && qmake ../../tests/nativebridge.pro && make -j4 && ./nativebridge-test)
(cd build/tests && qmake ../../tests/geometry.pro && make -j4 && ./geometry-test)
QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=Basic qmltestrunner -import qml/modules -input tests -o -,txt
./scripts/packaging-test.sh
