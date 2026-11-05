#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -parse-as-library -swift-version 6 "$root/lab/ios/PairingProof.swift" "$root/ios/Pairing/PairingClient.swift" "$root/ios/Pairing/DeviceIdentity.swift" "$root/ios/Delivery/CommandPacket.swift" -o "$output/pairing-proof"
"$output/pairing-proof" "$root/lab/ios/fixtures"
