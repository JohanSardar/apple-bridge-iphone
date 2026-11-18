#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
xcodebuild -version >/dev/null
command -v xcodegen >/dev/null
OUTPUT="${APPLE_BRIDGE_IOS_OUTPUT:-$ROOT/.build/ios}"
xcodegen generate --spec "$ROOT/ios/project.yml" --project "$ROOT/ios" >/dev/null
# Sign to run locally (ad hoc, no Apple account or team): the Simulator then
# grants the app its entitlements, so it can keep BOGO's keys in the Keychain.
# These overrides apply to this Simulator build only; device and release
# builds sign as project.yml says.
lockf -t 3600 /tmp/ab-xcode.lock xcodebuild -quiet -project "$ROOT/ios/AppleBridge.xcodeproj" -scheme AppleBridge -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUTPUT/Simulator" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= build
