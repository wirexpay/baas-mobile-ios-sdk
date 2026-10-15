import CryptoKit
import Foundation
import UIKit
import WirexMobileSDK

/// Everything the example needs at runtime that a rebuild would otherwise be required to change.
///
/// Seeded from launch arguments, then overridden from JSON pasted into the app. **Merge, not
/// replace**: a key absent from the pasted document keeps its previous value, so when one credential
/// expires you paste a document containing only that one. That is the whole reason this exists —
/// `action_token` lives 300 seconds, and rebuilding for each is not a workflow.
///
/// SECURITY: in memory only. Nothing here reaches `UserDefaults`, a file, or the keychain — the SDK
/// makes that promise about card values and an example that persisted a bearer would be teaching the
/// opposite. Values die with the process.
/// Why a type rather than `Result<String, String>`: the failure type of `Result` must conform to
/// `Error`, and making `String` conform is a module-wide side effect for one example's convenience.
enum ConfigOutcome {
    case merged(String)
    case rejected(String)
}

final class LiveConfig {
    static let shared = LiveConfig()

    private let lock = NSLock()
    private var credentials: [String: String] = [:]
    /// The example keeps one map per mode and hands over the one that matches.
    private var appearanceTokens: [String: Any] = [:]
    /// The map handed over when dark is showing. Complete on its own — nothing is layered.



    private init() {
        // Credentials and identity are entered in the app (the "credentials" box), never passed on
        // the command line — a bearer in a process's argument vector is visible in `ps` and in crash
        // logs. The map starts empty; paste to fill it.
        credentials = [:]
    }

    // MARK: - Credentials

    func credential(_ key: String) -> String {
        lock.wirexWithLock { credentials[key] ?? "" }
    }

    /// Merges a pasted document. Returns a human-readable summary, or an error to show.
    func applyCredentials(json: String) -> ConfigOutcome {
        guard let parsed = Self.parse(json) else { return .rejected("not valid JSON") }

        let known = ["environment", "bearer", "email", "wallet", "cardId", "chainId", "actionToken", "cardholderName"]
        var applied: [String] = []
        var cleared: [String] = []
        var unknown: [String] = []

        lock.wirexWithLock {
            for (key, value) in parsed {
                guard known.contains(key) else { unknown.append(key); continue }
                guard let text = value as? String else { continue }
                // An EMPTY string clears the key. Merge semantics are "a key you did not mention keeps
                // its value" — an empty string mentions it, so treating that as "not mentioned" left a
                // credential settable but never clearable. That matters most for `actionToken`: while
                // it holds a value the example short-circuits minting, so a stale one freezes every
                // reveal and the only escape was restarting the app.
                if text.isEmpty {
                    credentials.removeValue(forKey: key)
                    cleared.append(key)
                    continue
                }
                credentials[key] = text
                applied.append(key)
            }
        }

        if applied.isEmpty && cleared.isEmpty && unknown.isEmpty {
            return .rejected("no recognised keys")
        }
        var summary = "merged: \(applied.sorted().joined(separator: ", "))"
        if !cleared.isEmpty { summary += " · CLEARED: \(cleared.sorted().joined(separator: ", "))" }
        // Named rather than ignored: a typo in a key would otherwise look like a successful paste.
        if !unknown.isEmpty { summary += " · IGNORED unknown: \(unknown.sorted().joined(separator: ", "))" }
        return .merged(summary)
    }

    /// Posted whenever a credential / identity value changes, so a screen can rebuild. Separate from
    /// `appearanceDidChange`: a credential change may have to rebuild a session or a form, an
    /// appearance change must never do either.
    static let credentialsDidChange = Notification.Name("wirex.example.credentialsDidChange")

