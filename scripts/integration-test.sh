#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/integration-tests build/system-tests
xcrun swiftc -swift-version 5 -D WINDOW_MANAGER_TESTS src/native/*.swift \
    tests/integrations/display.swift tests/integrations/privacy.swift tests/integrations/lifecycle.swift tests/integrations/events.swift tests/integrations/theme.swift tests/integrations/thumbnails.swift tests/integrations/main.swift \
    -o build/integration-tests/fixtures
build/integration-tests/fixtures
(cd build/system-tests && qmake ../../tests/system.pro && make -j4 && ./system-bridge-test)
