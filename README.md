# Wirex Mobile SDK for iOS

Wirex card and wallet features for a partner iOS app. The partner app never handles the card values.

- **Reveal** (`WirexReveal`, `WirexRevealFieldView`) shows cardholders their own card number, expiry,
  CVV and PIN. The SDK draws each field; the host places it and supplies strings, colours and icons.
- **Collect** (`WirexCollect`, `WirexCollectForm`) takes a card the user is entering and returns a
  token in place of the card values.
- **Wallet top-up** (`WirexWalletCheckoutView`) hosts the Wirex checkout with Apple Pay.

Use of the SDK requires an agreement with Wirex. See [LICENSE](LICENSE).

## Requirements

- iOS 13 or later.
- Xcode 26.5 or later. The framework's module interface can be read only by the compiler that built
  it or a later one.

## Installation

### Swift Package Manager

Add the package in Xcode (**File › Add Package Dependencies…**) with this URL:

```
https://github.com/wirexpay/baas-mobile-ios-sdk
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/wirexpay/baas-mobile-ios-sdk", from: "0.3.1")
```

Then add the `WirexMobileSDK` product to your target.

### CocoaPods

```ruby
pod 'WirexMobileSDK', '~> 0.3.1'
```

Both install the same `WirexMobileSDK.xcframework`, attached to the GitHub release of each version.
Swift Package Manager checks it against the checksum in `Package.swift`, and CocoaPods against the
`sha256` in the podspec.

## Environments

The SDK supports two environments, `production` and `test`, and the same two apply to every surface.
The host chooses one with `testMode`, or by name. The SDK holds the addresses, and no public API takes
a URL. An unknown name is an error: the SDK never falls back to another environment.

The card surfaces also need the chain ID of the partner's integration. It is passed when the
environment is created and sent with every request.

## Credentials

The SDK never issues credentials. The host implements `WirexCredentialProvider`, which supplies:

- the user's access token;
- an action token for each `WirexActionScope` the SDK asks for;
- the user's email and wallet address.

The SDK asks for a token when it needs one, so the host never has to push tokens in advance.

## Documentation

Every public type and member is documented in the framework and appears in Xcode's Quick Help.