    private func announceCredentialsChange() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.credentialsDidChange, object: nil) }
    }

    /// Writes a single key — the per-field Config tab's edit. An EMPTY value CLEARS the key, matching
    /// `applyCredentials`. `notify` is false while a field is mid-edit (every keystroke) and true when
    /// it ends, so a screen rebuilds once on blur rather than on every character.
    func setCredential(_ key: String, _ value: String, notify: Bool = true) {
        lock.wirexWithLock {
            if value.isEmpty { credentials.removeValue(forKey: key) } else { credentials[key] = value }
        }
        if notify { announceCredentialsChange() }
    }

    /// The SDK environment NAME the Config tab selected, defaulting to `test`. A name, never a URL —
    /// the SDK resolves it to the hosts it ships with.
    var environment: String {
        let value = credential("environment")
        return value.isEmpty ? "test" : value
    }

    /// `test` everywhere but the production name — mirrors `exampleConfig.ts`.
    var isTestMode: Bool { environment != "production" }

    /// Clears every credential / identity value back to empty (environment falls back to `test`).
    func resetCredentials() {
        lock.wirexWithLock { credentials.removeAll() }
        announceCredentialsChange()
    }

    /// Per-key presence, and for JWTs whether they are still valid. The expiry check is the point:
    /// an expired `action_token` and a missing one fail identically at the API, and knowing which is
    /// the difference between pasting a new token and hunting a bug.
    func credentialsStatus() -> String {
        ["bearer", "actionToken", "cardId", "cardholderName", "email", "wallet"].map { key in
            let value = credential(key)
            guard !value.isEmpty else { return "\(key): —" }
            // Length and a short digest, so a value mangled in transit is VISIBLE rather than
            // inferred. iOS text substitution can rewrite a `-` inside a JWT into an en dash; the
            // result still parses as JSON and still looks like a token, and the only symptom is a
            // 400 from the backend. Comparing this line against the source settles it in seconds.
            let mark = "len=\(value.count) sha=\(Self.shortDigest(value))"
            guard let expiry = Self.jwtExpiry(value) else { return "\(key): set · \(mark)" }
            let remaining = Int(expiry.timeIntervalSinceNow)
            let life = remaining > 0 ? "valid \(remaining)s" : "EXPIRED \(-remaining)s ago"
            return "\(key): \(life) · \(mark)"
        }.joined(separator: "\n")
    }

    /// First 4 hex of SHA-256. One-way and truncated, so it identifies a value without disclosing
    /// it — enough to tell "the same token" from "almost the same token".
    private static func shortDigest(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(4).description
    }

    // MARK: - Appearance

    /// Merges appearance tokens, named exactly as `contract/appearance.tokens.json` names them, so a
    /// partner can paste the token map it already has.
    /// Posted whenever the appearance tokens change, so every screen restyles at once.
    ///
    /// Without this each screen read the tokens only when it happened to rebuild — the collect form
    /// picked up a new theme on the next profile switch, which looked like the tokens had not applied.
    static let appearanceDidChange = Notification.Name("wirex.example.appearanceDidChange")

    private func announceAppearanceChange() {
        NotificationCenter.default.post(name: Self.appearanceDidChange, object: nil)
    }

    /// The HOST's light / dark / system policy — the example's own, not the SDK's.
    ///
    /// This is the whole shape of the change: the SDK takes one appearance and draws it. Deciding
    /// which one, and noticing when the device flips, belongs to the application that owns the design
    /// system. `system` here resolves against the trait collection at the moment of asking.


    /// Replaces both maps outright. What a preset does, as opposed to the merge a pasted document
    /// does.
    func setAppearance(_ tokens: [String: Any]) {
        lock.wirexWithLock { appearanceTokens = tokens }
        announceAppearanceChange()
    }

    func applyAppearance(json: String) -> ConfigOutcome {
        guard let parsed = Self.parse(json) else { return .rejected("not valid JSON") }
        lock.wirexWithLock {
            for (key, value) in parsed { appearanceTokens[key] = value }
        }
        announceAppearanceChange()
        return .merged("merged: \(parsed.keys.sorted().joined(separator: ", "))")
    }


    func resetAppearance() {
        defer { announceAppearanceChange() }
        lock.wirexWithLock { appearanceTokens.removeAll() }
    }

    /// The map for the mode being shown. `system` is the EXAMPLE's own policy, resolved here — the
    /// SDK is handed one map and told which mode it is.
    ///
    /// The token reading is the SDK's, not the example's. `WirexAppearanceTokens` is that mapping,
    /// in core, where the vocabulary is generated from `contract/` — an example that reimplements what it
    /// is demonstrating teaches the wrong thing.
    /// The HOST picks; the SDK draws what it is given.
    ///
    /// ONE document, handed over as-is. Which document that is, is the host's decision — this example
    /// swaps it when the theme changes, in `AppearanceViewController`, because that is where an
    /// application's design system would do it. The SDK resolves no theme.
    func appearance(osIsDark: Bool) -> WirexAppearance {
        let tokens = lock.wirexWithLock { appearanceTokens }
        // The DEVICE decides, and only it. `mode` tells the SDK which set of built-in defaults an
        // absent token falls through to — it is not a theme the SDK resolves.
        return WirexAppearanceTokens.appearance(
            tokens: tokens,
            mode: osIsDark ? .dark : .light
        )
    }

    /// Whether the SELECTION resolves to dark right now, for a host deciding which document to send.
    /// Whether the DEVICE is dark. Nothing else decides.
    ///
    /// The example used to carry its own `light | dark | system` selection, and the Appearance tab
    /// had three buttons for it. That put a theme vocabulary on screen the SDK does not have: it
    /// resolves no theme and holds no palette — it draws the one complete document it is handed. A
    /// control the SDK cannot honour teaches a partner the wrong contract, so the OS decides and the
    /// example swaps the document.
    func isDarkMode(osIsDark: Bool) -> Bool { osIsDark }

    // MARK: - Helpers

    private static func parse(_ json: String) -> [String: Any]? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// `exp` from an unverified JWT payload. Signature is NOT checked and must not be: this is a
    /// convenience for the operator, and the server is the only thing entitled to trust a token.
    private static func jwtExpiry(_ token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
