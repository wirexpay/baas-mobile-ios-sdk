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
- integration parameters — chain id, company id, user email, user wallet, card id, cardholder name,
  the BaaS API host;
- secrets (bearer, step-up action token, the `ownerKey` the Trade and Crypto tabs sign with), held in
  memory only and never
  persisted or logged.

Credentials are never passed on the command line — a bearer in a process's argument vector is visible
in `ps` and in logs. The one exception is the launch environment of the Trade and Crypto tabs, below.

## The surfaces

| Tab | What it shows |
|---|---|
| **Config** | a per-field editor for the environment, integration parameters and secrets, shared by every surface |
| **Reveal** | the cardholder's own PAN / expiry / CVV / PIN in sealed native rows |
| **Collect** | a sealed form that tokenizes an external funding card at the acquirer |
| **3DS** | paste a top-up orchestrator URL → the issuer challenge, and the outcome |
| **Wallet** | an availability probe + the hosted Apple Pay / Google Pay checkout (paste a provider block, build a quote; token mode via a checkout token) |
| **Trade** | a stock or coin trade end to end: Account, Catalog, Quote, Trade and Open orders, signed with a test user's key |
| **Crypto** | a send to any network and deposit addresses: Balances, Send, Pending and Deposit, signed with the same key |
| **Appearance** | restyle every sealed surface at once — presets or a pasted token document |

The field contract is the same across the React Native / Android / Flutter examples — see
`../PARTNER-CONFIG.md`.

> A revealed value is drawn in a capture-proof layer that the **iOS Simulator renders blank** — that is
> PCI protection, not a bug. The Apple Pay sheet likewise cannot present on the Simulator; the checkout
> still arms, only the sheet needs a real device.

## The Trade tab

The tab runs a real trade. On `production` it moves real money, so it refuses any trade worth more
than 10 USD: on the typed buy amount, on the quote, again at **Execute**, and on an open order before
**Resume**. On `test`, the catalog and quotes work, but the set-up and trades cannot run.

It signs with a test user's exported key, `ownerKey`. The key stays in memory, and the
`TestOnlySigner.swift` file that uses it is for testing only. The tab gets its bearer by logging in
with the key, through `POST /api/v1/user/authorize`; a pasted `bearer` wins over the login.

## The Crypto tab

The tab sends from the main account, on its own chain or to another network, and gets deposit
addresses. It signs and logs in as the Trade tab does, with the same `ownerKey`.

- **Balances:** `Read balances` lists the main account's tokens.
- **Send:** a network, a token, a recipient, an amount and an optional provider, then `Get quote`. The
  quote shows the rail, the fee and what arrives. `Send` runs it with a steps table. `Check delivery`
  shows for a send to another network, never for a transfer on the account's own chain.
- **Pending:** `Load pending` lists the requests that have not run or expired. A row's `Resume` runs
  only when this run of the app still holds the quote that made it, matched by its hash. Quotes live
  in memory only, so a row from an earlier run shows "no quote held for this send".
- **Deposit:** a family, then `Get deposit address`, which shows the address, its networks, and each
  token's minimum and maximum in USD.

On `production` the tab refuses a send worth more than 10 USD. It checks the typed amount at
`Get quote`. At `Send` and `Resume` it checks what leaves, the fee included, valued from a fresh
balances read. USDC, USDT and WUSD count at face value, and EURC and WEUR at 1.25 USD. It refuses any
other token, and a paying token missing from the balances.

## Prefill both tabs from the launch environment

A debug build reads these from its launch environment. They win over the Config tab and a seed link,
and the Config tab shows them read-only.

| Variable | Field |
|---|---|
| `WIREX_ENVIRONMENT` | `environment` |
| `WIREX_CHAIN_ID` | `chainId` |
| `WIREX_COMPANY_ID` | `companyId` |
| `WIREX_OWNER_KEY` | `ownerKey` |
| `WIREX_BAAS_API_URL` | `baasApiUrl`, the host only, with no path |

Set them in the Xcode scheme (**Edit Scheme › Run › Environment Variables**), or let the script pass them
as `SIMCTL_CHILD_*` from a gitignored file:

```sh
cp trade.local.env.example trade.local.env   # then put the test user's values in it
tools/run-trade.sh                           # builds, installs and opens the Trade tab
```

The script refuses a file git would track, and prints no value. `SIMCTL_CHILD_*` values are visible to
`ps eww` on the Mac that runs the simulator. That is the one exception to the rule above, and it stays
on the tester's own machine. A seed link never carries `ownerKey`.

## Build against the SDK's source

Until the SDK release with `Trade` and `Crypto` is out, the tabs build against a local checkout of the SDK's
source. `project.sdk-source.yml` points the example at it. Plain `xcodegen generate` keeps the published
package.

```sh
WIREX_SDK_SOURCE=/path/to/baas-ios-sdk/sdk/ios xcodegen generate --spec project.sdk-source.yml
```

A source checkout carries no hosts, so `WirexTrade.create` and `WirexCrypto.create` refuse it with
`notBuilt`. Before a live
run, the tester writes the hosts into that checkout, from its root:

```sh
WIREX_PRODUCTION_API_URL=<the BaaS API, with its /api prefix> \
WIREX_PRODUCTION_CARD_SERVICE_URL=<the card service> \
node tools/inject-endpoints.mjs
```

`create` needs both hosts, although a trade or a send uses only the API. Note that `WIREX_PRODUCTION_API_URL`
takes the `/api` prefix, but the example's `baasApiUrl` takes the host alone. After the run, put the
checkout back:

```sh
node tools/inject-endpoints.mjs --empty
```

## Tests

`xcodebuild test` runs the unit tests in `Tests/`: both tabs' 10 USD caps, the signer, the Crypto
tab's resume match and the error lines. There are no UI tests; a person taps through a trade and a send.
