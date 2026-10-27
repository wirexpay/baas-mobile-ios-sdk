import UIKit
import WirexMobileSDK

/// Wallet top-up — the Wirex-hosted Apple Pay / Google Pay checkout, embedded.
///
/// Two parts, one surface:
///  - an AVAILABILITY banner, driven by `WirexWalletAvailabilityChecker` (native canMakePayments). On a
///    simulator it answers unavailable — that is the real answer there, not a defect; a Pay sheet needs
///    a physical device with a provisioned card.
///  - the CHECKOUT: `WirexWalletCheckoutView` mounted from a pasted provider-config block and a quote
///    built from the fields. Legacy mode ends at the `token` event (your backend would execute); token
///    mode (paste a checkout token) has the frame execute itself.
///
/// The wallet surface is PART OF `WirexMobileSDK` — the same `import` as reveal / collect / 3DS. It keeps
/// its own environment table, resolved here from the one environment NAME this example is built for.
final class WalletViewController: UIViewController {
    // Resolved once from the example's environment name. Nil (with a reason) when the SDK has no
    // configuration for that name — the screen then shows the reason instead of a broken checkout.
    private var config: WirexWalletConfig?
    private var unavailableReason: String?
    /// The environment NAME the config was resolved for, so a Config-tab change can re-resolve.
    private var configuredEnvironment = ""
    private let cache = MemoryAvailabilityCache()

    private let scrollView = UIScrollView()
    private var keyboardAvoider: KeyboardAvoider?

    private let availabilityBanner = UILabel()
    private var checker: WirexWalletAvailabilityChecker?

    private let providerConfigView = UITextView()
    private let estimationIdField = UITextField()
    private let sourceAmountField = UITextField()
    private let sourceCurrencyField = UITextField()
    private let destinationAmountField = UITextField()
    private let destinationCurrencyField = UITextField()
    private let feeAmountField = UITextField()
    private let expiresSecondsField = UITextField()
    /// TOKEN MODE. Pasted for one run, held in memory only, never logged or shown back.
    private let checkoutTokenField = UITextField()
    private let providerNameField = UITextField()

    private let checkoutContainer = UIView()
    private var checkoutHeight: NSLayoutConstraint?
    private let log = EventLogView()

    private var checkout: WirexWalletCheckoutView?
    private var mountedProviderConfig: WirexWalletProviderConfig?
    private var quoteCounter = 1

    /// The SHAPE of a provider block, NOT real configuration. A live block arrives in your app config as
    /// `topup.providers.<name>` and is handed to the SDK VERBATIM; the values here only show what the
    /// fields look like, so the frame's handling of the block can be watched without a backend.
    private static let sampleProviderConfig = """
        {
          "apple_pay": {
            "merchant_name": "Example Merchant",
            "merchant_country_code": "GB",
            "merchant_capabilities": ["supports3DS"],
            "supported_networks": ["visa", "masterCard"],
            "required_billing_contact_fields": [],
            "api_version": 3
          },
          "google_pay": {
            "allowed_auth_methods": ["CRYPTOGRAM_3DS"],
            "allowed_card_networks": ["VISA", "MASTERCARD"],
            "api_version": 2,
            "api_version_minor": 0
          }
        }
        """

    init() {
        super.init(nibName: nil, bundle: nil)
        resolveConfig()
    }

    /// Resolves the wallet config from the Config tab's environment NAME. Re-run when it changes.
    private func resolveConfig() {
        let name = LiveConfig.shared.environment
        configuredEnvironment = name
        do {
            let environment = try WirexWalletEnvironment.resolve(name)
            config = WirexWalletConfig(
                environment: environment,
                clientId: nil,
                logging: WirexWalletLogging(level: .info, sink: ConsoleLogSink()),
                cache: cache
            )
            unavailableReason = nil
        } catch {
            config = nil
            unavailableReason = "Wallet environment '\(name)' is not available in this build: \(error)"
        }
    }

