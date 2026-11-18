# Changelog

Changes a user of the app would notice. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). There are no tagged
releases, and no build has passed Beta App Review for the public TestFlight
link yet; the first one will collect everything under **Unreleased**. Changes to BOGO's Mac side are in
[BOGO's changelog](https://github.com/JohanSardar/bogo/blob/main/CHANGELOG.md).

## Unreleased

### Added

- Add a Mac from another network: in Add Mac, tap "Mac not listed? Use a
  code", then scan the code `bogo approver add` shows on the Mac or type it.
  The 6 digits are compared as before.
- When adding a Mac fails on the phone, the phone and the Mac both say why,
  for example a Keychain or App Attest error.
- Pushes from BOGO's relay open the newest waiting request.
- A five-minute start for BOGO on the front page, with a recording of an
  approval.
- Add Mac lists BOGO Macs nearby, found over Bonjour, and the 6-digit check
  runs over a private room on BOGO's relay. The app uses BOGO's public relay
  by default, with no setting, or the relay a Mac's code names.
- Front page, security policy, Code of Conduct, contributing guide, docs
  index, and issue and pull request templates.
- The BOGO tab, which replaces the old Approvals tab: add a Mac with matching
  codes and Face ID, review each request on the Review card with the agent's
  pictures and highlighted values, see every value under All details, slide to
  approve with Face ID, or deny with a note. Activity lists past requests.
- BOGO's relay link: registration with App Attest, and encrypted requests and
  decisions through BOGO's own relay.
- The public [TestFlight link](https://testflight.apple.com/join/dQu75bv1) and
  the [release steps](docs/release.md) that ship builds to it.
- Settings → Demo in Debug builds, which sends realistic requests from a
  stand-in Mac.

### Changed

- The BOGO install command uses GitHub directly, without the relay redirect.

- The app guide is now a short [Build, run and pair](ios/README.md) guide,
  with [Capabilities](docs/capabilities.md), [Lab and
  qualification](docs/lab.md) and [Maintainer notes](docs/maintainers.md) on
  their own pages.

- One design across every screen of the app, BOGO and Apple Bridge alike, with
  the rules in [docs/design.md](docs/design.md).
- The repo now stands alone: it builds without the Apple Bridge Mac repo, Go,
  Node or pnpm.

### Fixed

- `make simulator` builds an app whose Keychain works, so it can be added to
  a real Mac, and `make simulator` and `make test` print no warnings.
- Pairing verifies the Mac's signing key, and Live Activity state is read from
  sealed commands.
- The Weather shortcut, whose intent had been deleted, is gone.
