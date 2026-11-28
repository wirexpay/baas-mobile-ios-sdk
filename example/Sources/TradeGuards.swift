import Foundation
import WirexMobileSDK

/// The Trade tab's own limits, checked before the SDK is asked to sign anything.
enum TradeGuards {
    /// The most a trade on `production` may be worth, in USD. Testers trade small real amounts.
    static let productionCapUSD: Decimal = 10

    // SECURITY: answers why a trade is refused, or nil to let it run. Only `production` moves real money.
    static func refusal(environment: String, usd: Decimal) -> String? {
        guard environment == "production" else { return nil }
        guard usd <= productionCapUSD else {
            return "refused: on production a trade may be worth at most \(productionCapUSD) USD, this one is \(usd) USD"
        }
        return nil
    }

    /// The same check for a value in base units, such as a quote's USDC out at 6 decimals.
    static func refusal(environment: String, units: String, decimals: Int) -> String? {
        guard let usd = value(units: units, decimals: decimals) else { return "refused: the trade's value is not a number" }
        return refusal(environment: environment, usd: usd)
    }

    // SECURITY: a buy is worth its USDC in plus Circle's fee on Arc; a sale is worth its USDC out.
    static func refusal(
        environment: String, side: WirexTradeSide, amountIn: String, inDecimals: Int,
        estimatedOut: String, outDecimals: Int, transferFee: String?
    ) -> String? {
        guard side == .buy else { return refusal(environment: environment, units: estimatedOut, decimals: outDecimals) }
        guard let paid = value(units: amountIn, decimals: inDecimals),
              let fee = value(units: transferFee ?? "0", decimals: inDecimals)
        else { return "refused: the trade's value is not a number" }
        return refusal(environment: environment, usd: paid + fee)
    }

    static func refusal(environment: String, quote: WirexTradeQuote) -> String? {
        refusal(
            environment: environment, side: quote.side, amountIn: quote.amountIn, inDecimals: quote.tokenInDecimals,
            estimatedOut: quote.estimatedAmountOut, outDecimals: quote.tokenOutDecimals, transferFee: quote.transferFee
        )
    }

    static func refusal(environment: String, order: WirexTradeOpenOrder) -> String? {
        refusal(
            environment: environment, side: order.side, amountIn: order.amountIn, inDecimals: order.tokenInDecimals,
            estimatedOut: order.estimatedAmountOut, outDecimals: order.tokenOutDecimals, transferFee: nil
        )
    }

    /// What a send's token counts as in USD: dollar coins at face value, euro coins at 1.25.
    static let sendRates: [String: Decimal] = [
        "USDC": 1, "USDT": 1, "WUSD": 1, "EURC": Decimal(string: "1.25")!, "WEUR": Decimal(string: "1.25")!,
    ]

    // SECURITY: a send's worth meets the cap; on production a token with no rate here is refused.
    static func sendRefusal(environment: String, symbol: String, amount: Decimal) -> String? {
        guard environment == "production" else { return nil }
        guard let rate = sendRates[symbol.uppercased()] else {
            return "refused: on production the tab sends only USDC, USDT, WUSD, EURC or WEUR, not \(symbol)"
        }
        return refusal(environment: environment, usd: amount * rate)
    }

    /// What leaves on a send, the fee included: the unwrap when the quote has one, otherwise the pay token.
    static func leaving(_ quote: WirexSendQuote) -> (token: String, units: String) {
        quote.unwrap.map { ($0.token, $0.units) } ?? (quote.payToken, quote.payUnits)
    }

    // SECURITY: what leaves at Send and Resume, valued by its symbol and decimals from a fresh balances
    // read. `paying` is nil when that read has no row for the token, which is refused.
    static func sendRefusal(environment: String, units: String, paying: (symbol: String, decimals: Int)?) -> String? {
        guard environment == "production" else { return nil }
        guard let paying else { return "refused: the paying token is not among the main account's balances" }
        guard let amount = value(units: units, decimals: paying.decimals) else {
            return "refused: the send's value is not a number"
        }
        return sendRefusal(environment: environment, symbol: paying.symbol, amount: amount)
    }

    static func sendRefusal(environment: String, quote: WirexSendQuote, balances: [WirexCryptoBalance]) -> String? {
        let (token, units) = leaving(quote)
        let row = balances.first { $0.token.lowercased() == token.lowercased() }
        return sendRefusal(environment: environment, units: units, paying: row.map { ($0.symbol, $0.decimals) })
    }

    /// Decimal text as a tester types it, such as `5` or `2.50`. Nil when it is not a positive amount.
    static func usd(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Digits and at most one dot: `Decimal(string:)` alone would read `2.5abc` as 2.5.
        guard trimmed.allSatisfy({ $0.isASCIIDigit || $0 == "." }), trimmed.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: trimmed, locale: posix), value > 0
        else { return nil }
        return value
    }

    /// Base units as decimal text, scaled by `decimals`. Nil for anything but digits.
    static func value(units: String, decimals: Int) -> Decimal? {
        guard !units.isEmpty, units.allSatisfy(\.isASCIIDigit), let raw = Decimal(string: units, locale: posix) else {
            return nil
        }
        var scale = Decimal(1)
        for _ in 0..<max(decimals, 0) { scale *= 10 }
        return raw / scale
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
