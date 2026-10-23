# Wirex Mobile SDK for iOS — Integration Guide

One Swift package, four sealed surfaces: card **Reveal**, card **Collect**, **3-D Secure** and **Wallet** top-up with Apple Pay. This guide covers what each surface needs, where the credentials come from, how to style the views, and how to run the example app. Every snippet below is type-checked against `WirexMobileSDK` 0.3.14.

<!-- badges: Native iOS · Swift · UIKit | WirexMobileSDK 0.3.14 · Swift Package / CocoaPods | Reveal · Collect · 3-D Secure · Wallet -->

## 1. What the SDK does

The SDK owns **sealed UI surfaces** and nothing else. A revealed card number, a card the user is typing and a wallet payment token live inside a native view or a Wirex-hosted web frame and **never reach your app code**. The SDK never mints a credential, never stores one, and never moves money on its own.

Your app supplies two things:

- **Authentication.** A `WirexCredentialProvider` the SDK calls on demand: the user's bearer, a step-up action token when card data or PIN is read, and the user's identity.
- **Orchestration.** Your backend prices and executes money-moving calls through the Wirex BaaS API (top-up estimate and execute, the 3-D Secure URL, the wallet checkout token) and ships the wallet provider config. The SDK renders the result and reports events back.

| Surface | Credentials | What it does |
|---|---|---|
| Reveal | yes | Shows the cardholder their own PAN, expiry, CVV and PIN in sealed native rows. |
| Collect | yes | Captures an external card in a sealed native form and tokenizes it at the acquirer. |
| 3-D Secure | **no** | Renders the issuer challenge for a card payment and reports the outcome. |
| Wallet | yes | Embeds the Wirex-hosted Apple Pay checkout for a backend-priced top-up. |

:::diagram model Apple Pay

## 2. Requirements and install

- **iOS 15 or later.** The framework's deployment target is iOS 15.
- **Xcode 26.5 or later.** The binary ships a `.swiftinterface`; it can be read by the compiler that built it or a newer one.
- Swift Package Manager or CocoaPods. Both install the same `WirexMobileSDK.xcframework`, verified by checksum.

```swift
// Package.swift (or Xcode → File → Add Package Dependencies…)
.package(url: "https://github.com/wirexpay/baas-mobile-ios-sdk.git", from: "0.3.14")
// then add the product "WirexMobileSDK" to your app target
```

```ruby
# Podfile
pod 'WirexMobileSDK', '~> 0.3.14'
```

Wirex assigns these values per integration. Everything else is your user's data.

| Value | What it is | Where it goes |
|---|---|---|
| `testMode` | `false` = production, `true` = the Wirex test environment. The SDK holds the hosts; no public API takes a URL. | `WirexReveal.create`, `WirexCollect.create`, `WirexThreeDS(testMode:)`; the wallet takes the same choice by name: `WirexWalletEnvironment.resolve("test")` or `"production"`. |
| `chainId` | The chain your integration operates on, sent as `X-Chain-Id` on every authenticated call. Required for Reveal and Collect. | `chainId:` on `create(...)`. |
| `clientId` | **Optional, wallet only.** A partner id that selects your branding and configuration on the Wirex-hosted checkout pages. Wirex tells you if you have one; most integrations do not. It is not a credential and grants nothing. | `WirexWalletConfig(clientId:)`; leave `nil` unless Wirex gave you one. |

## 3. Credential provider

One object you implement. The SDK calls it when it needs a token, so you never push tokens in advance.

```swift
import WirexMobileSDK

final class AppCredentials: WirexCredentialProvider {
    var userEmail: String? { "user@example.com" }   // return ONE of email / wallet address
    var userWallet: String? { nil }

    func accessToken() async throws -> String {
        "<bearer for the signed-in user, from your backend>"
    }

    func actionToken(scope: WirexActionScope) async throws -> String {
        switch scope {
        case .cardData, .pin:
            // Run your step-up (biometrics, PIN, MFA) and exchange it on your backend.
            return "<short-lived action token>"
        @unknown default:
            throw WirexDeclined()
        }
    }
}
```

