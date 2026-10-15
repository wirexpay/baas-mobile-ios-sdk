import Foundation

/// The SDK environment this example talks to.
///
/// A name, never a URL — the SDK maps it onto the hosts it holds. Set it to the environment Wirex
/// assigned to your integration (`test` or `production`). The card surfaces resolve it through
/// `WirexEnvironment.resolve(_:)` and the wallet surface through `WirexWalletEnvironment.resolve(_:)`.
enum WirexSdkConfig {
    static let environment = "test"
}
