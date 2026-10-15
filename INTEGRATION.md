# Wirex Mobile SDK (iOS) — integration context (for an AI assistant)

> Audience: an AI assistant helping a partner integrate `WirexMobileSDK` on native iOS (Swift / UIKit).
> This file is the working context — read top to bottom; every fact is load-bearing. Dense on purpose:
> no marketing. The human-facing version is `INTEGRATION.html`. For exact backend request/response
> shapes, defer to the Wirex BaaS API reference — this file does not restate them.

---

## 1. Mental model (the one thing to get right)

The SDK owns **sealed UI surfaces** and nothing else. Secrets (a revealed PAN/CVV, a typed card number,
a wallet payment token) live inside a native view or a Wirex-hosted web frame and **never reach app
code**. The SDK **never mints a credential, never stores one**, and (except where noted) **never decides
a money movement**.

The integrator supplies two things:

1. **Authentication** — a `WirexCredentialProvider` the SDK calls on demand (bearer + step-up signature + identity).
2. **Orchestration** — the partner **backend** prices and executes money-moving work (top-up pricing/execution, the 3DS URL, the wallet checkout token) and ships the provider config.

| Surface | Needs credentials? | What it does |
|---|---|---|
| Reveal | yes | show the cardholder their own PAN/expiry/CVV/PIN in sealed native rows |
| Collect | yes | capture an external card in a sealed native form and tokenize it at the acquirer |
| 3-D Secure | **no** | render the issuer challenge for a card payment; report the outcome |
| Wallet | yes | embed the Wirex-hosted Apple Pay / Google Pay checkout |

**One package.** `import WirexMobileSDK` brings all four surfaces — the wallet is a folder inside the
one binary target, not a separate product.

---

## 2. Who integrates, and exactly what they must have

**The integrator is a partner** issuing Wirex-backed cards to their own users.

Wirex assigns (per integration):
- `environment` — card surfaces (Reveal/Collect/3DS) select it with a `testMode: Bool` passed to their factory (`false` = production, `true` = test); wallet resolves a NAME via `WirexWalletEnvironment.resolve(_:)`. Never a URL; the SDK holds the hosts.
- `chainId` — the `X-Chain-Id` on every authenticated call.
- `clientId` — optional, for the hosted pages. Not auth.

Partner owns / must build:
- **A bearer** for the signed-in user → `accessToken()`.
- **A wallet step-up signature** capability (user signs a confirmation message; the backend exchanges it for a short-lived action token) → `actionToken(scope:)`.
- **The identity**: ONE of email or EOA wallet address → `userEmail` / `userWallet`.
- **A provisioned card** (card id) for Reveal/Collect.
- **Backend orchestration** for Wallet/Collect top-ups (price, execute, mint a checkout token, obtain the 3DS URL). Wirex BaaS API — see its reference.
- **Provider config** for Wallet: the wallet provider block from the partner's app config.

---

## 3. Install

Swift Package Manager — the published package carries a binary `.xcframework` that holds all four surfaces:

```swift
// Package.swift (or Xcode → Add Package)
.package(url: "https://github.com/wirexpay/baas-mobile-ios-sdk.git", from: "0.3.7")
// product: "WirexMobileSDK"
```
- iOS 13+. No Apple Pay **app entitlement** is required — wallet Apple Pay runs inside the Wirex web frame (WKWebView), not native PassKit.

---

## 4. Credential provider (the one object the partner implements)

```swift
import WirexMobileSDK

final class AppCredentials: WirexCredentialProvider {
    func accessToken() async throws -> String { /* partner auth → Wirex bearer */ }
    func actionToken(scope: WirexActionScope) async throws -> String { /* .cardData / .pin → action token */ }
    var userEmail: String? { /* return ONE of email / wallet */ }
    var userWallet: String? { /* the EOA address, if identifying by wallet */ }
}
```

Rules the SDK enforces / expects:
- **Exactly one identity.** Returning both `userEmail` and `userWallet` is a backend `400` ("multiple user identifiers"). Return one; the SDK forwards whichever is non-nil.
- **The SDK sends the bearer as-is and does not retry a 401.** `accessToken()` must check expiry and refresh; a stale token reads like "card rejected".
- `actionToken(scope:)` is the user's **wallet signature** over a confirmation action, exchanged by the backend for a short-lived, one-shot token. A user declining throws `WirexDeclined`.
- Read **per call** — a value refreshed mid-session takes effect on the next SDK call.

---

## 5. Surfaces — exact API

### 5.1 Reveal  (needs credentials)
```swift
import WirexMobileSDK

// Factory returns nil for an unknown environment. testMode picks it; chainId is per integration.
guard let reveal = WirexCardReveal.create(
    credentials: credentials, chainId: chainId, testMode: isTestMode) else { return }
let session = try reveal.session(
    cardId: cardId,
    fields: [.cardholderName, .pan, .expiry, .cvv, .pin],   // omit .pin for a virtual card
    cardholderName: cardholderName)

// One WirexRevealFieldView (a UIView) per field, bound to the session; then load fills them.
let panView = WirexRevealFieldView()
panView.bind(session: session, field: .pan)
try await session.load()                                    // observe progress via the session snapshot
```
- The value is drawn in a secure capture-proof layer; on the **iOS Simulator** it renders **blank** (PCI protection, not a bug). `dangerouslyDisableScreenProtection: true` on `create(...)` draws it for simulator development only.