- **Exactly one identity.** Return either `userEmail` or `userWallet`. Sending both is a backend `400`.
- **The SDK sends the bearer as-is and does not retry a 401.** Check expiry in `accessToken()` and refresh before returning.
- `actionToken(scope:)` is the step-up for reading card data (`.cardData`) or the PIN (`.pin`). If the user backs out, throw `WirexDeclined()`; the SDK stops the operation and reports it as declined, not as an error.
- Values are read **per call**, so a refreshed token takes effect on the next SDK request.

## 4. Reveal {creds}

Shows the cardholder their own card details. Each field is a `WirexRevealFieldView` you place in your layout; the SDK draws the value inside it.

```swift
import UIKit
import WirexMobileSDK

final class RevealViewController: UIViewController {
    private let credentials = AppCredentials()
    private var session: WirexRevealSession?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let reveal = WirexReveal.create(credentials: credentials, testMode: true, chainId: "<chain id>") else {
            return   // nil when this build has no endpoints for that environment
        }
        do {
            let session = try reveal.session(cardId: "<card id>", fields: [.pan, .expiry, .cvv, .pin], cardholderName: "JANE DOE")
            self.session = session

            let panRow = WirexRevealFieldView()
            panRow.bind(session: session, field: .pan)
            view.addSubview(panRow)
            panRow.frame = CGRect(x: 16, y: 100, width: view.bounds.width - 32, height: panRow.naturalHeight)

            session.onChange = { snapshot in
                switch snapshot.state {
                case .idle, .loading, .ready: break
                case .error(let error): print(error.code, error.retryable)
                @unknown default: break
                }
            }
            Task { try await session.load() }   // throws only WirexDeclined or CancellationError
        } catch {
            print(error)   // WirexError with reason == .invalidCardId for a malformed card id
        }
    }
}
```

- `fields` are `WirexRevealField` cases: `cardholderName`, `pan`, `expiry`, `cvv`, `pin`. Omit `.pin` for a virtual card.
- `PAN`, `CVV` and `PIN` start **masked**. `panRow.reveal()` unmasks, `panRow.mask()` masks again, `isMasked` reads the state. Rows re-mask when detached (`masksWhenDetached`).
- Session state is `WirexRevealState`: `idle`, `loading`, `ready`, `error(WirexError)`. Per-field results are in `snapshot.loaded`, `snapshot.failed` and `snapshot.outcome(for:)`, so one failed field does not hide the others.
- `load()` is idempotent and reports request failures through the snapshot; it only throws `WirexDeclined` or `CancellationError`.
- `onCopy` fires when the user copies a copyable field; `session.clear()` wipes loaded values.

> **Gotcha · sizing** A row draws its value at its natural height. Size the host box to `naturalHeight` (or let Auto Layout use `intrinsicContentSize`); a box shorter than the content clips the value.

> **Note · simulator** The value is drawn in a secure, capture-proof layer that the iOS Simulator renders blank. That is the PCI protection working. For simulator development only, pass `dangerouslyDisableScreenProtection: true` to `create(...)`. Never ship it on.

## 5. Collect {creds}

Captures a card the user is entering. The form is one `UIView`; your app receives a token, never the PAN or CVV.

:::flow Collect: user types the card | SDK tokenizes at the acquirer | your backend: estimate | execute → 3-D Secure URL

```swift
import UIKit
import WirexMobileSDK

final class CollectViewController: UIViewController {
    private let credentials = AppCredentials()
    private var form: WirexCollectForm?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let collect = WirexCollect.create(credentials: credentials, testMode: true, chainId: "<chain id>") else { return }
        let form = collect.form(profile: .topup)
        self.form = form
        view.addSubview(form)
        form.frame = CGRect(x: 16, y: 100, width: view.bounds.width - 32, height: form.naturalHeight)
        form.onChange = { state in
            print(state.isComplete, state.brand)   // enable your Pay button on isComplete
        }
    }

    func tokenize() {
        guard let form else { return }
        Task { @MainActor in
            do {
                let token = try await form.tokenizeTopUp(WirexTopUpTokenizeParams(
                    billingDetails: WirexBillingDetails(line1: "1 Main St", zipCode: "SW1A 1AA", city: "London", country: "GB"),
                    label: "My card"))
                print(token.cardId, token.brand, token.bin, token.last4, token.expiryMonth, token.expiryYear)
            } catch let error as WirexError {
                print(error.code, error.retryable)
            }
        }
    }
}
```