    /// A seed link (deep link or the Config tab's field) may carry the checkout token, estimation id and
    /// provider: prefill those fields, so a QA device needs no typing. They stay editable.
    private func syncSeededFields() {
        for (field, key) in [(checkoutTokenField, "checkoutToken"), (estimationIdField, "estimationId"), (providerNameField, "walletProvider")] {
            let seeded = LiveConfig.shared.credential(key)
            if !seeded.isEmpty, field.text != seeded, !field.isFirstResponder { field.text = seeded }
        }
    }

    /// The environment chip on the Config tab changed: what was built for the old one is torn down.
    @objc private func credentialsDidChange() {
        syncSeededFields()
        guard LiveConfig.shared.environment != configuredEnvironment else { return }
        checker?.stop()
        checker = nil
        checkout?.destroy()
        checkout?.removeFromSuperview()
        checkout = nil
        mountedProviderConfig = nil
        resolveConfig()
        log.append("environment → \(configuredEnvironment): checkout unmounted, availability re-probed")
        startAvailabilityProbe()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        checkout?.destroy()
        checker?.stop()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Wallet"
        buildLayout()
        NotificationCenter.default.addObserver(
            self, selector: #selector(credentialsDidChange), name: LiveConfig.credentialsDidChange, object: nil
        )

        scrollView.keyboardDismissMode = .onDrag
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)
        keyboardAvoider = KeyboardAvoider(scrollView: scrollView, root: view)

