import Foundation

/// The Trade tab's bearer: a pasted `bearer` wins, else a wallet-signature login with `ownerKey`, held in
/// memory until 30 s before `expires_at`, as the route allows 10 logins per 15 minutes per IP.
actor TradeLogin {
    static let shared = TradeLogin()

    enum Failure: Error, CustomStringConvertible {
        case missing(String)
        case refused(status: Int, reason: String)
        case malformed

        var description: String {
            switch self {
            case .missing(let what): return "login needs \(what) on the Config tab"
            case .refused(let status, let reason): return "login refused: HTTP \(status) \(reason)"
            case .malformed: return "login answered without access_token and expires_at"
            }
        }
    }

    private struct Session {
        let scope: String
        let bearer: String
        let expiresAt: Date
    }

    private var session: Session?
    private var inFlight: (scope: String, task: Task<Session, Error>)?

    func accessToken() async throws -> String {
        let config = LiveConfig.shared
        let pasted = config.credential("bearer")
        if !pasted.isEmpty { return pasted }

        let request = try LoginRequest(config: config)
        if let session, session.scope == request.scope, session.expiresAt.timeIntervalSinceNow > 30 {
            return session.bearer
        }
        // One login at a time per scope: parallel reads share it instead of each spending an attempt.
        if let inFlight, inFlight.scope == request.scope { return try await inFlight.task.value.bearer }
        let task = Task { try await Self.login(request) }
        inFlight = (request.scope, task)
        defer { inFlight = nil }
        let fresh = try await task.value
        session = fresh
        return fresh.bearer
    }

    /// Drops the held token, so the next call logs in again.
    func forget() { session = nil }

    private struct LoginRequest {
        let host: String
        let chainId: String
        let companyId: String
        let signer: TestOnlySigner

        /// A token is for one key, company, chain and host; a change to any of them logs in again.
        var scope: String { [signer.address, companyId, chainId, host].joined(separator: "|") }

        init(config: LiveConfig) throws {
            host = config.credential("baasApiUrl")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
            chainId = config.credential("chainId")
            companyId = config.credential("companyId")
            let key = config.credential("ownerKey")
            // SECURITY: https only, as the signed login goes to whatever host is typed.
            guard host.hasPrefix("https://") else { throw Failure.missing("an https BaaS API URL") }
            guard !chainId.isEmpty else { throw Failure.missing("the chain id") }
            guard !companyId.isEmpty else { throw Failure.missing("the company id") }
            guard !key.isEmpty else { throw Failure.missing("ownerKey, or a pasted bearer") }
            signer = try TestOnlySigner(hexKey: key)
        }
    }

    private static func login(_ request: LoginRequest) async throws -> Session {
        guard let url = URL(string: "\(request.host)/api/v1/user/authorize") else { throw Failure.missing("a valid BaaS API URL") }
        let nonce = Int(Date().timeIntervalSince1970)
        let message = "I, owner of account \(request.signer.address) confirm that I request access token for company \(request.companyId) on chain \(request.chainId) at \(nonce)"
        let signature = try request.signer.signMessage(message)

        var http = URLRequest(url: url)
        http.httpMethod = "POST"
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue(request.companyId, forHTTPHeaderField: "X-Company-Id")
        http.setValue(request.chainId, forHTTPHeaderField: "X-Chain-Id")
        http.httpBody = try JSONSerialization.data(withJSONObject: [
            "owner_address": request.signer.address,
            "message_signature": "0x" + Hex.encode(signature),
            "nonce": nonce,
        ])
        diag.sdk("trade: login started")
        let (data, response) = try await URLSession.shared.data(for: http)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else {
            // The route's reason name only: never the body, which can quote what was sent.
            let reason = (body?["error_reason"] as? String) ?? ""
            diag.err("trade: login failed HTTP \(status) \(reason)")
            throw Failure.refused(status: status, reason: reason)
        }
        guard let bearer = body?["access_token"] as? String, !bearer.isEmpty,
              let expiresAt = (body?["expires_at"] as? NSNumber)?.doubleValue
        else { throw Failure.malformed }
        diag.sdk("trade: login done")
        return Session(scope: request.scope, bearer: bearer, expiresAt: Date(timeIntervalSince1970: expiresAt))
    }
}