- Profiles: `.topup` (fund a top-up with this card) and `.octDestination` (register a payout card via `form.tokenizeOctDestination(WirexOctTokenizeParams(cardLabel:isSaved:isThirdParty:))`, which returns `externalCardId`).
- `WirexCollectState` carries `isComplete`, `brand` (`visa`, `mastercard`, `unknown`) and per-field `fields` with `isValid` and `error` (`incomplete`, `invalid`, `expired`).
- Billing details (`line1`, `zipCode`, `city`, `country`) are required by the tokenizer; `line2` and `state` are optional. The **card user must be enrolled at the acquirer**, otherwise tokenization fails.
- After tokenizing, **your backend** prices and executes the top-up with the `cardId`; a card payment may return a 3-D Secure URL for the next section.
- `form.errorLine` controls where validation messages render (`hidden`, `reserved`, `animated`); `form.row(for:)` returns a single sealed row if you lay fields out yourself.

## 6. 3-D Secure {nocreds}

Presents the issuer challenge for a card payment. Your backend obtains the orchestrator URL from the top-up execute response; the SDK renders the flow and reports the outcome. No credentials are needed.

```swift
import UIKit
import WirexMobileSDK

final class ThreeDSViewController: UIViewController {
    private let threeDS = WirexThreeDS(testMode: true)
    private let challengeView = WirexThreeDSView()
    private var session: WirexThreeDSSession?

    func startStepUp(orchestratorUrl: String) {
        view.addSubview(challengeView)
        challengeView.frame = view.bounds
        let session = threeDS.session(orchestratorUrl: orchestratorUrl)
        self.session = session
        session.onChange = { snapshot in
            guard snapshot.state == .settled, let outcome = snapshot.outcome else { return }
            print(outcome.status, outcome.error?.code as Any)   // completed · pending · failed · unknown
        }
        challengeView.bind(session)
        session.start()
    }

    func cancel() {
        session?.cancel()
        challengeView.unbind()
    }
}
```

| State (`WirexThreeDSState`) | Outcome status (`WirexThreeDSStatus`) | Outcome error code |
|---|---|---|
| `idle` · `loading` · `challenge` · `settled` | `completed` · `pending` · `failed` · `unknown` | `originRefused` · `declined` · `unavailable` |

> **Note** `pending` means the payment is not settled *yet*; it is not an error. Reconcile the real result from your backend's status feed, not from the 3-D Secure status alone.

## 7. Wallet · Apple Pay {creds|device}

Embeds the Wirex-hosted checkout for a top-up your backend has already priced. The frame renders the quote and the Apple Pay button; the Pay sheet is native. No Apple Pay entitlement or merchant identifier is needed in your app: the sheet is presented by the Wirex frame.

Three inputs, all from your backend and your app config:

| Input | What it is |
|---|---|
| `quote` | `estimationId` + `sourceAmount` from your backend's top-up estimate. Short TTL; a new estimate re-arms the checkout. |
| `providerConfig` | The wallet provider block from your app config, passed **verbatim** (`WirexWalletProviderConfig(jsonText:)`). |
| `auth` | Token mode: a `checkoutToken` your backend minted for this top-up flow. Omit it for legacy mode. |

:::diagram wallet

```swift
import UIKit
import WirexMobileSDK

final class WalletViewController: UIViewController {
    private var config: WirexWalletConfig?
    private var checker: WirexWalletAvailabilityChecker?
    private var checkout: WirexWalletCheckoutView?

    override func viewDidLoad() {
        super.viewDidLoad()
        do {
            let config = WirexWalletConfig(environment: try WirexWalletEnvironment.resolve("test"))
            self.config = config

            // 1. Availability: decide whether to show a Pay button at all.
            let checker = WirexWalletAvailabilityChecker(config: config, providerConfig: nil)
            checker.onChange = { availability in print(availability.applePay) }
            checker.start()
            self.checker = checker
        } catch { print(error) }
    }

    // 2. Checkout: arm it with a backend-priced quote and the provider block.
    func mount(providerConfigJson: String, checkoutToken: String) throws {
        guard let config else { return }
        let checkout = WirexWalletCheckoutView(
            config: config,
            quote: WirexWalletQuote(estimationId: "<estimation id>", sourceAmount: WirexWalletMoney(amount: "10.00", currency: "EUR")),
            providerConfig: try WirexWalletProviderConfig(jsonText: providerConfigJson),
            auth: WirexWalletCheckoutAuth(checkoutToken: checkoutToken))
        checkout.onEvent = { [weak self] event in self?.handle(event) }
        view.addSubview(checkout)
        self.checkout = checkout
    }

    func handle(_ event: WirexWalletCheckoutEvent) {
        switch event {
        case .ready: break
        case .naturalHeight(let height): checkout?.frame.size.height = height
        case .sheetOpen, .cancelled, .executing: break
        case .attemptFailed(let reason): print(reason)
        case .estimationExpired: break                       // re-price on your backend, then rearm(...)
        case .token(let token): print(token.walletPaymentToken) // legacy mode: your backend executes
        case .executed(let result): print(result.id, result.status)
        case .executeFailed(let error): print(error.reason)
        case .failed(let error): print(error.kind)
        case .diagnostic, .debug: break
        @unknown default: break
        }
    }

    func newQuote(_ quote: WirexWalletQuote, providerConfig: WirexWalletProviderConfig, checkoutToken: String) {
        checkout?.rearm(quote: quote, providerConfig: providerConfig, auth: WirexWalletCheckoutAuth(checkoutToken: checkoutToken))
    }

    deinit { checker?.stop() }
}
```

