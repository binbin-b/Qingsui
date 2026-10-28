#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
mkdir -p .build/tests
xcrun swiftc -parse-as-library -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  Sources/ChatLedger/MessageEditor.swift Tests/EditorLayoutTests.swift \
  -o .build/tests/EditorLayoutTests
.build/tests/EditorLayoutTests