        startAvailabilityProbe()
    }

    // MARK: - Availability

    private func startAvailabilityProbe() {
        guard let config else {
            availabilityBanner.text = unavailableReason
            return
        }
        availabilityBanner.text = "Checking Apple Pay / Google Pay availability…"
        // `providerConfig: nil` pre-quote: iOS reads the block only for the Android floor keys, so the
        // probe answer is the same. On a simulator the answer is unavailable — the real answer there.
        let checker = WirexWalletAvailabilityChecker(config: config, providerConfig: nil)
        checker.onChange = { [weak self] availability in self?.renderAvailability(availability) }
        self.checker = checker
        renderAvailability(checker.current)
        checker.start()
    }

    private func renderAvailability(_ availability: WirexWalletAvailability?) {
        guard let availability else {
            availabilityBanner.text =
                "Apple Pay / Google Pay: checking… (unavailable on the Simulator — needs a real device)"
            return
        }
        let methods = [availability.applePay ? "Apple Pay" : nil, availability.googlePay ? "Google Pay" : nil]
            .compactMap { $0 }
        availabilityBanner.text = methods.isEmpty
            ? "Apple Pay / Google Pay unavailable here — needs a real device with a provisioned card."
            : "Pay available: \(methods.joined(separator: " · "))"
    }

    // MARK: - Actions

    @objc private func dismissKeyboard() { view.endEditing(true) }

    @objc private func insertSample() {
        diag.tap("Sample (shape only)")
        providerConfigView.text = Self.sampleProviderConfig
        log.append("sample provider config inserted — the SHAPE of a provider block, not real config")
    }

    @objc private func mount() {
        diag.tap("Mount checkout")
        view.endEditing(true)
        guard let config else { log.append(unavailableReason ?? "wallet unavailable"); return }

        let providerConfig: WirexWalletProviderConfig
        do {
            providerConfig = try WirexWalletProviderConfig(jsonText: providerConfigView.text ?? "")
        } catch {
            log.append("provider config rejected: \(error) — paste a JSON object (try the sample)")
            return
        }

        checkout?.destroy()
        checkout?.removeFromSuperview()

        let quote = currentQuote()
        let checkout = WirexWalletCheckoutView(
            config: config,
            quote: quote,
            providerConfig: providerConfig,
            appearance: nil,
            buttons: nil,
            branding: nil,
            strings: nil,
            auth: currentAuth(),
            provider: trimmedOrNil(providerNameField.text)
            // debug: omitted — never make the payment web view inspectable in a shipped app.
        )
        checkout.onEvent = { [weak self] event in self?.handle(event) }

        checkout.translatesAutoresizingMaskIntoConstraints = false
        checkoutContainer.addSubview(checkout)
        NSLayoutConstraint.activate([
            checkout.leadingAnchor.constraint(equalTo: checkoutContainer.leadingAnchor),
            checkout.trailingAnchor.constraint(equalTo: checkoutContainer.trailingAnchor),
            checkout.topAnchor.constraint(equalTo: checkoutContainer.topAnchor),
            checkout.bottomAnchor.constraint(equalTo: checkoutContainer.bottomAnchor),
        ])
        self.checkout = checkout
        mountedProviderConfig = providerConfig
        log.append("mounted: estimationId=\(quote.estimationId) mode=\(modeName) — waiting for ready")
    }

    @objc private func rearm() {
        diag.tap("New quote (rearm)")
        guard let checkout, let providerConfig = mountedProviderConfig else {
            log.append("nothing mounted — Mount checkout first")
            return
        }
        quoteCounter += 1
        estimationIdField.text = "example-\(quoteCounter)"
        let quote = currentQuote()
        checkout.rearm(quote: quote, providerConfig: providerConfig, auth: currentAuth(), provider: trimmedOrNil(providerNameField.text))
        log.append("rearm: estimationId=\(quote.estimationId) freshToken=\(currentAuth() != nil) — iOS reloads; expect ready again")
    }

    // MARK: - Events

    private func handle(_ event: WirexWalletCheckoutEvent) {
        switch event {
        case .ready:
            log.append("ready — review screen rendered, buttons live")
        case .naturalHeight(let height):
            checkoutHeight?.constant = CGFloat(height)
            log.append("naturalHeight: \(height)")
        case .sheetOpen:
            log.append("sheetOpen")
        case .cancelled:
            log.append("cancelled — nothing tokenized")
        case .attemptFailed(let reason):
            log.append("attemptFailed: \(reason)")
        case .estimationExpired:
            log.append("estimationExpired — tap New quote (rearm)")
        case .token(let token):
            log.append(
                "token: method=\(token.method.rawValue)"
                    + " cardNetwork=\(token.cardNetwork ?? "-")"
                    + " panLast4=\(token.panLast4 ?? "-")"
                    + " payload=<\(token.walletPaymentToken.count) chars, not shown>"
            )
            log.append("a host calls execute here with the token; this example has no backend, so it ends here")
        case .executing:
            log.append("executing — the frame is calling execute")
        case .executed(let result):
            log.append("executed: id=\(result.id) status=\(result.status) method=\(result.method.rawValue)")
        case .executeFailed(let error):
            log.append("executeFailed: reason=\(error.reason) detail=\(error.detail ?? "-") — paste a fresh token, then rearm")
        case .failed(let error):
            log.append("failed: \(error)")
        case .diagnostic(let diagnostic):
            let fields = diagnostic.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            log.append("diagnostic: \(diagnostic.kind.rawValue) \(fields)")
        case .debug(let level, let message):
            log.append("debug[\(level)]: \(message)")
        @unknown default:
            log.append("unknown event (SDK newer than this example)")
        }
    }

    // MARK: - Token mode / quote

    private func currentAuth() -> WirexWalletCheckoutAuth? {
        trimmedOrNil(checkoutTokenField.text).map { WirexWalletCheckoutAuth(checkoutToken: $0) }
    }

    private var modeName: String { currentAuth() == nil ? "legacy" : "token" }

    private func currentQuote() -> WirexWalletQuote {
        let sourceCurrency = text(sourceCurrencyField, fallback: "EUR")
        let seconds = Int64(text(expiresSecondsField, fallback: "900")) ?? 900
        var destination: WirexWalletMoney?
        if let amount = trimmedOrNil(destinationAmountField.text) {
            destination = WirexWalletMoney(amount: amount, currency: text(destinationCurrencyField, fallback: sourceCurrency))
        }
        var fee: WirexWalletMoney?
        if let amount = trimmedOrNil(feeAmountField.text) {
            fee = WirexWalletMoney(amount: amount, currency: sourceCurrency)
        }
        return WirexWalletQuote(
            estimationId: text(estimationIdField, fallback: "example-1"),
            sourceAmount: WirexWalletMoney(amount: text(sourceAmountField, fallback: "105.50"), currency: sourceCurrency),
            destinationAmount: destination,
            fee: fee,
            expiresAtMs: Int64(Date().timeIntervalSince1970 * 1000) + seconds * 1000
        )
    }

    private func text(_ field: UITextField, fallback: String) -> String { trimmedOrNil(field.text) ?? fallback }

    private func trimmedOrNil(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Layout

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        availabilityBanner.font = .preferredFont(forTextStyle: .footnote)
        availabilityBanner.numberOfLines = 0
        availabilityBanner.textColor = .secondaryLabel

        providerConfigView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        providerConfigView.layer.borderWidth = 1
        providerConfigView.layer.borderColor = UIColor.separator.cgColor
        providerConfigView.layer.cornerRadius = 8
        providerConfigView.heightAnchor.constraint(equalToConstant: 140).isActive = true
        providerConfigView.autocorrectionType = .no
        providerConfigView.autocapitalizationType = .none
        providerConfigView.text = Self.sampleProviderConfig

        configureField(estimationIdField, text: "example-1")
        configureField(sourceAmountField, text: "105.50")
        configureField(sourceCurrencyField, text: "EUR")
        configureField(destinationAmountField, text: "100.00")
        configureField(destinationCurrencyField, text: "EUR")
        configureField(feeAmountField, text: "5.50")
        configureField(expiresSecondsField, text: "900")
        configureField(checkoutTokenField, text: "")
        checkoutTokenField.placeholder = "top-up token (empty = legacy)"
        syncSeededFields()
        checkoutTokenField.smartQuotesType = .no
        checkoutTokenField.smartDashesType = .no
        checkoutTokenField.smartInsertDeleteType = .no
        checkoutTokenField.spellCheckingType = .no
        checkoutTokenField.isSecureTextEntry = true
        configureField(providerNameField, text: "")
        providerNameField.placeholder = "estimate's provider name (optional)"

        checkoutContainer.backgroundColor = UIColor(red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x14 / 255.0, alpha: 1)
        checkoutContainer.layer.cornerRadius = 12
        let height = checkoutContainer.heightAnchor.constraint(equalToConstant: 120)
        height.isActive = true
        checkoutHeight = height

        log.heightAnchor.constraint(equalToConstant: 200).isActive = true

        let stack = UIStackView(arrangedSubviews: [
            availabilityBanner,
            caption("Provider config JSON (topup.providers.<name>, verbatim)"),
            providerConfigView,
            actionButton("Sample (shape only)", action: #selector(insertSample)),
            caption("Quote"),
            labeledRow("estimationId", estimationIdField),
            actionButton("Fetch estimate", action: #selector(fetchEstimate)),
            labeledRow("source", sourceAmountField, sourceCurrencyField),
            labeledRow("destination", destinationAmountField, destinationCurrencyField),
            labeledRow("fee", feeAmountField),
            labeledRow("expires in (s)", expiresSecondsField),
            caption("Token mode"),
            labeledRow("top-up token", checkoutTokenField),
            labeledRow("provider", providerNameField),
            actionButton("Mount checkout", action: #selector(mount)),
            actionButton("New quote (rearm)", action: #selector(rearm)),
            caption("Checkout"),
            checkoutContainer,
            caption("Events"),
            log,
        ])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    // MARK: - Fetch estimate (verify a bearer; what your backend does)

    @objc private func fetchEstimate() {
        diag.tap("Fetch estimate")
        Task { await performFetchEstimate() }
    }

    /// Prices a top-up with the documented Wirex BaaS API using the bearer on the Config tab, and fills
    /// the estimation id. Pricing a top-up is the partner backend's job; this is a convenience to
    /// verify a token and get a real id without a backend. The SDK only consumes the id.
    private func performFetchEstimate() async {
        let cfg = LiveConfig.shared
        let base = cfg.credential("baasApiUrl")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let bearer = cfg.credential("bearer")
        let chainId = cfg.credential("chainId")
        let wallet = cfg.credential("wallet")
        let email = cfg.credential("email")
        // https only: the bearer goes to whatever is typed here. The chain id is required by the API.
        guard base.hasPrefix("https://"), !bearer.isEmpty, !chainId.isEmpty else {
            log.append("Fetch estimate: set an https BaaS API URL, a bearer and the chain id on the Config tab")
            return
        }
        var headers = ["Authorization": "Bearer \(bearer)", "X-Chain-Id": chainId, "Content-Type": "application/json"]
        if !wallet.isEmpty {
            headers["X-User-Wallet"] = wallet
        } else if !email.isEmpty {
            headers["X-User-Email"] = email
        } else {
            log.append("Fetch estimate: set a user wallet or email on the Config tab")
            return
        }
        let currency = text(destinationCurrencyField, fallback: "EUR")
        let amount = text(destinationAmountField, fallback: "100.00")
        do {
            let (address, decimals) = try await resolveSettlementToken(base: base, headers: headers, currency: currency)
            let estimationId = try await postEstimate(base: base, headers: headers, amount: amount, decimals: decimals, tokenAddress: address)
            await MainActor.run {
                self.estimationIdField.text = estimationId
                self.log.append("estimate: \(estimationId)")
            }
        } catch {
            await MainActor.run { self.log.append("estimate failed: \(error.localizedDescription)") }
        }
    }

    private func resolveSettlementToken(base: String, headers: [String: String], currency: String) async throws -> (String, Int) {
        guard let url = URL(string: "\(base)/api/v1/config/tokens") else {
            throw NSError(domain: "estimate", code: 0, userInfo: [NSLocalizedDescriptionKey: "BaaS API URL is not a valid URL"])
        }
        var req = URLRequest(url: url)
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "estimate", code: 1, userInfo: [NSLocalizedDescriptionKey: "GET /config/tokens failed"])
        }
        let json = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]] = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["data"] as? [[String: Any]]) ?? []
        for row in rows {
            let equiv = row["equivalent_symbols"] as? [String] ?? []
            let symbol = row["symbol"] as? String ?? ""
            if equiv.contains(currency) || symbol.hasSuffix(currency) {
                let address = (row["address"] as? String) ?? (row["contract_address"] as? String) ?? ""
                let decimals = row["decimals"] as? Int ?? 18
                return (address, decimals)
            }
        }
        throw NSError(domain: "estimate", code: 2, userInfo: [NSLocalizedDescriptionKey: "no settlement token for \(currency)"])
    }

    private func postEstimate(base: String, headers: [String: String], amount: String, decimals: Int, tokenAddress: String) async throws -> String {
        guard let url = URL(string: "\(base)/api/v1/cards/topup/estimate") else {
            throw NSError(domain: "estimate", code: 0, userInfo: [NSLocalizedDescriptionKey: "BaaS API URL is not a valid URL"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "destination_amount": Self.toBaseUnits(amount, decimals: decimals),
            "destination_token_address": tokenAddress,
            "payment_method": "apple_pay",
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "estimate", code: 3, userInfo: [NSLocalizedDescriptionKey: "POST /cards/topup/estimate failed: \(body)"])
        }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = obj?["estimation_id"] as? String else {
            throw NSError(domain: "estimate", code: 4, userInfo: [NSLocalizedDescriptionKey: "no estimation_id in response"])
        }
        return id
    }

    /// display amount (e.g. "100.00") → base-units string (amount * 10^decimals), without float loss.
    private static func toBaseUnits(_ amount: String, decimals: Int) -> String {
        let parts = amount.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = parts.first.map(String.init) ?? "0"
        let frac = parts.count > 1 ? String(parts[1]) : ""
        let fracPadded = String((frac + String(repeating: "0", count: decimals)).prefix(decimals))
        let scaled = String((whole + fracPadded).drop(while: { $0 == "0" }))
        return scaled.isEmpty ? "0" : scaled
    }

    private func configureField(_ field: UITextField, text: String) {
        field.text = text
        field.borderStyle = .roundedRect
        field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
    }

    private func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        label.numberOfLines = 0
        return label
    }

    private func labeledRow(_ name: String, _ controls: UIView...) -> UIView {
        let label = UILabel()
        label.text = name
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let row = UIStackView(arrangedSubviews: [label] + controls)
        row.spacing = 8
        row.alignment = .center
        row.distribution = .fill
        return row
    }

    private func actionButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
}
