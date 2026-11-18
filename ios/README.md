# Build, run and pair

This guide builds the app, runs it in the Simulator, tries BOGO without a Mac,
and pairs the app with BOGO or Apple Bridge on your Mac. Commands run from the
root of this repository.

Other pages:

- [Capabilities](../docs/capabilities.md): what each Apple Bridge capability
  does, the commands it takes and the permissions it needs.
- [Lab and qualification](../docs/lab.md): the lab scenarios and the
  real-device runners.
- [Maintainer notes](../docs/maintainers.md): signed device builds and
  provisioning for the maintainer's team.

## Build and run in the Simulator

You need a Mac with Xcode 26.4 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). You don't need an Apple developer account, a team ID, a signing certificate or an iPhone.

```sh
git clone https://github.com/JohanSardar/apple-bridge-iphone.git
cd apple-bridge-iphone
make simulator
```

`make simulator` generates `ios/AppleBridge.xcodeproj` and builds the app and its extensions for the Simulator without signing. To run that build, boot any iPhone from `xcrun simctl list devices available`, then install and launch it:

```sh
xcrun simctl boot "iPhone 17"
open -a Simulator
xcrun simctl install booted .build/ios/Simulator/Build/Products/Debug-iphonesimulator/AppleBridge.app
xcrun simctl launch booted com.johansardar.applebridge.ios
```

To work in Xcode instead, run `make project`, open `ios/AppleBridge.xcodeproj`, choose the AppleBridge scheme and an iPhone simulator, and press Run. Xcode signs Simulator builds locally, so the team in the project doesn't matter there. Run `make project` again after adding or moving files; the generated project is not tracked.

## Try BOGO without a Mac

Debug builds include a stand-in Mac that sends realistic requests.

1. In the Simulator's menu, choose Features → Face ID → Enrolled.
2. In the app, open BOGO → Add Mac and tap **Stand-in Mac**. When the codes
   show, tap **Confirm with Face ID**, then choose Features → Face ID →
   Matching Face.
3. Open Settings → Demo and tap Send next to a request. It arrives on the
   Review card three seconds later.
4. Read it, slide to approve, and match the face again.

This is how the recording on the [front page](../README.md) was made.

## Pair with BOGO on your Mac

Install and set up BOGO on the Mac first ([BOGO's five-minute
start](https://github.com/JohanSardar/bogo#get-started-in-five-minutes)).
`bogo setup` runs `bogo approver add` for you; then, in the app, open BOGO →
Macs → Add Mac and tap your Mac. If it isn't listed, because the phone is on
another network, tap **Mac not listed? Use a code** and scan or type the code
the Mac shows. Check that both screens show the same 6 digits, answer `y` on
the Mac and confirm with Face ID. BOGO's [Add your
iPhone](https://github.com/JohanSardar/bogo/blob/main/docs/add-your-iphone.md)
guide covers each screen and what to do when something goes wrong.

Which app builds can pair depends on App Attest:

- **TestFlight and App Store builds** attest with App Attest's production
  environment. The Mac's BOGO config needs `"production"` in
  `approvers.iphone.app_attest`, which a new BOGO home already has.
- **Xcode device builds** use the development environment, which a new BOGO
  home also accepts.
- **Simulator builds** have no App Attest. Pair them only with a BOGO daemon
  built for testing (`cargo build -p bogo --features test-registration`), and
  never use that daemon for real approvals. The Simulator gets no pushes; open
  BOGO to see waiting requests.

### How the BOGO tab works

The BOGO tab lists waiting and recent requests, with your Macs at the top; the Activity tab lists past requests. Each request shows what will run, built
from the exact signed bytes, apart from the agent's unverified reason. Approve
signs with a Face ID–gated Secure Enclave key after a short arm delay; Deny
takes an optional note; Pause stops an agent. BOGO keeps its own keys, its own
SQLite store (`Application Support/BOGO`) and its own Keychain items, shared
with nothing in Apple Bridge.

Debug builds talk to the stand-in Mac, which replays BOGO's test vectors. To
feed it, drop JSON commands such as `{"request":"lie-in-reason"}` into
`Application Support/BOGO/stand-in/inbox/` in the app's data container.
Simulator Debug builds use a software key behind simulated Face ID and skip
App Attest; neither exists in device or Release builds.

The old Face ID approvals capability is gone; BOGO replaced it. Apple Bridge
`bridge.approval` jobs are ignored and expire on the Mac.

## Pair with Apple Bridge on your Mac

On the Mac, run `bridge pair --iphone --via-remote`, then scan the QR code from
the app's Pairing screen, or paste its `ab1-` code. [Capabilities →
Pairing](../docs/capabilities.md#pairing) explains the keys and checks
involved. Then turn on, in the app's settings, each capability you want Apple
Bridge's agents to use; each one stays off until you do.

## Checks

```sh
make lint
make test
```

`make lint` parses every Swift, Python and shell file and rejects code comments. `make test` needs no iPhone, network or permission prompt. It compiles production Swift with fake adapters and runs:

- the pairing proof and eleven Apple Bridge model proofs;
- the BOGO proofs in `packaging/dev/check-bogo.py`, which build `BogoModel`, `BogoCrypto` and `BogoRelay` for the Mac. They decode every request vector in `ios/BogoKit/BogoRelay/StandInVectors` and refuse every rejected one, check the amounts and mismatch warnings on the Review card, and run the relay registration and decision-sync logic against fake relays and Macs;
- the Python tests for the release and real-device tooling.

Every pull request runs `make lint`, `make test`, `make simulator` and an unsigned Release build for iPhone on GitHub's hosted macOS runners ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)).

## Signing with your own team

The development team comes from `ios/Signing.xcconfig`. To use your own without editing it, put yours in the git-ignored `ios/Local.xcconfig`, then regenerate the project:

```sh
echo 'DEVELOPMENT_TEAM = ABCDE12345' > ios/Local.xcconfig
make project
```

The bundle IDs, App Groups and provisioning profile names belong to the maintainer's team. A device build under another team also needs its own App IDs and profiles for the app and each extension. A self-built app can't use the public BOGO relay's pushes, which need the maintainer's push key; see BOGO's [Running your own relay](https://github.com/JohanSardar/bogo/blob/main/docs/self-hosting-relay.md#waking-phones).

## Adding a capability

Capability work is isolated under `ios/Capabilities/<Name>/`. Each folder owns its descriptor and future views, permission adapter and handlers. Register it once in the append-only `ios/App/Capabilities.swift` list. XcodeGen includes the entire directory automatically. Keep registry entries from both sides when resolving merges. [Capabilities → Adding commands](../docs/capabilities.md#adding-commands) covers handlers and App Intents.

## Versions

- The marketing version is `MAJOR.MINOR.PATCH`. MAJOR stays 0 while the app is only on TestFlight. Raise MINOR, and reset PATCH to 0, when an upload adds or changes something a user can see. An upload that only fixes things keeps the marketing version and raises only the build number, because each new marketing version waits for a new Beta App Review. PATCH is for fixes to a version already released on the App Store.
- The build number is one integer for the whole app. Raise it by one for every upload and never reuse or reset it, including when the marketing version changes. App Store Connect refuses a number it has already seen.
- `ios/project.yml` keeps `0.1` and `1` for local builds. The release script stamps the real numbers into the archive with `--version` and `--build`.
- Tag the commit of every uploaded build `v<version>+<build>`, for example `v0.1.2+5`, and push the tag. The tag is the record of what each TestFlight build contains.

The release steps are in [docs/release.md](../docs/release.md).