- **Legacy vs token mode.** Without `auth`, the sheet tokenizes and the checkout emits `.token`; your backend executes the top-up with it. With a backend-minted `checkoutToken`, the frame executes itself and emits `.executing` → `.executed` or `.executeFailed`; nothing sensitive reaches app code.
- `estimationId` and `checkoutToken` are two independent values from two backend calls; the id is not derived from the token.
- Events: `ready`, `naturalHeight(Double)`, `sheetOpen`, `cancelled`, `attemptFailed(reason:)`, `estimationExpired`, `token(WirexWalletPaymentToken)`, `executing`, `executed(WirexWalletExecuteResult)`, `executeFailed(WirexWalletExecuteError)`, `failed(WirexWalletError)`, `diagnostic(WirexWalletDiagnostic)`, `debug(level:message:)`.
- `WirexWalletMoney.amount` is a decimal **string** (`"10.00"`). `WirexWalletQuote` also accepts optional `destinationAmount`, `fee`, `rate` and `expiresAtMs`.
- `providerConfig` is passed verbatim. Do not re-case keys or add defaults; an absent `apple_pay` key means "do not offer Apple Pay".
- `WirexWalletConfig(cache:)` takes an optional key-value store (`WirexWalletAvailabilityCache`) so the availability answer survives relaunch. The SDK writes one key with two booleans.

> **Gotcha · availability** Start a `WirexWalletAvailabilityChecker` with the real provider block before you show a Pay button; `onChange` reports the native `canMakePayments` answer. On the Simulator it reports unavailable, and the Pay sheet cannot present (no Secure Element). Test on a device with a provisioned card.

## 8. Appearance, strings and sizing

Every surface takes an appearance object and a strings object. The SDK ships no copy, so your app supplies every word the views draw.

```swift
import UIKit
import WirexMobileSDK

func styled(reveal: WirexReveal, session: WirexRevealSession) -> WirexRevealFieldView {
    let appearance = WirexAppearance(mode: .dark, colorTextOverride: .white, colorFocusOverride: .systemBlue,
                                     fontFamily: "Inter", fontSizeBase: 17, borderRadius: 12)
    let strings = WirexRevealStrings(fieldLabels: [.pan: "Card number", .cvv: "CVV"],
                                     maskedPlaceholder: "••••", maskedSegmentGlyph: "*", copy: "Copy", copied: "Copied")
    let row = WirexRevealFieldView(session: session, field: .pan, appearance: appearance, strings: strings)
    return row
}

func walletStyle() -> (WirexWalletAppearance, WirexWalletBranding, WirexWalletButtons) {
    (WirexWalletAppearance(theme: .dark, variables: ["--wx-accent": "#0057FF"]),
     WirexWalletBranding(logo: .hidden, processingDisclosurePartnerName: "Acme"),
     WirexWalletButtons(applePay: .init(style: .black, type: .topUp)))
}
```

