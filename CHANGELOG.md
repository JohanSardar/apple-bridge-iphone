# Changelog

Changes a user of the app would notice. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). There are no tagged
releases, and no build has passed Beta App Review for the public TestFlight
link yet; the first one will collect everything under **Unreleased**. Changes to BOGO's Mac side are in
[BOGO's changelog](https://github.com/JohanSardar/bogo/blob/main/CHANGELOG.md).

## Unreleased

### Added

- Front page, security policy, contributing guide, docs index, and issue and
  pull request templates.
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

- One design across every screen of the app, BOGO and Apple Bridge alike, with
  the rules in [docs/design.md](docs/design.md).
- The repo now stands alone: it builds without the Apple Bridge Mac repo, Go,
  Node or pnpm.

### Fixed

- Pairing verifies the Mac's signing key, and Live Activity state is read from
  sealed commands.
- The Weather shortcut, whose intent had been deleted, is gone.
