#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
xcrun swiftc -parse-as-library -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/ChatLedger/SelectableMessage.swift Tests/SelectionTests.swift -o .build/tests/SelectionTests
.build/tests/SelectionTests
