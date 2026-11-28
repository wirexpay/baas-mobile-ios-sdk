import Foundation
import WirexMobileSDK

/// The login is the SDK's bearer source as it stands: a pasted bearer, or the key's own login.
extension TradeLogin: WirexTradeTokenProvider {}

/// One `WirexTrade` and one `WirexCrypto`, built again when the environment, the chain or the key
/// changes. The company id and the host only change the login, which notices by itself.
final class TradeSession: @unchecked Sendable {
    static let shared = TradeSession()

    enum Failure: Error, CustomStringConvertible {
        case noKey
        case noChain

        var description: String {
            switch self {
            case .noKey: return "set ownerKey on the Config tab or in the launch environment"
            case .noChain: return "set the chain id on the Config tab or in the launch environment"
            }
        }
    }

    private let lock = NSLock()
    private var current: (scope: String, trade: WirexTrade)?
    private var currentCrypto: (scope: String, crypto: WirexCrypto)?

    func trade() throws -> WirexTrade {
        let (signer, chainId, scope) = try inputs()
        return try lock.wirexWithLock {
            if let current, current.scope == scope { return current.trade }
            let trade = try WirexTrade.create(
                testMode: LiveConfig.shared.isTestMode, chainId: chainId, tokenProvider: TradeLogin.shared,
                signer: signer, logging: WirexLogging(level: .info, sink: ConsoleLogSink())
            )
            current = (scope, trade)
            diag.sdk("trade: built for \(LiveConfig.shared.environment) on chain \(chainId)")
            return trade
        }
    }

    /// The Crypto tab's `WirexCrypto`, on the same signer and login as the trade.
    func crypto() throws -> WirexCrypto {
        let (signer, chainId, scope) = try inputs()
        return try lock.wirexWithLock {
            if let currentCrypto, currentCrypto.scope == scope { return currentCrypto.crypto }
            let crypto = try WirexCrypto.create(
                testMode: LiveConfig.shared.isTestMode, chainId: chainId, tokenProvider: TradeLogin.shared,
                signer: signer, logging: WirexLogging(level: .info, sink: ConsoleLogSink())
            )
            currentCrypto = (scope, crypto)
            diag.sdk("crypto: built for \(LiveConfig.shared.environment) on chain \(chainId)")
            return crypto
        }
    }

    /// The key, the chain and the scope a surface is built for. A change to any of them builds it again.
    private func inputs() throws -> (TestOnlySigner, String, String) {
        let config = LiveConfig.shared
        let key = config.credential("ownerKey")
        guard !key.isEmpty else { throw Failure.noKey }
        let chainId = config.credential("chainId")
        guard !chainId.isEmpty else { throw Failure.noChain }
        let signer = try TestOnlySigner(hexKey: key)
        return (signer, chainId, [config.environment, chainId, signer.address].joined(separator: "|"))
    }
}

/// One line per failure, the same on every platform's example: the reason first, then what helps.
enum TradeErrorText {
    static let hints: [WirexTradeError.Reason: String] = [
        .signerMismatch: "the key does not own this account",
        .investmentWalletRequired: "set up the account first",
        .quoteExpired: "get a new quote",
        .insufficientFunds: "the main account cannot cover the buy",
        .orderNotEnded: "the order is still open: resume it from Open orders",
    ]

    /// The Crypto tab's hints, the same text in every app.
    static let cryptoHints: [WirexCryptoError.Reason: String] = [
        .invalidAddress: "the recipient is not an address of that network",
        .recipientIsAccount: "the recipient is the main account itself",
        .insufficientFunds: "the main account cannot cover the send",
        .quoteExpired: "get a new quote",
        .quoteMismatch: "the quote is not this send's",
        .overLimit: "try a smaller amount",
        .amountTooSmall: "try a larger amount",
        .bridgeUnavailable: "the bridge is unavailable: try again later",
        .rhinoKeyMissing: "the company has no rhino.fi key",
        .depositUnavailable: "no deposit network is left: ask again later",
        .signerMismatch: "the key does not own this account",
        .tokenUnavailable: "sign in again",
    ]

    /// `reason · (hint) · step <step> · route <routeReason> / <detailKey> · HTTP <status> · <entryPointCode>`,
    /// each absent part left out. Anything that is neither error shows its own description.
    static func line(_ error: Error) -> String {
        if let error = error as? WirexTradeError {
            return line(
                error.name, hints[error.reason], error.step?.rawValue, error.routeReason, error.detailKey,
                error.httpStatus, error.entryPointCode
            )
        }
        if let error = error as? WirexCryptoError {
            return line(
                error.name, cryptoHints[error.reason], error.step?.rawValue, error.routeReason, error.detailKey,
                error.httpStatus, error.entryPointCode
            )
        }
        return "\(error)"
    }

    private static func line(
        _ name: String, _ hint: String?, _ step: String?, _ routeReason: String?, _ detailKey: String?,
        _ httpStatus: Int?, _ entryPointCode: String?
    ) -> String {
        var parts = [name]
        if let hint { parts.append("(\(hint))") }
        if let step { parts.append("step \(step)") }
        switch (routeReason, detailKey) {
        case let (reason?, key?): parts.append("route \(reason) / \(key)")
        case let (reason?, nil): parts.append("route \(reason)")
        case let (nil, key?): parts.append("route / \(key)")
        case (nil, nil): break
        }
        if let httpStatus { parts.append("HTTP \(httpStatus)") }
        if let entryPointCode { parts.append(entryPointCode) }
        return parts.joined(separator: " · ")
    }
}
