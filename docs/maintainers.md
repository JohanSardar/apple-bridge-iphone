# Maintainer notes

> **For the maintainer's Apple developer team.** These steps use the team's
> bundle IDs, App Groups and provisioning profiles, and a machine set up for
> them. You don't need them to build, run or contribute to the app: the
> Simulator build in [Build, run and pair](../ios/README.md) needs no account.
> To sign with your own team, see
> [Signing with your own team](../ios/README.md#signing-with-your-own-team).

## Signed device builds

A signed development build needs an Apple Development identity and the development profiles for the app and each extension, saved as `~/.config/apple-bridge/ios/dev.mobileprovision`, `alarms.mobileprovision`, `ScreenTimeMonitor.mobileprovision`, `ScreenTimeReport.mobileprovision` and `BridgeWidgets.mobileprovision`. Run `make build`. It writes `.build/ios/AppleBridge.ipa`. Override the main and alarm profiles with `APPLE_BRIDGE_IOS_PROFILE` and `APPLE_BRIDGE_ALARM_PROFILE`, or the output directory with `APPLE_BRIDGE_IOS_OUTPUT`. `packaging/dev/install-ios.sh` copies the IPA to the Mac the iPhone is plugged into (`APPLE_BRIDGE_INSTALL_HOST`, an ssh host) and installs it over USB with pymobiledevice3, which must be on that Mac's PATH or in its `~/.local/bin`. Build products and generated Xcode projects are ignored.

The app uses manual signing. Extension targets (widgets, App Intents and AlarmKit features) must use their own matching provisioning profiles before embedding. The current profile has no App Group identifiers; shared containers must be provisioned before use. App Intents and AlarmKit can also be implemented in the main app target.

## Provisioning profiles

Each target is signed with its own profile, which `packaging/dev/build-ios.sh`
reads from `~/.config/apple-bridge/ios/`:

| Target | Bundle ID | Profile file |
|---|---|---|
| App | `com.johansardar.applebridge.ios` | `dev.mobileprovision` (`APPLE_BRIDGE_IOS_PROFILE`) |
| Alarm Live Activity | `com.johansardar.applebridge.ios.alarms` | `alarms.mobileprovision` (`APPLE_BRIDGE_ALARM_PROFILE`) |
| Screen Time monitor | `com.johansardar.applebridge.ios.screentimemonitor` | `ScreenTimeMonitor.mobileprovision` |
| Screen Time report | `com.johansardar.applebridge.ios.screentimereport` | `ScreenTimeReport.mobileprovision` |
| Widgets | `com.johansardar.applebridge.ios.widgets` | `BridgeWidgets.mobileprovision` |

The build script installs the profiles and signs each target with its own.

**Widgets.** Register `com.johansardar.applebridge.ios.widgets` and create an
IOS_APP_DEVELOPMENT profile with all enabled iOS devices and development
certificates. The existing development profiles authorize the shared Keychain
group; no additional App Group portal association is needed.

## Screen Time provisioning

Provision the `com.johansardar.applebridge.ios.screentimemonitor` and `.screentimereport` App IDs with Family Controls in the developer portal, then regenerate IOS_APP_DEVELOPMENT profiles through ASC including all enabled iOS devices and development certificates. Register and associate `group.com.johansardar.applebridge.ios.screentime` with the main app and monitor extension. Install profiles as `~/.config/apple-bridge/ios/ScreenTimeMonitor.mobileprovision` and `ScreenTimeReport.mobileprovision`; refresh the main profile after associating the group. `build-ios.sh` reads each target's profile independently. ASC rejects FAMILY_CONTROLS capability changes, so portal enablement is a prerequisite even though App ID/profile creation uses ASC.

## Release builds

Release builds go to TestFlight with the private release settings described
in [Releasing to TestFlight](release.md).
