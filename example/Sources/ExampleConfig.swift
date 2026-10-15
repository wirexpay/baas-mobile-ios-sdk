import Foundation
import WirexMobileSDK

/// The example's runtime configuration — everything a partner (or QA) types into the running build on
/// the Config tab, so one binary exercises every surface without a rebuild.
///
/// TWO tiers, on purpose:
///   - `settings`  — non-secret integration parameters (environment, chainId, clientId, the demo card
///                   id, the wallet quote, the Custom Tab return link). Safe to show and to prefill.
///   - `secrets`   — the bearer, the step-up action token, the wallet checkout token. Held in memory
///                   ONLY, never logged, matching the SDK's own no-persistence promise. They reset when
///                   the process dies; QA re-pastes them.
///
/// Mirrors `exampleConfig.ts` in the React Native example — the same field contract (PARTNER-CONFIG.md),
/// so QA enters the same values on every platform.
enum ExampleEnvironment: String, CaseIterable {
    case test
    case production

    /// `test` everywhere but production.
    var isTestMode: Bool { self != .production }
}

/// The single source the Config screen writes and every surface reads. A class so the credential
/// provider can hold a reference and re-read live; guarded by a lock for the SDK's background calls.
final class ExampleConfigStore: @unchecked Sendable {
    static let shared = ExampleConfigStore()

    /// Posted whenever anything changes, so a screen can reconfigure.
    static let didChange = Notification.Name("ExampleConfigStore.didChange")

    private let lock = NSLock()

    // Non-secret settings.
    private var _environment: ExampleEnvironment = .test
    private var _chainId = ""
    private var _clientId = ""
    private var _userEmail = ""
    private var _userWallet = ""
    private var _cardId = ""
    private var _cardholderName = ""
    private var _walletAmount = "10.00"
    private var _walletCurrency = "EUR"
    private var _walletProvider = ""
    private var _returnUrl = ""

    // Secrets — memory only.
    private var _bearer = ""
    private var _actionToken = ""
    private var _checkoutToken = ""

    private func read<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
    private func write(_ body: () -> Void) {
        lock.lock(); body(); lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }

    var environment: ExampleEnvironment { get { read { _environment } } set { write { _environment = newValue } } }
    var chainId: String { get { read { _chainId } } set { write { _chainId = newValue } } }
    var clientId: String { get { read { _clientId } } set { write { _clientId = newValue } } }
    var userEmail: String { get { read { _userEmail } } set { write { _userEmail = newValue } } }
    var userWallet: String { get { read { _userWallet } } set { write { _userWallet = newValue } } }
    var cardId: String { get { read { _cardId } } set { write { _cardId = newValue } } }
    var cardholderName: String { get { read { _cardholderName } } set { write { _cardholderName = newValue } } }
    var walletAmount: String { get { read { _walletAmount } } set { write { _walletAmount = newValue } } }
    var walletCurrency: String { get { read { _walletCurrency } } set { write { _walletCurrency = newValue } } }
    var walletProvider: String { get { read { _walletProvider } } set { write { _walletProvider = newValue } } }
    var returnUrl: String { get { read { _returnUrl } } set { write { _returnUrl = newValue } } }

    var bearer: String { get { read { _bearer } } set { write { _bearer = newValue } } }
    var actionToken: String { get { read { _actionToken } } set { write { _actionToken = newValue } } }
    var checkoutToken: String { get { read { _checkoutToken } } set { write { _checkoutToken = newValue } } }
}

/// The credential provider the SDK calls. Reads the live store per call, so a bearer or action token
/// typed on the Config tab takes effect on the next reveal without a reconfigure.
///
/// A real integration mints these: `accessToken` from the partner's auth, `actionToken` from the user's
/// wallet signature. The example lets QA paste them so a device needs no backend or wallet.
final class ExampleCredentialProvider: WirexCredentialProvider {
    private let store = ExampleConfigStore.shared

    func accessToken() async throws -> String {
        let token = store.bearer
        if token.isEmpty { throw ExampleError.missing("Set a bearer on the Config tab") }
        return token
    }

    func actionToken(scope: WirexActionScope) async throws -> String {
        let token = store.actionToken
        if token.isEmpty { throw ExampleError.missing("Set a step-up action token on the Config tab") }
        return token
    }

    var userEmail: String? { store.userEmail.isEmpty ? nil : store.userEmail }
    var userWallet: String? { store.userWallet.isEmpty ? nil : store.userWallet }
}

enum ExampleError: LocalizedError {
    case missing(String)
    var errorDescription: String? { if case let .missing(message) = self { return message }; return nil }
}
