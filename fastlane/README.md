fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios privacy

```sh
[bundle exec] fastlane ios privacy
```

Upload + publish App Privacy details (nutrition labels). Interactive: this
        rides Apple's private web API, so it asks for your Apple ID password + 2FA.

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Push App Store text metadata (all localizations) — no binary, no screenshots

### ios release

```sh
[bundle exec] fastlane ios release
```

Archive + upload a new build to App Store Connect. No metadata/screenshots
        touched, no submission — the build lands in TestFlight/ASC processing and
        a human decides when (and whether) to submit it for review.

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Push App Store screenshots (draft metadata only) — no binary, no text metadata, no submission

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
