#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="$PWD/build/app/PillSpike.app"
if [[ ! -x "$bundle/Contents/MacOS/PillSpike" ]]; then ./scripts/build.sh; fi
# Automated/test modes keep stdout and never instantiate privacy managers.
for argument in "$@"; do
    case "$argument" in
        --test-audio|--test-services|--self-test) exec "$bundle/Contents/MacOS/PillSpike" "$@" ;;
    esac
done
# LaunchServices makes the app responsible for its own privacy prompts,
# unlike executing it as a Terminal child. Does not stop an existing instance.
/usr/bin/open -a "$bundle" --args "$@"