- `WirexAppearance` is a memberwise struct with every parameter defaulted: `mode` (`.light` / `.dark`), colour overrides (`colorTextOverride`, `colorLabelOverride`, `colorPlaceholderOverride`, `colorErrorOverride`, `colorFocusOverride`, `colorBackgroundOverride`, `colorBorderOverride`, `surfaceColorOverride`), typography (`fontFamily`, `fontSizeBase`, `fontSizeLabel`, `lineHeightBase`, `lineHeightLabel`, `fontWeightBase`, `fontWeightLabel`), geometry (`borderRadius`, `borderWidth`, `spacingUnit`, `paddingHorizontal`, `paddingVertical`, `spacingLabel`, `spacingError`, `iconSize`, `controlMinHeight`). The same object styles Reveal, Collect and 3-D Secure; `setAppearance(_:)` / `apply(appearance:)` restyle a live view.
- Strings: `WirexRevealStrings` (field labels, `maskedPlaceholder` for plain fields, `maskedSegmentGlyph` drawn in every PIN cell while masked, default `*`, copy texts), `WirexCollectStrings` (labels, placeholders, an `error` closure per field and a `brandName` closure) and `WirexThreeDSStrings(title:close:loading:)`. Icons: `WirexRevealIcons(copy:copied:)`, `WirexCollectIcons(visa:mastercard:)`, `WirexThreeDSIcons(close:)`.
- Wallet: `WirexWalletAppearance(theme:variables:)` passes CSS variables to the frame; `WirexWalletBranding(logo:processingDisclosurePartnerName:privacyUrl:)`; `WirexWalletButtons` sets the Apple Pay button `style` (`black`, `white`, `whiteOutline`) and `type` (`plain`, `topUp`, `buy`).
- **Sizing.** `WirexRevealFieldView.naturalHeight`, `WirexCollectForm.naturalHeight` and the wallet's `.naturalHeight` event report the content height. Apply it instead of hardcoding a row height.

## 9. Logging, timeouts and errors

```swift
import WirexMobileSDK

final class ConsoleLogSink: WirexLogSink {
    func write(level: WirexLogLevel, event: String, fields: [String: String]) { print(level, event, fields) }
}

final class ConsoleWalletLogSink: WirexWalletLogSink {
    func write(level: WirexWalletLogLevel, event: String, fields: [String: String]) { print(level, event, fields) }
}

func configured(credentials: AppCredentials) -> WirexReveal? {
    WirexReveal.create(
        credentials: credentials, chainId: "<chain id>",
        logging: WirexLogging(level: .info, sink: ConsoleLogSink()),   // or .disabled, .debug, osLogLogging(level:)
        timeouts: WirexTimeouts(requestSeconds: 20, resourceSeconds: 60))
}

func describe(_ error: Error) {
    if let e = error as? WirexError {
        print(e.code, e.retryable, e.reason as Any, e.detail.apiCode as Any)
    } else if let e = error as? WirexEnvironmentUnavailable {
        print(e)   // unknownName · notBuilt · malformedEndpoints · missingChainId
    } else if error is WirexDeclined {
        print("user declined the step-up")
    }
}
```

- Logging is off by default. The card surfaces take `WirexLogging(level:sink:)`; the wallet takes a separate `WirexWalletLogging(level:sink:)` with its own `WirexWalletLogSink` protocol. Every logged value passes a redactor; tokens and card data are never handed to a sink.
- `WirexError.code`: `unauthorized`, `actionRequired`, `updateRequired`, `invalidInput`, `temporary`, `failed`. `retryable` says whether a retry can help. `reason` adds detail where the backend gives one: `actionTokenRejected`, `cardAlreadyLinked`, `cardLimitReached`, `invalidCardId`.
- `WirexEnvironmentUnavailable` is thrown by `WirexEnvironment.resolve(_:chainId:)` and `WirexWalletEnvironment.resolve(_:)` for an unknown name or an empty `chainId`; the `create(...)` factories return `nil` instead. Show the reason; never fall back to another environment.
- `WirexDeclined` is not an error state: the user said no, and nothing was sent.

## 10. Your backend

The SDK makes none of these calls. Your backend performs them with the partner credentials Wirex issued, and the app passes the results in:

- **Price a top-up** → `estimationId` and `sourceAmount` for the wallet quote. Short TTL; re-price to re-arm an expired checkout.
- **Execute a top-up** → settles it; a card payment returns the 3-D Secure orchestrator URL.
- **Mint a checkout token** (wallet token mode) → `checkoutToken`, scoped to the top-up flow.
- **Serve the wallet provider config** → the provider block the app passes to the wallet verbatim.

