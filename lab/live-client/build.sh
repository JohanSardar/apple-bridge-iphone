#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
output=${1:-"$root/.build/live-client"}
mkdir -p "$(dirname "$output")"
xcrun swiftc -parse-as-library -O "$root/lab/live-client/main.swift" "$root/ios/Pairing/PairingClient.swift" "$root/ios/Delivery/PhoneJob.swift" -o "$output"
