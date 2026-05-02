#!/usr/bin/env bash
# Build and launch codex-meter. Used by the README quickstart; safe to re-run.
set -euo pipefail

cd "$(dirname "$0")"

xcodebuild -project CodexMeter/CodexMeter.xcodeproj \
           -scheme CodexMeter \
           -configuration Release \
           -derivedDataPath build \
           build

open build/Build/Products/Release/CodexMeter.app
