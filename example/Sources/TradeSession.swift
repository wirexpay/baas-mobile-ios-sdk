import Foundation
import WirexMobileSDK

/// The login is the SDK's bearer source as it stands: a pasted bearer, or the key's own login.
extension TradeLogin: WirexTradeTokenProvider {}

/// The tab's one `WirexTrade`, built from the config and built again when the environment, the chain
/// or the key changes. The company id and the host only change the login, which notices by itself.
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

    func trade() throws -> WirexTrade {
        let config = LiveConfig.shared
        let key = config.credential("ownerKey")
        guard !key.isEmpty else { throw Failure.noKey }
        let chainId = config.credential("chainId")
        guard !chainId.isEmpty else { throw Failure.noChain }
        let signer = try TestOnlySigner(hexKey: key)
        let scope = [config.environment, chainId, signer.address].joined(separator: "|")
        return try lock.wirexWithLock {
            if let current, current.scope == scope { return current.trade }
            let trade = try WirexTrade.create(
                testMode: config.isTestMode,
                chainId: chainId,
                tokenProvider: TradeLogin.shared,
                signer: signer,
                logging: WirexLogging(level: .info, sink: ConsoleLogSink())
            )
            current = (scope, trade)
            diag.sdk("trade: built for \(config.environment) on chain \(chainId)")
            return trade
        }
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

    /// `reason · (hint) · step <step> · route <routeReason> / <detailKey> · HTTP <status> · <entryPointCode>`,
    /// each absent part left out. Anything that is not a trade error shows its own description.
    static func line(_ error: Error) -> String {
        guard let error = error as? WirexTradeError else { return "\(error)" }
        var parts = [error.name]
        if let hint = hints[error.reason] { parts.append("(\(hint))") }
        if let step = error.step { parts.append("step \(step.rawValue)") }
        switch (error.routeReason, error.detailKey) {
        case let (reason?, key?): parts.append("route \(reason) / \(key)")
        case let (reason?, nil): parts.append("route \(reason)")
        case let (nil, key?): parts.append("route / \(key)")
        case (nil, nil): break
        }
        if let status = error.httpStatus { parts.append("HTTP \(status)") }
        if let code = error.entryPointCode { parts.append(code) }
        return parts.joined(separator: " · ")
    }
}
