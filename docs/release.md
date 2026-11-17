# Releasing to TestFlight

These steps take the current `main` to a TestFlight build anyone can join from the public link. Follow them from the top for every release. No value from the release settings, key, keychain password or contact file belongs in this repository, a log or a chat.

The app record is `Apple Bridge` (bundle ID `com.johansardar.applebridge.ios`). The public link lives on the external TestFlight group `Public`.

## What you need

- Xcode 26.4+, XcodeGen and Python 3 with `pyjwt` and `cryptography` (`python3 -m pip install pyjwt cryptography`).
- The private release settings in `~/.config/apple-bridge-release/`:
  - `release.env` exports `APPLE_DEVELOPER_TEAM_ID`, `IOS_DISTRIBUTION_IDENTITY`, `RELEASE_KEYCHAIN`, `ASC_KEY_PATH`, `ASC_KEY_ID` and `ASC_ISSUER_ID`.
  - `profiles-release.json` maps the app and its four extensions to their App Store distribution profiles. They include Family Controls and expire 2027-10-31. Renew them before then.
  - `keychain.password` unlocks the dedicated release keychain.
  - `testflight-contact.json` holds the Test Information feedback email and the Beta App Review contact, in this shape:

    ```json
    {"feedbackEmail": "", "contactFirstName": "", "contactLastName": "", "contactPhone": "", "contactEmail": ""}
    ```

    Testers can see the feedback email. Only Apple sees the review contact. Use details already on the developer account, and never commit this file.

## 1. Pick the version

Use a new build number, higher than every build already uploaded. App Store Connect → Apple Bridge → TestFlight lists them, or read them with the API. Keep the marketing version (such as `0.2.0`) until a release changes what the app does.

## 2. Check main

From a clean checkout of `main`:

```sh
make lint
make test
```

## 3. Archive, export and upload

Unlock the release keychain first, or code signing fails with `errSecInternalComponent`:

```sh
source ~/.config/apple-bridge-release/release.env
security unlock-keychain -p "$(cat ~/.config/apple-bridge-release/keychain.password)" "$RELEASE_KEYCHAIN"
python3 packaging/release/testflight.py \
  --profiles ~/.config/apple-bridge-release/profiles-release.json \
  --output ~/Desktop/applebridge-<version>-<build> \
  --version <version> --build <build> --external --upload
```

`--external` exports a build external testers can install. Without it the build is internal-only and can't join the public group. Builds 4 and 5 (0.1.2) were uploaded that way. The script prints `R1-TESTFLIGHT passed=true external=true uploaded=true` when the upload is accepted. It changes no signing setting: it signs with the existing distribution identity and profiles.

Export compliance is answered by `ITSAppUsesNonExemptEncryption = false` in `ios/App/Info.plist`, so App Store Connect asks nothing after upload. Keep it unless the app adds encryption beyond Apple's.

## 4. Public group and Beta App Review

```sh
python3 packaging/release/testflight_public.py --version <version> --build <build> \
  --contact ~/.config/apple-bridge-release/testflight-contact.json --submit
```

It waits for processing (up to an hour), checks export compliance, and sets the Test Information from `packaging/release/testflight/`:

- `beta-description.txt`: what testers read about the app.
- `whats-new.txt`: What to Test for this build. Update it every release.
- `review-notes.txt`: the notes for Beta App Review. Reviewers have no Mac running BOGO or the Apple Bridge gateway, so the notes say what the app does and what they can see without one.

Then it makes sure the external group `Public` exists with its public link on and no tester limit, adds the build, and submits the build for Beta App Review. It prints the public link and the review state. Without `--submit` it stops before the review. If a contact field is missing it names the field and submits nothing. Every step is safe to rerun.

The first build of a marketing version waits for Beta App Review, usually a day. Later builds of the same version usually go live without a new review. The public link shows "This beta isn't accepting any new testers right now" until a build in the group is approved.

## 5. Check

- The script ends with `beta app review: WAITING_FOR_REVIEW`, `IN_REVIEW` or `APPROVED`.
- `curl -sL <public link> | grep -o '<title>[^<]*</title>'` shows the TestFlight join page for Apple Bridge.
- Once approved, open the link on an iPhone, install, and check the BOGO, Activity and Settings tabs.

## Pairing a TestFlight build with BOGO

A TestFlight build attests with App Attest's **production** environment. A development build attests with the development environment. The BOGO daemon on the Mac accepts only the environments listed in `approvers.iphone.app_attest` in its config, so a Mac pairing with a TestFlight build needs `"production"` in that list:

```toml
[approvers.iphone]
app_attest = ["production"]          # TestFlight or App Store build
# app_attest = ["production", "development"]  # also accept your own Xcode builds
```

Restart the daemon after editing (`bogo stop`, then `bogo start`). The release itself never changes anyone's Mac config.

The TestFlight build also uses production push (APNs), set by `testflight.py`.
