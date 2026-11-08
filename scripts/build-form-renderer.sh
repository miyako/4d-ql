#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product fourdform
BIN=$(swift build -c release "${ARCHS[@]}" --show-bin-path)
mkdir -p build/standalone
cp "$BIN/fourdform" build/standalone/fourdform
codesign --force --sign - build/standalone/fourdform
codesign --verify --strict build/standalone/fourdform
echo "Built standalone renderer: $PWD/build/standalone/fourdform"
