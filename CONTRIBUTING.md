# Contributing to the Apple Bridge iPhone app

Thanks for helping. This app carries two products, so start by finding where
your change belongs:

| Change | Where |
|---|---|
| Anything in the app: screens, capabilities, the BOGO tab, build scripts | this repo |
| BOGO's daemon, relay, request format or docs | [JohanSardar/bogo](https://github.com/JohanSardar/bogo) |
| Apple Bridge on the Mac | [JohanSardar/apple-bridge](https://github.com/JohanSardar/apple-bridge) |
| A bug in the BOGO tab | [BOGO's issues](https://github.com/JohanSardar/bogo/issues/new/choose) |
| A vulnerability | a private report, as [SECURITY.md](SECURITY.md) says |

For anything bigger than a small fix, open an issue first so we can agree on
the approach before you write it.

## How this project works

Both repos follow the same rules, written once in
[BOGO's CONTRIBUTING](https://github.com/JohanSardar/bogo/blob/main/CONTRIBUTING.md):
how the project uses AI agents, and what evidence a pull request needs. In
short: you're responsible for every line you submit, and you show what you ran
and what you saw.

The app's own engineering rules are in [PRINCIPLES.md](PRINCIPLES.md), and how
every screen should look is in [docs/design.md](docs/design.md).

## Build and check

From this repo's root, with Xcode 26.4 or later and XcodeGen:

```sh
make simulator
make lint
make test
```

`make lint` enforces the no-comments rule. [Build, run and pair](ios/README.md)
covers building and running the app, [Capabilities](docs/capabilities.md)
covers each capability, and [Lab and qualification](docs/lab.md) covers the
scenarios beyond `make test`.

## What a pull request needs

- **What changed and why**, in plain words.
- **Evidence.** What you ran and what you saw. Any change to a screen needs
  screenshots, in light and dark mode. Debug builds have Settings → Demo,
  which sends realistic requests to the BOGO tab.
- **What you could not check**, and why.
- **A line in [CHANGELOG.md](CHANGELOG.md)** under Unreleased, if a user would
  notice.

If you change how the BOGO tab decodes, shows or signs a request, say so: the
BOGO repo's request vectors must still decode the same way.

## License

By contributing, you agree that your contribution is licensed under the
[MIT license](LICENSE).
