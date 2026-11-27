# Changelog

## Unreleased

- Trade: `WirexTrade` buys and sells US stocks and coins from a main account on Base or Arc, through an investment account on Base. `WirexTrade.create(testMode:chainId:tokenProvider:signer:)` takes the partner's chain, a bearer source (`WirexTradeTokenProvider`) and the host's signer (`WirexTradeSigner`). It has seven members: `account`, `setUpAccount`, `catalog`, `quote`, `execute`, `openOrders` and `resume`.
- Trade: the host app signs. The SDK hands it a 32-byte hash and takes back 65 bytes; no key enters the SDK. Each step reports through `onStep`, and each failure is a `WirexTradeError` with one reason name.
- Trade: nothing is kept between calls. `openOrders` and `resume` read where an order stands, so a trade carries on after the app restarts.
- Example: a **Trade** tab runs a trade end to end. It signs with a test user's key from the launch environment or the Config tab, held in memory only, and logs in with it. It refuses a production trade worth more than 10 USD.

## 0.3.15

- 3-D Secure: the challenge now renders inside a Flutter host. The step-up view no longer moves the box the host owns; a host that re-assigns the box's frame while nothing is showing (Flutter does, every frame) left the challenge off-screen.
- 3-D Secure: `dangerouslyDisableScreenProtection` on `WirexThreeDS`, the same switch Reveal and Collect have. Set, the challenge is not covered while the screen is recorded or mirrored; app-switcher masking still applies. Off by default; never ship a build with it set.

## 0.3.14

- Version aligned with the other mobile SDKs (0.3.14). No iOS code change: iOS already honours `dangerouslyDisableScreenProtection` per field, so the Android reveal fix in this release has no iOS counterpart.

## 0.3.13

Reveal
- A row masked when the app leaves the foreground keeps your reveal request and draws again on return, as long as the session still holds the value. Past the session's 120 s lifetime the row stays masked until you load again.
- A hidden segmented field (PIN) shows the masked placeholder's glyph in every cell instead of empty boxes.
- Deployment floor is iOS 15.
- Reveal: new string `maskedSegmentGlyph`, drawn in every PIN cell while masked (default `*`; pass `•` for dots).

## 0.3.7

- 3-D Secure: presents the card issuer's authentication page a top-up asks for and reports the outcome.
- Wallet top-up: token mode. The checkout can execute the top-up itself and report executing / executed / failed instead of handing back a token. Standalone launch helpers build the checkout URL and parse the return link for hosts that open the checkout in a browser tab; the return link is matched at a path boundary.
- Privacy manifests ship with the iOS artifacts.
- Reveal: a field row pinned shorter than its content clips instead of collapsing.

## 0.3.1

First public release.

- Card reveal: shows a cardholder their own card number, expiry, CVV and PIN inside the host app.
- Card collect: takes a card the user is entering and returns a token.
- Wallet top-up: hosts the Wirex checkout with Apple Pay.
- One environment model for every surface: `production` and `test`, selected with `testMode`.
