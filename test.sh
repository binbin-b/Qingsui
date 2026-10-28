#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
mkdir -p .build/tests
xcrun swiftc -parse-as-library -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  Sources/ChatLedger/Models.swift Sources/ChatLedger/Store.swift Sources/ChatLedger/ArchiveService.swift Tests/CoreTests.swift \
  -o .build/tests/CoreTests
.build/tests/CoreTests
