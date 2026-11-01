#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Real shared-provider acceptance uses owned RAM entries and fake desktop effects.
if [[ -z "${MACCER_SHARED_FIXTURE_BIN:-}" ]]; then
    source="${MACCER_SOURCE:-$HOME/Documents/maccer}"
    cargo build --manifest-path "$source/Cargo.toml" -p launcher-service --example pill_acceptance_fixture
    export MACCER_SHARED_FIXTURE_BIN="$source/target/debug/examples/pill_acceptance_fixture"
fi
mkdir -p build/launcher-tests
(cd build/launcher-tests && qmake ../../tests/launcher.pro && make -j"$(sysctl -n hw.logicalcpu)" && QT_QPA_PLATFORM=offscreen ./launcher-test)
