# Example configuration — the debug menu

This example is one binary that exercises **every SDK surface** against **any partner's data**. Nothing
is hard-coded: the **Config** tab is a per-field editor for the integration parameters and credentials, and
every screen reads it live. The same field set is the contract for the iOS, Android, React Native and Flutter
examples, so QA enters the same values everywhere; the Wallet screen additionally takes the estimation id and
the provider block, or fetches an estimate with your bearer.

## Fields

### Environment
| Field | What it is |
|---|---|
| `environment` | `test` or `production`. Maps to the SDK's `testMode`; the SDK holds the hosts itself. |

### Integration parameters (non-secret)
| Field | What it is | Who gives it |
|---|---|---|
| `chainId` | `X-Chain-Id` — the chain the partner operates on | **Wirex**, per integration |
| `companyId` | `X-Company-Id` on the login the Trade and Crypto tabs share — the company the test user belongs to | **Wirex**, per integration |
| `clientId` | `?client=` on the hosted pages (optional) | **Wirex** |
| `userEmail` / `userWallet` | identity headers `X-User-Email` / `X-User-Wallet` | partner (the signed-in user) |
| `cardId` | the card Reveal / Collect act on | partner (a provisioned card) |
| `cardholderName` | display name on Collect | partner |
| `walletAmount` / `walletCurrency` / `walletProvider` | the top-up quote the Wallet screens arm with | partner (from an estimate) |
| `baasApiUrl` | the BaaS API host (https, no path). The Trade and Crypto login calls it, and so does the Wallet screen's **Fetch estimate** helper. Pricing is the partner backend's job; the helper only verifies a bearer | **Wirex**, per environment |
| `returnUrl` | Custom Tab App Link — **https, verified for this app's package** (`assetlinks.json`) | partner |

### Secrets (memory only — never persisted, never logged)
| Field | What it is | In production it is |
|---|---|---|
| `bearer` | `getAccessToken` — Wirex bearer for the user | minted by the partner's auth |
| `actionToken` | `getActionToken` — step-up for card data / PIN | the user's **wallet signature**, exchanged by the partner's backend |
| `checkoutToken` | token mode — the short-lived top-up token | minted by the **partner's backend** |
| `ownerKey` | **TESTING ONLY.** The test user's exported private key. It signs the login and each trade and send step on the Trade and Crypto tabs. A pasted `bearer` wins over the login | the user's **own wallet**, which signs; a real app never holds a key |

### Where the values come from

The four fields the Trade and Crypto tabs share are `environment`, `chainId`, `companyId` and `ownerKey`. A higher source wins over a lower one.

| Order | Source | Notes |
|---|---|---|
| 1, highest | The env or a local file, in a debug build only | The Config tab shows these fields read-only |
| 2 | The **Config** tab | `ownerKey` stays in memory only |
| 3 | A `wirexqa://seed` link | Never carries `ownerKey`: a link that does is refused whole |

The env or file source per platform:

| Platform | Source |
|---|---|
| iOS | The launch environment, from the Xcode scheme or `SIMCTL_CHILD_*`: `WIREX_ENVIRONMENT`, `WIREX_CHAIN_ID`, `WIREX_COMPANY_ID`, `WIREX_OWNER_KEY` and `WIREX_BAAS_API_URL`. `example/tools/run-trade.sh` passes them from the gitignored `example/trade.local.env` |
| Android | Intent extras, through `adb shell am start -e` |
| React Native and Flutter | A gitignored `e2e.local.json`, read only in debug builds |
| Web | `.env.local` |

CI checkouts never have the file, so no distributed build carries a key.

### Dev options
| Toggle | What it does |
|---|---|
| `Disable screen protection` | **DEV ONLY**: draws the revealed PAN/CVV on the iOS **Simulator** (the SDK's secure capture layer renders blank there). **Off by default** — leave off on a real device and in any shippable build; on it defeats PCI screen-capture protection. |

## What each surface needs

| Surface | What to enter |
|---|---|
| **Reveal** (PAN/CVV/expiry/PIN) | environment, chainId, bearer, actionToken, cardId |
| **Collect** (tokenize a card) | environment, chainId, bearer |
| **3DS step-up** | environment; a top-up orchestrator URL (the 3DS screen takes it directly — the SDK makes no call and needs no credentials) |
| **Wallet — Apple Pay / Google Pay** | environment, chainId, bearer, walletProvider, walletAmount/Currency; paste the estimation id + provider config on the Wallet screen |
| **Wallet — token mode** | the above + a `checkoutToken` your backend minted |
| **Trade** (stocks and coins) | environment, chainId, ownerKey; and companyId with baasApiUrl for the login, or a pasted bearer. A full trade runs only on `production`, where the tab refuses a trade worth more than 10 USD |
| **Crypto** (sends and deposit addresses) | the same as Trade. On `production` the tab refuses a send worth more than 10 USD, the fee included. USDC, USDT and WUSD count at face value, EURC and WEUR at 1.25 USD, and no other token is sent |

## Credentials in a real integration

The example lets QA **paste** `bearer` and `actionToken` so a device needs no backend or wallet. A real
partner implements the credential provider instead:

- `getAccessToken()` → a bearer from the partner's auth against Wirex BaaS.
- `getActionToken(scope)` → the **user's wallet signature** over the confirmation action (`cardData`, `pin`).
- `userEmail` / `userWallet` → the identity headers.

`WirexThreeDS.configure({ testMode })` takes **no** credentials: the host authenticates to obtain the
orchestrator URL and hands it over.