Authenticated calls carry `Authorization: Bearer`, `X-Chain-Id` and one identity header (`X-User-Email` or `X-User-Wallet`, never both). For exact paths and payloads see the Wirex BaaS API reference provided with your integration.

## 11. The example app

[`example/`](example/) is a UIKit app that exercises all four surfaces against your own data; nothing is compiled in. Generate the project with `xcodegen generate` (the `project.yml` resolves `WirexMobileSDK` from this repository) and open `WirexMobileSdkExample.xcodeproj`. The **Config** tab is a per-field editor for the environment, the integration parameters (chain id, identity, card id, cardholder name) and the secrets (bearer, step-up action token); values live in memory only, and every screen reads them live. The **Wallet** screen takes an estimation id and the provider block, and its **Fetch estimate** button prices a top-up through the BaaS API with your bearer, so you can get a real estimation id without standing up a backend. The **Appearance** tab restyles every sealed surface at once. The field list is in [`PARTNER-CONFIG.md`](PARTNER-CONFIG.md). Reveal values render blank on the Simulator and the Pay sheet needs a real device.

## 12. Patterns from a production integration

The SDK ships inside a production cardholder app built on the same BaaS API. The patterns below are not required by the API; they are what that integration settled on, with the app-specific parts removed.

### Credentials in practice

```swift
import Foundation
import WirexMobileSDK

protocol AuthSession: AnyObject {
    func accessToken() async -> (token: String, expiresAt: Date)?
    func refreshAccessToken() async -> String?
    func signAction(_ scope: WirexActionScope) async throws -> String
    var userEmail: String? { get }
}

final class ProductionCredentials: WirexCredentialProvider, @unchecked Sendable {
    private let auth: AuthSession
    private var offered: (scope: WirexActionScope, token: String)?
    init(auth: AuthSession) { self.auth = auth }

    /// Sign BEFORE the sheet opens and hand the token over one-shot: the user confirms once.
    func offerStepUpToken(_ scope: WirexActionScope, _ token: String) { offered = (scope, token) }
    func revokeOfferedStepUpToken() { offered = nil }

    func accessToken() async throws -> String {
        // Expiry, not just presence: the SDK sends what it is given and never retries a 401.
        if let current = await auth.accessToken(), current.expiresAt.timeIntervalSinceNow > 30 { return current.token }
        if let refreshed = await auth.refreshAccessToken() { return refreshed }
        throw WirexError(code: .unauthorized, retryable: false)
    }

    func actionToken(scope: WirexActionScope) async throws -> String {
        if let offered, offered.scope == scope { self.offered = nil; return offered.token }
        return try await auth.signAction(scope)                   // fallback: sign now
    }

    var userEmail: String? { auth.userEmail }
    var userWallet: String? { nil }
}
```

- **Check the bearer's expiry, not just its presence.** Your own API client probably refreshes on a 401 and retries; the SDK does neither. Use the same expiry buffer your client uses so the two agree on "about to expire", refresh before returning, and only fall back to a still-valid token when the refresh fails.
- **Sign once.** The user confirms a card reveal with a step-up *before* the sheet opens. Mint the action token there, offer it to the provider one-shot, and revoke it if the flow is abandoned. Otherwise the SDK asks for a second confirmation for the same action.
- **Configure once per process**, cached behind a promise or a flag, and clear the cache on failure so a later attempt can retry. Derive `testMode` from your *runtime* environment if your app can switch backends. Log at `debug` in development builds and `warn` in release.
- **Tokens and identity are read per call**, so a sign-out and sign-in is picked up automatically; keep the provider reading live state rather than a captured copy.

### Reveal in practice

- **One session per open sheet, destroyed with it.** The session holds the retrieved values natively; leaving one alive after the sheet closes keeps a PAN in memory for nothing.
- **Unmask immediately when the user already confirmed.** After the step-up signature, call `reveal()` on the rows right after `load()` instead of asking for another tap.
- **Log which fields failed together with the snapshot's error code.** The row shows only *that* a field failed, never why.

### Collect in practice

