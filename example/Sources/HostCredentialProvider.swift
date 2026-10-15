import Foundation
import UIKit
import WirexMobileSDK

/// Non-secret launch arguments, so the example can be driven by a script.
///
/// Credentials and identity are NOT passed here: a bearer, token or card id in a process's argument
/// vector is visible in `ps` and in crash logs. They are entered in the app instead (the
/// "credentials" box). What remains on the command line is a 3DS URL to seed and which tab to open —
/// neither is a secret.
enum LaunchArgs {
    private static func value(_ flag: String) -> String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return "" }
        return arguments[index + 1]
    }

    /// The orchestrator address a real host would read from `three_ds_state.url`. Seeded from a launch
    /// argument; editable on screen, since each step-up mints a new URL. Not a secret.
    static var threeDsUrl: String { value("-wirexThreeDsUrl") }
    /// Which tab to open on. `collect` or nothing.
    static var screen: String { value("-wirexScreen") }
}

/// What a partner application has to implement.
///
/// This is the entire integration contract for authentication: the SDK never manages a user session,
/// so it asks the host for a token whenever it needs one. A real app returns the token it already
/// holds and runs whatever action-token it uses — Face ID, a PIN sheet, an MFA prompt.
///
/// Two things worth copying:
///
///  - `actionToken(scope:)` is called once per SCOPE per reveal, not per HTTP request. PAN + expiry
///    + CVV asks once; adding PIN asks again.
///  - A user declining is signalled by throwing `WirexDeclined`. The session then
///    abandons the whole reveal instead of prompting again for the remaining fields.
///
/// What this deliberately does NOT show is how to obtain a token. That is the host's flow against
/// the host's backend, and an example that picked one would be teaching a choice the SDK does not
/// make.
final class HostCredentialProvider: WirexCredentialProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _declineNextActionToken = false

    // Must match the token's user: the backend receives these as `X-User-Email` / `X-User-Wallet`
    // alongside the bearer, so a mismatch fails for a reason unrelated to the token.
    // Read through LiveConfig, so a value pasted into the app takes effect without a rebuild.
    var userEmail: String? { LiveConfig.shared.credential("email").isEmpty ? nil : LiveConfig.shared.credential("email") }
    var userWallet: String? { LiveConfig.shared.credential("wallet").isEmpty ? nil : LiveConfig.shared.credential("wallet") }

    /// Set from the UI to exercise the decline path.
    var declineNextActionToken: Bool {
        get { lock.wirexWithLock { _declineNextActionToken } }
        set { lock.wirexWithLock { _declineNextActionToken = newValue } }
    }

    func accessToken() async throws -> String { LiveConfig.shared.credential("bearer") }

    func actionToken(scope: WirexActionScope) async throws -> String {
        if declineNextActionToken {
            declineNextActionToken = false
            throw WirexDeclined()
        }
        // `scope` distinguishes the PIN so a stronger prompt could be demanded; the backend has one
        // `GetCardDetails` action type today, so both scopes mint the same way.
        _ = scope

        // The token the host holds. A real application returns whatever its own flow produced; this
        // one returns what was pasted or passed at launch.
        let supplied = LiveConfig.shared.credential("actionToken")
        guard !supplied.isEmpty else {
            // No token, reported as the SDK's "the user must do something" rather than as a crash.
            // A host whose flow failed reports the same thing.
            throw WirexError(code: .actionRequired, retryable: true)
        }
        return supplied
    }
}
