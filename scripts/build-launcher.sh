#!/bin/bash
set -euo pipefail
source_dir="${1:?maccer source directory required}"
output="${2:?launcher output directory required}"
deployment="${3:-26.0}"
arch="${4:-$(uname -m)}"

if [[ ! -f "$source_dir/crates/launcher-agent/include/maccer_agent.h" ]]; then
    echo "Missing Rust C ABI header: $source_dir/crates/launcher-agent/include/maccer_agent.h" >&2
    exit 2
fi
case "$arch" in
    arm64|aarch64) target="aarch64-apple-darwin"; expected="arm64" ;;
    x86_64) target="x86_64-apple-darwin"; expected="x86_64" ;;
    *) echo "Unsupported Qt architecture '$arch'; expected arm64 or x86_64." >&2; exit 2 ;;
esac

mkdir -p "$output/include" "$output/cargo-target"
export CARGO_TARGET_DIR="$output/cargo-target"
export MACOSX_DEPLOYMENT_TARGET="$deployment"
cargo build --manifest-path "$source_dir/Cargo.toml" -p launcher-agent --lib --release --target "$target"
source_library="$CARGO_TARGET_DIR/$target/release/liblauncher_agent.dylib"
if [[ ! -f "$source_library" ]]; then
    echo "Cargo succeeded but did not produce $source_library" >&2
    exit 1
fi
cp "$source_dir/crates/launcher-agent/include/maccer_agent.h" "$output/include/maccer_agent.h"
cp "$source_library" "$output/liblauncher_agent.dylib"
install_name_tool -id @rpath/liblauncher_agent.dylib "$output/liblauncher_agent.dylib"
actual="$(lipo -archs "$output/liblauncher_agent.dylib")"
if [[ "$actual" != "$expected" ]]; then
    echo "Rust library architecture '$actual' does not match Qt architecture '$expected'." >&2
    exit 1
fi
