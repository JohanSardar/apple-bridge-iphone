#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IPA="${1:-$ROOT/.build/ios/AppleBridge.ipa}"
HOST="${APPLE_BRIDGE_INSTALL_HOST:?set APPLE_BRIDGE_INSTALL_HOST to the ssh host of the Mac the iPhone is plugged into}"
scp "$IPA" "$HOST:/tmp/AppleBridge.ipa"
ssh "$HOST" '~/.local/bin/pymobiledevice3 apps install /tmp/AppleBridge.ipa'
