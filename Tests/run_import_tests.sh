#!/bin/zsh
# Compiles the importers with the test harness and runs them against Tests/Fixtures.
set -e
cd "$(dirname "$0")/.."
if [[ -z "$DEVELOPER_DIR" && -d /Applications/Xcode.app ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
OUT=$(mktemp -d)/import_tests
xcrun swiftc -swift-version 5 -parse-as-library Sources/Models.swift Sources/SampleData.swift Sources/Importers.swift Sources/ImportPlanner.swift Sources/AppleBooksImporter.swift Tests/ImportTests.swift -o "$OUT"
"$OUT" Tests/Fixtures
