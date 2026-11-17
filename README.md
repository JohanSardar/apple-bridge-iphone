# Apple Bridge for iPhone

The native iPhone companion for [Apple Bridge on Mac](https://github.com/JohanSardar/apple-bridge). This repository owns the app, capabilities, pairing client, encrypted delivery client, widgets, extensions, iOS builds and TestFlight tooling. It builds without the Mac repository, Go, Node or pnpm.

## Build and check

Use Xcode 26.4+ and XcodeGen (`brew install xcodegen`). From this repository:

```sh
make simulator
make lint
make test
```

`make simulator` builds the app and extensions without signing. `make test` compiles and executes eleven production Swift models with fake adapters, then runs the existing release and harness tests. These checks run locally without an iPhone, permission prompts, personal data or gateway. On the Air, run each step through `~/bin/ab-local`; it supplies the compatible Mac SDK for the model checks. Full app builds require Xcode.

For a signed device build, configure the existing private development profiles described in [the app guide](ios/README.md), then run `make build`. Installation remains explicit through `packaging/dev/install-ios.sh`. Generated projects, app products, provisioning profiles and credentials stay outside git. Bundle IDs and signing settings are unchanged.

## Gateway connection

The Mac gateway owns `/v1/iphone/*`, command admission, the ledger, signed record ingestion and relay/APNs delivery. This app owns local execution, permissions, device keys and receipts. Pairing and the wire format are unchanged. Neither repository imports the other's source to build its product.

Cross-repository scenarios remain in the Mac repository because they start its real gateway. Clone both repositories, then run there with `APPLE_BRIDGE_IPHONE_ROOT` pointing to this checkout:

```sh
APPLE_BRIDGE_IPHONE_ROOT=/path/to/apple-bridge-iphone ~/bin/ab-local go run ./cmd/bridge-lab run lab/scenarios/iphone/APP-SHELL-SIM.yaml --level sim
```

The gateway's [feature graph](https://github.com/JohanSardar/apple-bridge/blob/main/features.yaml) tracks these integrated journeys. [Physical qualification history](docs/real-qualification.md) records earlier measurements and limitations; moving repositories does not qualify new hardware behavior.

## TestFlight

[docs/release.md](docs/release.md) lists the release steps from `main` to the public TestFlight link: archive and upload with `packaging/release/testflight.py --external --upload`, then put the build in the public group and submit it for Beta App Review with `packaging/release/testflight_public.py --submit`. Both scripts read the private release settings, which stay outside git.

A Mac running BOGO needs `"production"` in `approvers.iphone.app_attest` to pair with a TestFlight build, because TestFlight builds use App Attest's production environment.

Imported from `JohanSardar/apple-bridge` at `030ebf5e00c25389205f91f682fb3e3f834e3b12`, retaining the filtered history of the app and moved tooling. The original license and engineering principles are included.