```swift
import UIKit
import WirexMobileSDK

/// The sealed form plus your own billing-address and card-label fields; submit only when both are ready.
final class NewCardViewController: UIViewController {
    private var form: WirexCollectForm?
    var billing: WirexBillingDetails?                      // filled by your own address screen
    private var isComplete = false

    func mount(_ collect: WirexCollect) {
        let form = collect.form(profile: .topup)
        form.onChange = { [weak self] state in
            self?.isComplete = state.isComplete
            self?.navigationItem.rightBarButtonItem?.isEnabled = self?.canSubmit ?? false
        }
        view.addSubview(form)
        self.form = form
    }

    private var canSubmit: Bool { isComplete && billing != nil }

    @MainActor
    func submit() async throws -> String {
        guard let form, let billing else { throw WirexError(code: .invalidInput, retryable: false) }
        return try await form.tokenizeTopUp(WirexTopUpTokenizeParams(billingDetails: billing)).cardId
    }

    deinit { form?.clear() }
}
```

- The sealed rows replace only the card inputs. Keep your own billing-address entry and card label, enable submit on `isComplete` **and** a complete address, and release the form when the screen goes away.

### 3-D Secure in practice

```swift
import WirexMobileSDK

/// Settle exactly once, and tell the three endings apart.
final class StepUpWatcher {
    private var settled = false

    func watch(_ session: WirexThreeDSSession,
               onError: @escaping (String) -> Void,
               onDismissed: @escaping () -> Void,
               onComplete: @escaping (WirexThreeDSStatus) -> Void,
               onChallengeVisible: @escaping (Bool) -> Void) {
        session.onChange = { [weak self] snapshot in
            guard let self else { return }
            onChallengeVisible(snapshot.isChallengeVisible)          // hide your own header while true
            guard snapshot.state == .settled, let outcome = snapshot.outcome, !self.settled else { return }
            self.settled = true
            if let error = outcome.error { onError(error.message ?? error.code.rawValue); return }   // show it
            if outcome.status == .unknown { onDismissed(); return }   // the user closed it: reconcile by backend status
            onComplete(outcome.status)                                // completed · pending · failed
        }
    }
}
```

- Start the session only after the view is mounted; a challenge can appear within a frame of the page asking for one.
- Three endings, not interchangeable: an outcome with an `error` is shown; `unknown` *without* an error means the user closed the challenge, which is a decision, not a failure, and the payment may still complete; anything else is a real status. Reconcile the first two against your backend.

### Wallet top-up in practice

```swift
import WirexMobileSDK

final class WalletArming {
    var checkout: WirexWalletCheckoutView?

    /// One token per armed quote. A failed mint is not fatal in-app: run legacy mode instead.
    func auth(mint: () async throws -> String) async -> WirexWalletCheckoutAuth? {
        guard let token = try? await mint() else { return nil }
        return WirexWalletCheckoutAuth(checkoutToken: token)
    }

    /// An expired estimate is re-priced on your backend, then the same view is re-armed (minting again in token mode).
    func handle(_ event: WirexWalletCheckoutEvent,
                reprice: @escaping () async -> (WirexWalletQuote, WirexWalletProviderConfig, WirexWalletCheckoutAuth?)) {
        guard case .estimationExpired = event else { return }
        Task { @MainActor in
            let (quote, providerConfig, auth) = await reprice()
            self.checkout?.rearm(quote: quote, providerConfig: providerConfig, auth: auth)
        }
    }
}
```

- **One `checkoutToken` per armed quote.** Mint it on your backend for the quote you are about to arm; a re-arm mints again. Never hand the user's session bearer to the frame.
- **A failed mint is not fatal in-app.** Run legacy mode instead: the frame tokenizes and your backend executes. Keep `debug` off outside development builds.

## 13. Troubleshooting

- **A revealed field is blank.** Simulator (secure layer), or the row was given a height smaller than `naturalHeight`.
- **`create(...)` returns `nil`.** This build has no endpoints for that side, or `chainId` is empty. Call `WirexEnvironment.resolve(_:chainId:)` to get the reason.
- **Reveal or Collect fails with `unauthorized`.** The bearer is stale; `accessToken()` must refresh. The SDK never retries a 401.
- **Collect cannot tokenize.** The user is not enrolled at the acquirer, or billing details are missing.
- **The Pay button is unavailable.** The checker was not started, the provider block is empty, or you are on the Simulator.
- **3-D Secure ends in `pending`.** Not an error. Settle by your backend's status.
- **Both `userEmail` and `userWallet` are set.** The backend answers `400`. Return exactly one.
