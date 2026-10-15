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

## Configure on device

Nothing is compiled in. The **Config** tab is a per-field editor over `LiveConfig`, the single store
every surface reads live — type a value and the next call picks it up, no rebuild. It holds:

- the **environment** (`test` / `production`), a name the SDK maps onto the hosts it ships with;
- integration parameters — chain id, user email, user wallet, card id, cardholder name;
- secrets (bearer, step-up action token), held in memory only and never persisted or logged.

Credentials are never passed on the command line — a bearer in a process's argument vector is visible
in `ps` and in logs.

## The surfaces

| Tab | What it shows |
|---|---|
| **Config** | a per-field editor for the environment, integration parameters and secrets, shared by every surface |
| **Reveal** | the cardholder's own PAN / expiry / CVV / PIN in sealed native rows |
| **Collect** | a sealed form that tokenizes an external funding card at the acquirer |
| **3DS** | paste a top-up orchestrator URL → the issuer challenge, and the outcome |
| **Wallet** | an availability probe + the hosted Apple Pay / Google Pay checkout (paste a provider block, build a quote; token mode via a checkout token) |
| **Appearance** | restyle every sealed surface at once — presets or a pasted token document |

The field contract is the same across the React Native / Android / Flutter examples — see
`../PARTNER-CONFIG.md`.

> A revealed value is drawn in a capture-proof layer that the **iOS Simulator renders blank** — that is
> PCI protection, not a bug. The Apple Pay sheet likewise cannot present on the Simulator; the checkout
> still arms, only the sheet needs a real device.
