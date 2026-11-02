#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
xcodebuild -version >/dev/null
command -v xcodegen >/dev/null
OUTPUT="${APPLE_BRIDGE_IOS_OUTPUT:-$ROOT/.build/ios}"
xcodegen generate --spec "$ROOT/ios/project.yml" --project "$ROOT/ios" >/dev/null
lockf -t 3600 /tmp/ab-xcode.lock xcodebuild -quiet -project "$ROOT/ios/AppleBridge.xcodeproj" -scheme AppleBridge -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUTPUT/Simulator" CODE_SIGNING_ALLOWED=NO build
