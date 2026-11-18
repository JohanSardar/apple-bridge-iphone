# Capabilities

What each Apple Bridge capability on the iPhone does, the commands Apple
Bridge's gateway on the Mac sends it, and the permission it needs. Every
capability stays off until you turn it on in the app. The BOGO tab is
separate and uses none of these; see [Build, run and
pair](../ios/README.md#pair-with-bogo-on-your-mac).

The Mac gateway owns `/v1/iphone/*`, command admission, the ledger, signed
record ingestion, and relay and APNs delivery. The app owns local execution,
permissions, device keys and receipts. The lab scenarios named below are
listed in [Lab and qualification](lab.md). What has been measured on a real
iPhone, and what hasn't, is in the [qualification record](real-qualification.md).

## Pairing

On the Mac, run `bridge pair --iphone --via-remote`, then scan the QR from the app’s Pairing screen (or paste its `ab1-` code). The app stores Ed25519 signing and X25519 encryption keys in a device-only Keychain item accessible after first unlock. The phone-only one-time proof binds both public keys to the code. Replica enrollment rejects phone codes. The phone receives no gateway API grants. `iphone.devices` lists device IDs for `bridge revoke <id>`.

A pairing code carries the Mac's signing key. The app refuses a remote code without it, requires the response to return the same key, and checks an HMAC over the response keyed by the pairing secret, so a server holding a valid certificate can't substitute its own key. A remote code issued by an older Mac must be issued again. A direct test code without the key still works, because its TLS fingerprint pin authenticates the channel. A phone paired earlier keeps its saved key. A remotely paired phone with no saved key must pair again, because nothing would authenticate a key fetched over public TLS.

Remote pairing validates the relay’s normal HTTPS certificate. Direct test HTTPS pins the certificate fingerprint in the QR. The replication mTLS port is not an iPhone endpoint. For isolated testing, `APPLE_BRIDGE_SECRET_STORE=file go run ./lab/iphonegateway -home /tmp/ab-test-iphone -address https://<reachable-host>:17781` writes a private code file and serves an iOS-compatible TLS certificate. `--pair-code <code>` is an app launch seam for unattended lab pairing; do not put the code in evidence.

## Delivery

Delivery: The relay runs with `-apns-key <private-p8-path>` and `-apns-sandbox=true` for the development profile (`false` for production). Team, key ID and topic are fixed to the provisioned app. The gateway uses its existing private relay identity to authenticate `/iphone/push`; only signed ciphertext reaches the relay/APNs. Keys and APNs tokens must never be committed.

The app registers for silent pushes at launch; silent delivery does not need notification-alert permission. Pairing/local-network/camera prompts still need a tap on the phone. APNs background delivery is best effort, so the locked-phone under-five-second scenario must be measured on hardware and is not a latency guarantee.

`iphone.ping` takes `{"device_id":"iphone:…"}` inside the normal command envelope. Commands use the existing ledger, grants and owner approval. Admitted jobs survive restart; signed, encrypted jobs are dispatched on push or fetch. Expiry after possible dispatch is indeterminate. Device-only receipts prevent rerunning an ambiguous operation and retain signed results for upload after reconnecting.

## Notifications

`iphone.notify` takes `device_id`, `title`, `body`, optional `buttons: [{id, title}]` (up to four), `thread`, and `time_sensitive`. Enable Notifications in the phone settings screen and allow alerts first. iOS notification settings and Focus determine actual presentation; time-sensitive delivery does not bypass the user's choices. The thread groups notifications in Notification Center. Disabled capabilities reject commands before scheduling.

With no buttons, the signed result is `{"delivered":true}` after iOS accepts the local notification request. With buttons, the command stays dispatched until a tap returns `{"action_id":"<id>"}` or opening/dismissing it returns `{"dismissed":true}`. Action receipts are saved on the phone before upload and retried on wake/foreground. Command expiry still applies, so unanswered notifications can become indeterminate. No notification content is sent in plaintext through the relay.

## Alarms and timers

AlarmKit commands use `iphone.alarm.create/list/update/cancel` and `iphone.timer.start/cancel` through the existing push delivery path. Enable Alarms and timers in the app first. Arguments always include `device_id`; create/update take `fire_at` (Unix seconds), optional `title` and `snooze_seconds` (default 540). Update replaces the schedule for `id`; cancel takes `id`. Timer start takes `duration_seconds`. Optional UUID `id` on create/start allows callers to choose an identity. List reads the app's AlarmKit alarms, including their current system state. AlarmKit provides the system alarm sound through Silent and Focus, Stop, and a Snooze countdown. The first command requests AlarmKit authorization; permission must be allowed on the phone. The alarms lab scenario runs the production Swift command handler with a fake adapter. On hardware, the alarms real-device scenario schedules a tagged alarm a minute ahead, reads it back, then cancels it.

The embedded AlarmActivity widget renders AlarmKit countdowns on the Lock Screen and Dynamic Island. Signed builds embed it with its own provisioning profile ([maintainer notes](maintainers.md#provisioning-profiles)).

## Health

Enable Health read and choose “Allow Health read access” on the phone. HealthKit deliberately does not disclose whether read access was denied; an empty capture is not proof of permission. The app only requests read access. Anchored pages, pending uploads and acknowledgements are persisted with file protection. Each paired device and sample type has an independent upload sequence; the gateway atomically commits `health.sample` changes and rejects gaps or altered retries. Deleted samples remain tombstones. Capture resumes on launch, foreground and HealthKit observer wakes; iOS controls background timing. Unsupported background-delivery types still refresh on foreground. Medication dose events use anchors; medication concepts use incremental snapshot comparison because HealthKit does not expose anchored concept queries. Workout routes retain their workout UUID and coordinates.

`health.summary` takes `period` (`day` or `week`), `date` (`YYYY-MM-DD`), optional `time_zone` (default UTC), and optional `device_id`. Weeks begin Monday in that zone. It requires `health:read`. Results group by HealthKit type, unit and category (including individual sleep stages), with count, sum, average, minimum, maximum and clipped duration seconds. Quantity samples belong to their start date; duration samples can span windows. Sums are raw captured sample totals and may include overlapping sources; they do not claim parity with the Health app's deduplicated statistics. Use `records.query` with collection `health.sample` for the original records. The Health read lab scenario exercises the shared capture engine with a fake HealthKit store and signed gateway ingestion.

### Writing to Health

enable Health write, then tap Allow Health write access on the phone. `iphone.health.log` takes `device_id`, `kind` (`water`, `weight`, `mindful`, `workout`), positive `value`, RFC3339 `start`, and `tag` (1–128 UTF-8 bytes). Values use ml, kg, minutes and minutes respectively. Workouts also require `activity` (`walking`, `running`, `cycling`, `other`). The command checks existing write authorization without prompting and returns the saved sample UUID. Day and week summaries use the existing Health read capture and `health.summary` path.

The Health write lab scenario validates the shared Swift write/read/delete sequence for all four tagged sample types and signed command delivery. After granting read and write access for these four types, tap Test tagged Health write and cleanup. It writes each `[ab-test]` sample, queries its UUID and tag, deletes only the app-owned test sample using its retained handle (including on a failed read), and checks it is absent. The screen reports pass or incomplete; no personal samples enter evidence.

## Location

enable Location, tap Allow Location, then enable Always and Precise Location in iOS Settings. `iphone.location.current` takes `device_id`; `iphone.geofence.add` also takes `name`, `latitude`, `longitude`, and `radius` in meters (maximum 20 named regions); `iphone.geofence.remove` takes `name`; `iphone.geofence.list` republishes the named region definitions. `iphone.location.significant` takes `enabled`. Background monitoring requires Always authorization; current location requires full accuracy. The phone retains monitoring settings across launches and queues records atomically until a signed upload succeeds.

Read `iphone.location` with the `iphone:read` grant for precise samples, named geofences, and `arrive`, `leave`, or `significant` events. Records are scoped to their paired device and deduplicated on retry. Removing a geofence publishes `geofence_removed`. Command receipts contain counts and monitoring state, never coordinates; location payloads travel on the separate signed record-ingestion endpoint. iOS controls background delivery timing. The location lab scenario compiles and runs the actual Swift location store with a fake adapter, then uploads its records through the signed gateway endpoint and checks durable deduplication.

## Screen Time

Authorize on the phone, enable the capability, and choose opaque app/category/website tokens with Apple's picker. `iphone.screentime.shield` and `unshield` affect the named `bridge.manual` store; `schedule` takes `start_minute` and `end_minute` (local wall-clock minutes, repeating daily, at least 15 minutes, overnight supported); `cancel` stops only `bridge.downtime` and clears its separate store. Unshield does not cancel downtime. Apple's settings and other apps' stores are untouched. App and website usage is displayed inside the privacy-preserving DeviceActivity report extension for the current day; no usage data is exported to the gateway.

The Screen Time extensions need their own App IDs, profiles and App Group ([maintainer notes](maintainers.md#screen-time-provisioning)).

## Live Activities and widgets

Enable **Live Activities and widgets** in the app. The phone registers its ActivityKit push-to-start token and each running task's update token through signed `/v1/iphone/live-token` requests. Disabling ends local activities and revokes registered tokens through `/v1/iphone/live-disable` when reachable.

`iphone.live.start`, `iphone.live.update` and `iphone.live.end` require `iphone:write` and take `device_id`, a stable `task_id`, `title`, `status`, and `progress` between zero and one. Start uses the push-to-start token; wait for the phone to register the task token before update/end can dispatch. Each command is sent once through the authenticated relay using the ActivityKit APNs topic and push type. That push carries only fixed text, progress 0 and an opaque task handle, because the relay and Apple can read it and nothing signs it. Treat it as a wake-up with no security meaning: a dishonest push sender can still change or end what it shows. Real title, status and progress arrive as a sealed command the app opens with its paired gateway key, then applies locally. The app returns a receipt once it has applied them. If the app can't wake, or the Activity hasn't appeared after ten seconds, the generic text stays. Missing tokens leave commands queued until expiry. Do not retry start under a new command ID unless another activity is intended.

BridgeWidgets renders task title, status and progress on the Lock Screen and Dynamic Island. Its home-screen and rectangular/inline lock-screen widgets show the last delivery status with its age, rather than claiming current connectivity. The snapshot uses a shared Keychain access group (`$(AppIdentifierPrefix)com.johansardar.applebridge.ios.widgetstatus`) with after-first-unlock, device-only protection. Signed builds embed the widget extension with its own profile ([maintainer notes](maintainers.md#provisioning-profiles)).

## Capture

`iphone.capture.photo` and `iphone.capture.audio` always come back rejected. Capture depended on the removed Face ID approvals, so its command handlers are gone and Camera and microphone shows as unavailable. The capture model and adapter remain for the capture lab scenario.

The signed `/v1/iphone/capture` endpoint accepts bytes only for the paired target’s live dispatched command and matching request hash. It stores them in the gateway blob store and returns `blob_id`, `digest`, `size`, and `content_type`. Use the existing query-blob download path with that `blob_id`; access belongs to the command’s requesting principal under `iphone:write`, with the existing one-hour query-blob grant lifetime. The capture lab scenario executes the shared Swift capture flow with a fake adapter and proves signed gateway upload, retrieval, and retry binding for both commands.

## App Intents and Siri

App Intents live beside each capability's handlers in `<Capability>Intents.swift`. Each command has a concrete intent returning its JSON result; commands with arguments expose an Arguments JSON text parameter using the same command fields above (local execution supplies `device_id: iphone:local` automatically). Intents use `CommandHandlers.all`, so disabled capabilities remain disabled and adapter permission checks still apply. Failures propagate to Shortcuts. Ping is always available.

Each folder registers its actions by defining concrete App Intent types; no central intent list is required. `BridgeShortcuts` in the Siri folder supplies optional ready-made Siri phrases. Add future commands' intents in their capability folder, then optionally add a phrase to that provider. App Intents are extracted automatically by Xcode from all capability folders. Siri phrases use “<command title> with Apple Bridge”. In Shortcuts, select the Apple Bridge action, fill its arguments, and save the shortcut; select that shortcut in Settings → Action Button → Shortcut. iOS allows at most ten App Shortcuts; additional commands can remain discoverable App Intent actions and run through saved Siri shortcuts.

## Adding commands

Future capability folders supply `Capability.handlers`; the sole capability registration remains `App/Capabilities.swift`. Enabled, available capabilities contribute handlers automatically. Each gateway command owns an `iphone_<command>_descriptors.go` file and registers its argument validator with `RegisterIPhoneCommand`. Every argument object includes `device_id`. Handlers return JSON bytes; a handler that cannot prove whether an effect occurred must throw so the result is indeterminate. Keep permission checks inside the capability handler.

Existing `Capability.handlers` keep the JSON argument/result API. A capability that waits for user interaction may instead register a `deferredHandlers` entry receiving the signed job context; returning nil leaves its receipt pending. Notifications persist their eventual response before the delivery layer signs and uploads it.
