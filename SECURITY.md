# Security policy

This app holds device keys for Apple Bridge and the approval key for BOGO, so
security reports matter here.

## Reporting a vulnerability

Report it privately through GitHub. Please don't open a public issue, pull
request or discussion for it.

- **The BOGO tab**, or anything that could let a BOGO approval be forged,
  reused or shown differently from what runs: report it to BOGO, at
  [**Report a BOGO vulnerability**](https://github.com/JohanSardar/bogo/security/advisories/new).
  BOGO's [security policy](https://github.com/JohanSardar/bogo/blob/main/SECURITY.md)
  lists what BOGO promises and where those promises stop.
- **The rest of the app** (Apple Bridge pairing, delivery, capabilities,
  widgets and extensions): report it here, at
  [**Report a vulnerability**](https://github.com/JohanSardar/apple-bridge-iphone/security/advisories/new).

If you're not sure which one fits, pick either: a report in the wrong place
gets moved, not lost.

Include what you can: the commit or build, your iOS version, steps to
reproduce, and what an attacker gains. Test only against your own devices and
data.

The app is maintained by one person, so replies can take a few days. You'll
get an acknowledgement, then a fix or a plan once the report is understood.
You'll be credited in the advisory unless you ask not to be.

## Supported versions

There are no tagged releases yet. Only the latest `main` gets security fixes.

## Dependencies

The app uses no third-party code: no Swift packages, CocoaPods or
frameworks from outside Apple. `ios/project.yml` lists every target and
dependency. The BOGO tab relies on these Apple frameworks for its security:

| Framework | Why |
|---|---|
| Security | The Keychain items that hold BOGO's keys |
| LocalAuthentication | Face ID before every approval |
| CryptoKit | The Secure Enclave P-256 approval key and its signatures, and X25519, HKDF, ChaCha20-Poly1305 and SHA-256 for BOGO's channel and requests |
| DeviceCheck | App Attest, which proves to the Mac that it is talking to this app |
| Network | Finding BOGO Macs nearby over Bonjour |
| VisionKit | Scanning a BOGO pairing code with the camera |
| SQLite (system library) | BOGO's local store of requests and decisions |

Apple Bridge's capabilities use the frameworks of what they reach, such as
HealthKit, CoreLocation, AlarmKit and FamilyControls, each only after you
turn the capability on. BOGO's Mac side lists its own dependencies in
[its security policy](https://github.com/JohanSardar/bogo/blob/main/SECURITY.md#dependencies).