### 5.2 Collect  (needs credentials)
```swift
guard let collect = WirexCardCollect.create(
    credentials: credentials, chainId: chainId, testMode: isTestMode) else { return }
let form = collect.form(profile: .topup)                    // a UIView; reports validity + brand
let token = try await form.tokenizeTopUp(WirexTopUpTokenizeParams(
    billingDetails: WirexBillingDetails(line1: …, zipCode: …, city: …, country: …)))
// token: brand, last4, expiryMonth, expiryYear — opaque; PAN/CVV never reach app code
```
- The **card user must be enrolled at the acquirer**; a non-enrolled user fails tokenization. The **partner backend** then funds the top-up (price → execute, §6).

### 5.3 3-D Secure  (NO credentials)
```swift
let threeDS = WirexCardThreeDS(testMode: isTestMode)        // no credentials
let session = threeDS.session(orchestratorUrl: url)         // url from the top-up execute response
session.onChange = { snapshot in /* snapshot.state: idle | loading | challenge | settled */ }

let view = WirexThreeDSView()                               // full-size
view.bind(session)
session.start()
```
- State: `idle | loading | challenge | settled`; outcome status: `completed | pending | failed | unknown`.
- `pending` = **not settled yet**, not an error. Reconcile the real outcome from the backend status feed.

### 5.4 Wallet  (needs credentials; real device only for the Pay sheet)
```swift
let config = WirexWalletConfig(
    environment: try WirexWalletEnvironment.resolve(environmentName),
    clientId: nil, logging: WirexWalletLogging(level: .info, sink: ConsoleLogSink()), cache: cache)

// availability (whether to show a Pay button):
let checker = WirexWalletAvailabilityChecker(config: config, providerConfig: nil)
checker.onChange = { availability in /* .applePay / .googlePay */ }
checker.start()

// checkout:
let checkout = WirexWalletCheckoutView(
    config: config,
    quote: WirexWalletQuote(estimationId: id, sourceAmount: .init(amount: "10.00", currency: "EUR")),
    providerConfig: try WirexWalletProviderConfig(jsonText: providerBlockJson),   // VERBATIM
    auth: tokenMode ? WirexWalletCheckoutAuth(checkoutToken: token) : nil,
    provider: providerName)
checkout.onEvent = { event in /* ready, naturalHeight, sheetOpen, cancelled, attemptFailed,
    estimationExpired, token (legacy), executing/executed/executeFailed (token mode), failed, diagnostic */ }
// checkout.rearm(quote:providerConfig:auth:provider:) after estimationExpired
```
- **Legacy** (no `auth`): the sheet tokenizes → `.token` event → the backend executes. **Token mode** (`auth`): the frame executes itself → `.executing/.executed/.executeFailed`; nothing reaches app code.
- On the **Simulator** the probe never resolves and the Pay sheet cannot present (no Secure Element); the checkout still arms.

---

## 6. Backend orchestration (what the SDK does NOT do)

The partner backend owns these (Wirex BaaS API, partner credentials). The SDK consumes their results.

- **Price a top-up** → `estimationId` + fiat `sourceAmount`. Short TTL; re-price to re-arm an expired checkout.
- **Execute a top-up** → settles it; a card payment returns a **3DS orchestrator URL** for `WirexCardThreeDS().session(orchestratorUrl:)`.
- **Mint a checkout token** (token mode only) → the `checkoutToken`; scoped to the top-up flow, independent of a specific estimation.
- **Provider config** → the wallet provider block, served from your app config, passed to Wallet verbatim.

`estimationId` and `checkoutToken` are **two independent values** — the id is not derived from the token.

---

## 7. Invariants & gotchas (each a real failure mode)

- **One identity.** email XOR wallet; both → 400.
- **Bearer expiry.** `accessToken()` must refresh; the SDK does not retry 401.
- **`estimationId` ≠ `checkoutToken`.** Independent backend calls.
- **Row sizing.** `WirexRevealFieldView` reports its own natural height; size the host box to it rather than pinning a short fixed height (a too-short box clips the value).
- **Wallet availability needs the checker running.** Start `WirexWalletAvailabilityChecker` with a real provider block; on the Simulator it reports unavailable (the real answer there).
- **Simulator limits.** Reveal/Collect secure layer renders blank; the Pay sheet cannot present. Use a real device.
- **Collect needs an acquirer-enrolled user**, else tokenization fails.
- **3DS `pending` is not an error.** Settle by backend status.
- **`providerConfig` is passed verbatim.** Do not re-case/default/strip; an absent `apple_pay`/`google_pay` key means "do not offer".
- **Unknown environment** throws `WirexEnvironmentUnavailable` — render the reason; never fall back.

---

## 8. The runnable example

This repo is a runnable native example covering all four surfaces. Credentials are entered at
runtime (pasted JSON on the Reveal/Collect screens, or launch arguments for a scripted run) — nothing is
compiled in. The field contract matches the React Native / Android / Flutter examples.

---

## 9. Quick decision rules

- "Which surface needs credentials?" → Reveal, Collect, Wallet yes; 3DS no.
- "Where does the `estimationId` come from?" → the partner backend prices the top-up; the SDK only consumes it. Not from any token.
- "Legacy or token mode for Wallet?" → token mode keeps the sheet payload off the device; legacy returns a token the backend executes. Both need a backend.
- "Why is the Pay button unavailable?" → checker not started, empty provider block, simulator, or no provisioned card.
- "Why is a revealed field blank?" → simulator (secure layer) or the host didn't size the row to its natural height.
- "Why does Collect fail to tokenize?" → the user is not enrolled at the acquirer.
