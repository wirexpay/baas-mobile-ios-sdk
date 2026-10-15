# Wirex Mobile SDK — iOS example

A native iOS app (UIKit) that exercises **every surface** of `WirexMobileSDK` — card **Reveal**, card
**Collect**, the **3-D Secure** step-up and **Wallet** top-up (Apple Pay / Google Pay). One `import
WirexMobileSDK` brings all four; the wallet surface is part of the same package.

## Install

The app resolves the published SDK via Swift Package Manager (`project.yml` → `WirexMobileSDK` from
`github.com/wirexpay/baas-mobile-ios-sdk`). The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open WirexMobileSdkExample.xcodeproj
```

Build and run on a simulator or device from Xcode.

## The environment

`Sources/SdkConfig.swift` holds the environment NAME this build talks to (a name, never a URL — the SDK
maps it onto the hosts it holds). Set it to the environment Wirex assigned (`test` or `production`).

## Enter credentials on device

Nothing is compiled in. Each surface reads the credentials from `LiveConfig`, which you fill at runtime:

**Paste JSON** on the Reveal or Collect screen (the "credentials" box), e.g.
`{"bearer":"…","email":"…","cardId":"…","chainId":"…","actionToken":"…","cardholderName":"…"}` — a
key you omit keeps its value; an empty string clears it. Credentials are never passed on the command
line — a bearer in a process's argument vector is visible in `ps` and in logs.

## The surfaces

| Tab | What it shows |
|---|---|
| **Reveal** | the cardholder's own PAN / expiry / CVV / PIN in sealed native rows |
| **Collect** | a sealed form that tokenizes an external funding card at the acquirer |
| **3DS** | paste a top-up orchestrator URL → the issuer challenge, and the outcome |
| **Wallet** | an availability probe + the hosted Apple Pay / Google Pay checkout (paste a provider block, build a quote; token mode via a checkout token) |

The field contract is the same across the React Native / Android / Flutter examples — see
`../PARTNER-CONFIG.md`.

> A revealed value is drawn in a capture-proof layer that the **iOS Simulator renders blank** — that is
> PCI protection, not a bug. The Apple Pay sheet likewise cannot present on the Simulator; the checkout
> still arms, only the sheet needs a real device.
