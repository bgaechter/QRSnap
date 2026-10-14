#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/clang-module-cache
core_sources=(QRSnap/Scan/*.swift QRSnap/Selection/GeometryAdapter.swift QRSnap/Routing/*.swift QRSnap/Decode/*.swift)
xcrun swiftc -parse-as-library -swift-version 6 -D STANDALONE_TESTS \
    -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$PWD/.build/clang-module-cache" \
    "${core_sources[@]}" QRSnapTests/*Tests.swift QRSnapTests/Support/StandaloneRunner.swift \
    -o .build/contract-tests
.build/contract-tests "$@"
