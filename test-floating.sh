#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
mkdir -p .build/tests
sources=(Sources/ChatLedger/*.swift)
sources=(${sources:#Sources/ChatLedger/ChatLedgerApp.swift})
xcrun swiftc -parse-as-library -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  "${sources[@]}" Tests/FloatingInteractionTests.swift -o .build/tests/FloatingInteractionTests
.build/tests/FloatingInteractionTests
