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

There are no releases yet. Only the latest `main` gets security fixes.
