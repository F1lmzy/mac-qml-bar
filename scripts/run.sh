#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/app/PillSpike.app/Contents/MacOS/PillSpike
if [[ ! -x "$app" ]]; then ./scripts/build.sh; fi
exec "$app" "$@"
