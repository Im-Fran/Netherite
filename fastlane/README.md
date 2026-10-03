fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### test

```sh
[bundle exec] fastlane test
```

Run the core tests

### certificates

```sh
[bundle exec] fastlane certificates
```

Create or sync the App Store certificates and profiles for both platforms

----


## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload an iOS/iPadOS build to TestFlight

----


## Mac

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Build and upload a macOS build to TestFlight

### mac direct

```sh
[bundle exec] fastlane mac direct
```

Build the notarized Developer ID app as build/Netherite.dmg and build/Netherite.zip (+ .zip.sig for OpenUpdater)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
