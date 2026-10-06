#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode), SwiftPM
# can't find the Swift Testing macro plugin by itself, so load it explicitly.
set -euo pipefail
cd "$(dirname "$0")"
plugin="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$plugin" ]; then
  exec swift test -Xswiftc -load-plugin-library -Xswiftc "$plugin" "$@"
fi
exec swift test "$@"
