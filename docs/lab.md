# Lab and qualification

How the app's behaviour is checked beyond `make test`: lab scenarios that run
the app's production Swift against a real Apple Bridge gateway with fake
device adapters, and runners that qualify a real iPhone. This is for working
on the Apple Bridge side of the app. The BOGO tab's checks are in
`make test` ([Build, run and pair](../ios/README.md#checks)).

The scenarios live in [the Mac repository](https://github.com/JohanSardar/apple-bridge),
because they start its real gateway. Clone both, then run each scenario from
the Mac repository with `APPLE_BRIDGE_IPHONE_ROOT` pointing at this checkout:

```sh
APPLE_BRIDGE_IPHONE_ROOT=/path/to/apple-bridge-iphone \
 go run ./cmd/bridge-lab run lab/scenarios/iphone/APP-SHELL-SIM.yaml --level sim
```

The gateway's [feature graph](https://github.com/JohanSardar/apple-bridge/blob/main/features.yaml)
tracks these journeys.

## Scenarios

| Scenario | Lab file (`--level sim`) | Real-device file (`--level real`) |
|---|---|---|
| app shell | `APP-SHELL-SIM.yaml` | `APP-SHELL-REAL.yaml` |
| pairing | `APP-PAIR-SIM.yaml` | `APP-PAIR-REAL.yaml` |
| command delivery | `APP-CMD-SIM.yaml` | `APP-CMD-REAL.yaml` |
| notifications | `APP-NOTIFY-SIM.yaml` | `APP-NOTIFY-REAL.yaml` |
| alarms | `APP-ALARM-SIM.yaml` | `APP-ALARM-REAL.yaml` |
| Health read | `APP-HEALTH-SIM.yaml` | `APP-HEALTH-REAL.yaml` |
| Health write | `APP-HEALTH-WRITE-SIM.yaml` | `APP-HEALTH-WRITE-REAL.yaml` |
| location | `APP-LOC-SIM.yaml` | `APP-LOC-REAL.yaml` |
| Screen Time | `APP-SCREENTIME-SIM.yaml` | `APP-SCREENTIME-REAL.yaml` |
| Live Activities and widgets | `APP-LIVE-SIM.yaml` | `APP-LIVE-REAL.yaml` |
| capture | `APP-CAPTURE-SIM.yaml` | `APP-CAPTURE-REAL.yaml` |
| App Intents | no YAML; see below | `APP-INTENTS-REAL.yaml` |
| build | | `APP-BUILD-REAL.yaml` |
| motion | | `APP-MOTION-REAL.yaml` |
| device context | | `APP-DEVICE-REAL.yaml` |
| Focus sync with a second Mac | | `FOC-PHONE-SYNC.yaml` |

The files are in `lab/scenarios/iphone/` in the Mac repository. The approval
real-device scenario (`APP-APPROVE-REAL.yaml`) is retired: the BOGO tab
replaced the Face ID approvals it tested, and the app answers it as
unsupported.

## Lab scenarios

The app shell lab scenario (`APP-SHELL-SIM.yaml`) runs the app’s shared Swift shell and pairing models locally with injected connection responses. It checks Settings/BOGO/Diagnostics tab structure, unpaired/paired/connecting/connected/offline/reconnected status and failed pairing recovery. No device, network service, Keychain access or permission prompt is needed. This qualifies view-model behavior, not pixel layout or biometrics; the app shell real-device scenario covers the physical capability and diagnostics inspection.

The pairing lab scenario runs with `APPLE_BRIDGE_SECRET_STORE=file go run ./cmd/bridge-lab run lab/scenarios/iphone/APP-PAIR-SIM.yaml --level sim`. On a real phone, the QR code and local-network permission prompts need an Allow tap.

The command delivery lab scenario runs with `APPLE_BRIDGE_SECRET_STORE=file go run ./cmd/bridge-lab run lab/scenarios/iphone/APP-CMD-SIM.yaml --level sim`. It covers durable offline admission, encrypted relay delivery, signed results, replay/dedupe, expiry and read-agent denial. `go test ./internal/relay` verifies APNs JWT signing and background headers. The isolated gateway fixture writes its synthetic API token to `api-token` for Swift simulator round trips.

The Screen Time lab scenario compiles the same Swift shield policy against a fake ManagedSettings adapter and checks app/category/domain shield/unshield, separate downtime ownership, overnight schedule validation and gateway command admission. Simulator UI and build verification is separate.

The Live Activities lab scenario exercises signed pairing/token registration, gateway admission, ActivityKit start/update/end payloads and APNs headers, duplicate-start suppression, and token revocation using a local APNs fixture. Simulator Xcode builds cover the extension and app. Visual simulator inspection also requires an unclaimed simulator.

The App Intents compile proof has no YAML: build the AppleBridge scheme for iOS or the simulator, then run `python3 lab/iphoneintents/check.py <path-to-AppleBridge.app>`. It checks every registered iPhone handler against extracted App Intent metadata and verifies Siri phrase extraction. The local dispatcher proof is `swiftc -parse-as-library ios/Capabilities/Siri/CommandIntent.swift lab/iphoneintents/main.swift -o /tmp/ab-intent-dispatch && /tmp/ab-intent-dispatch`; it checks JSON results, local identity, disabled commands and invalid arguments. The App Intents real-device scenario requires a saved Shortcuts workflow containing Ping iPhone and a real run returning `{"pong":true}`. Importing or saving a workflow, or allowing Shortcuts, needs a tap on the phone; record the run as limited until that is available.

The other lab scenarios each compile the capability's production Swift
against a fake adapter; [Capabilities](capabilities.md) describes what each
one covers.

## Real-device runners

These need a physical iPhone paired to the Mac, a signed Debug build
([maintainer notes](maintainers.md#signed-device-builds)) and a person at the
phone, or the automation the [qualification record](real-qualification.md)
describes. The sensor runners are documented in
[`lab/iphone-real/README.md`](../lab/iphone-real/README.md).

The seven shell and delivery real-device scenarios use the Debug-only `--ab-real` entry point. Build and install once after changing Swift; subsequent runs reuse that build. Set `AB_REAL_DEVICE` to the paired physical identifier from `xcrun devicectl list devices` and `APPLE_BRIDGE_SECRET_STORE=file`, then run the corresponding YAML with `bridge-lab --level real --json`. The runner holds `lockf -k -t 3600 /tmp/ab-iphone.lock` throughout each run and restoration. It copies a private request into the app container, launches the installed app, and copies a nonce-bound receipt back. The request is removed on the phone. Evidence retains only checks, counts and digests; ephemeral gateway credentials and pairing codes are deleted with the isolated test home.

Pairing and delivery create an isolated pinned HTTPS listener on the Mac. `AB_REAL_HOST` overrides the phone-reachable address (default: en0); the phone must reach that address. Delivery requires the app's development APNs key; set its path with `AB_REAL_APNS_KEY`. The runner never falls back to a simulated push. The command delivery real-device scenario requires an actual APNs callback and a signed pong in the gateway ledger. Notification interaction requires the exact test button action. Approval requires the production biometric policy and the signed command result.

The runner prints `>>>` instructions for the person at the phone and allows three minutes per interaction phase. Shell inspection uses the production capability and diagnostics views. Live qualification starts, updates and immediately ends only its own tagged ActivityKit activity; confirm the tagged widget and Lock Screen content on the phone. Intents qualification requires saving and running a tagged Ping iPhone shortcut in Shortcuts; the production intent records its pong, and cleanup requires deleting that shortcut and confirming on the phone. Directly invoking `perform()` from the probe cannot satisfy that receipt.

The phone stores its previous identity, relevant switches and widget status in a protected backup before qualification. Completion restores them. A separate `--ab-real-restore <run>` launch returns a restoration receipt before unlocking, including after a timeout. A later app launch also retries restoration after interruption. Do not install a different worker's build between runs unless it contains both workers' qualification entry points.

## Results

[Real iPhone qualification](real-qualification.md) is the record of what was
measured on a physical iPhone, and what remains unproved.
