#!/bin/bash
# Locate the Maccer C ABI in a backend checkout.
#
# Maccer consolidated its libraries into the `launcher` package (whose lib
# target is still named launcher_agent). Older checkouts kept the agent in a
# separate `launcher-agent` package. Both layouts ship the same header, so the
# pill resolves the first one that exists instead of hardcoding one revision.
maccer_layout() {
    local source="${1:?maccer source directory required}"
    if [[ -f "$source/crates/launcher/include/maccer_agent.h" ]]; then
        MACCER_HEADER="$source/crates/launcher/include/maccer_agent.h"
        MACCER_PACKAGE="launcher"
    elif [[ -f "$source/crates/launcher-agent/include/maccer_agent.h" ]]; then
        MACCER_HEADER="$source/crates/launcher-agent/include/maccer_agent.h"
        MACCER_PACKAGE="launcher-agent"
    else
        echo "Missing Rust C ABI header under $source/crates." >&2
        echo "Point MACCER_SOURCE at a maccer checkout that builds the launcher agent." >&2
        return 1
    fi
}
