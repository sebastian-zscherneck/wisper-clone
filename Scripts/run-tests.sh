#!/bin/bash
# Builds and runs the Swift Testing suite on machines with only Command Line
# Tools installed, where plain `swift test` silently executes zero tests.
# See Scripts/TestHost.swift for the underlying reason.
set -euo pipefail
cd "$(dirname "$0")/.."

CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
CLT_TESTLIBS="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
BUNDLE=".build/arm64-apple-macosx/debug/wisper-clonePackageTests.xctest/Contents/MacOS/wisper-clonePackageTests"
HOST=".build/test-host"

swift build --build-tests

if [[ ! -x "$HOST" || "Scripts/TestHost.swift" -nt "$HOST" ]]; then
    swiftc -parse-as-library \
        -F "$CLT_FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$CLT_TESTLIBS" \
        -o "$HOST" Scripts/TestHost.swift
fi

exec "$HOST" "$BUNDLE"
