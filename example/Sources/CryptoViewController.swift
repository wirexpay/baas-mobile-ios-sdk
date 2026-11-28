import UIKit
import WirexMobileSDK

/// The Crypto tab: sends from the main account to any network, and deposit addresses, through the SDK's
/// `WirexCrypto`. Same panels, buttons and wording as every platform's example.
final class CryptoViewController: UIViewController, PanelBuilding {

    /// A refusal of the tab's own, shown on the panel like an SDK error.
    private struct Refusal: Error, CustomStringConvertible { let description: String }

    /// A quote this run made, and the send's result once it ran. Memory only.
    private struct HeldSend {
        let quote: WirexSendQuote
        var result: WirexSendResult?
    }

    static let networks = ["ARC", "BASE", "ETHEREUM", "ARBITRUM", "OPTIMISM", "AVALANCHE", "MATIC_POS", "BINANCE", "TRON", "SOLANA"]
    static let families = ["EVM", "TRX", "SOL", "XLM", "BTC"]
    static let providers: [WirexSendRail?] = [nil, .cctp, .rhino, .across]

    private let scrollView = UIScrollView()
    private var keyboardAvoider: KeyboardAvoider?

    private let signerLabel = UILabel()
    private let balancesLabel = UILabel()
    private let quoteLabel = UILabel()
    private let sendLabel = UILabel()
    private let stepRows = UIStackView()
    private let resultLabel = UILabel()
    private let deliveryLabel = UILabel()
    private let pendingLabel = UILabel()
    private let pendingRows = UIStackView()
    private let depositLabel = UILabel()

    private let networkButton = UIButton(type: .system)
    private let tokenField = ConfigField()
    private let recipientField = ConfigField()
    private let amountField = ConfigField()
    private let providerControl = UISegmentedControl(items: ["any", "cctp", "rhino", "across"])
    private let familyControl = UISegmentedControl(items: CryptoViewController.families)

    private var network = "BASE"
    private var actionButtons: [UIButton] = []
    private var resumeButtons: [UIButton] = []
    private var sendButton: UIButton?
    private var checkDeliveryRow: UIView?

    private var balances: [WirexCryptoBalance] = []
    private var held: [String: HeldSend] = [:]
    /// The quote `Send` runs, and the config it was made under.
    private var current: WirexSendQuote?
    private var currentScope = ""
    private var lastResult: WirexSendResult?
    private var pending: [WirexPendingSend] = []
    private var stepLabels: [WirexCryptoStep: UILabel] = [:]
    private var busy = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Crypto"
        view.backgroundColor = Theme.bg
        buildLayout()
        refreshSigner()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshSigner), name: LiveConfig.credentialsDidChange, object: nil,
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshSigner()
    }

    // MARK: - Layout

    private func buildLayout() {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false

        content.addArrangedSubview(titleLabel("Crypto"))
        content.addArrangedSubview(caption(
            "Sends from the main account to any network, and deposit addresses. On production a send moves real "
                + "money, at most \(TradeGuards.productionCapUSD) USD a send, the fee included."
        ))

        content.addArrangedSubview(sectionLabel("Signer"))
        content.addArrangedSubview(card([signerLabel]))

        content.addArrangedSubview(sectionLabel("Balances"))
        content.addArrangedSubview(card([buttonRow(button("Read balances", #selector(readBalances))), balancesLabel]))

        content.addArrangedSubview(sectionLabel("Send"))
        networkButton.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
        networkButton.setTitleColor(Theme.teal, for: .normal)
        networkButton.contentHorizontalAlignment = .leading
        networkButton.showsMenuAsPrimaryAction = true
        networkButton.menu = UIMenu(children: Self.networks.map { code in
            UIAction(title: code) { [weak self] _ in self?.pickNetwork(code) }
        })
        pickNetwork(network)
        for control in [providerControl, familyControl] {
            control.selectedSegmentIndex = 0
            control.setTitleTextAttributes([.foregroundColor: Theme.textDim], for: .normal)
            control.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        }
        tokenField.text = "USDC"
        tokenField.autocapitalizationType = .allCharacters
        recipientField.placeholder = "recipient address"
        amountField.placeholder = "amount"
        amountField.keyboardType = .decimalPad
        let send = button("Send", #selector(sendQuote))
        sendButton = send
        let checkDelivery = buttonRow(button("Check delivery", #selector(checkDeliveryTapped)))
        checkDeliveryRow = checkDelivery
        stepRows.axis = .vertical
        stepRows.spacing = 4
        content.addArrangedSubview(card([
            labeled("Network", networkButton),
            labeled("Token", tokenField),
            labeled("To", recipientField),
            labeled("Amount", amountField),
            labeled("Provider", providerControl),
            hint("The amount is what arrives. The fee comes on top."),
            buttonRow(button("Get quote", #selector(getQuote))),
            quoteLabel,
            buttonRow(send),
            sendLabel,
            stepRows,
            resultLabel,
            checkDelivery,
            deliveryLabel,
        ]))

        content.addArrangedSubview(sectionLabel("Pending"))
        pendingRows.axis = .vertical
        pendingRows.spacing = 8
        content.addArrangedSubview(card([buttonRow(button("Load pending", #selector(loadPending))), pendingLabel, pendingRows]))

        content.addArrangedSubview(sectionLabel("Deposit"))
        content.addArrangedSubview(card([
            labeled("Family", familyControl),
            buttonRow(button("Get deposit address", #selector(getDepositAddress))),
            depositLabel,
        ]))

        for label in [signerLabel, balancesLabel, quoteLabel, sendLabel, resultLabel, deliveryLabel, pendingLabel, depositLabel] {
            style(label)
        }
        [balancesLabel, quoteLabel, sendLabel, pendingLabel, depositLabel].forEach { $0.text = "—" }
        syncButtons()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .onDrag
        scrollView.addSubview(content)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40),
            content.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
        ])
        keyboardAvoider = KeyboardAvoider(scrollView: scrollView, root: view)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)
    }

    @objc private func refreshSigner() {
        signerLabel.text = signerSummary()
        syncButtons()
    }

    private func pickNetwork(_ code: String) {
        network = code
        networkButton.setTitle("\(code) ▾", for: .normal)
    }

    // MARK: - Balances

    @objc private func readBalances() {
        run("Read balances", balancesLabel) { crypto in
            self.balances = try await crypto.balances()
            self.balancesLabel.text = self.balances.isEmpty
                ? "no balances"
                : self.balances.map { "\($0.symbol)  \(Self.amount($0.units, $0.decimals))" }.joined(separator: "\n")
            self.balancesLabel.textColor = Theme.textDim
        }
    }

    // MARK: - Quote and send

    @objc private func getQuote() {
        let token = (tokenField.text ?? "").trimmingCharacters(in: .whitespaces)
        let to = recipientField.text ?? ""
        let text = (amountField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return fail(quoteLabel, "set a token") }
        guard !to.isEmpty else { return fail(quoteLabel, "set a recipient") }
        guard let amount = TradeGuards.usd(text) else { return fail(quoteLabel, "set a positive amount") }
        // SECURITY: the typed amount meets the cap before anything is asked of the backend.
        if let refusal = TradeGuards.sendRefusal(environment: LiveConfig.shared.environment, symbol: token, amount: amount) {
            return fail(quoteLabel, refusal)
        }
        let network = self.network
        let provider = Self.providers[providerControl.selectedSegmentIndex]
        current = nil
        run("Get quote", quoteLabel) { crypto in
            let quote = try await crypto.quoteSend(to: to, network: network, token: token, amount: text, provider: provider)
            self.held[quote.sendId] = HeldSend(quote: quote)
            self.current = quote
            self.currentScope = self.configScope()
            self.quoteLabel.text = self.describe(quote)
            self.quoteLabel.textColor = Theme.textDim
            diag.sdk("crypto: quote rail \(quote.rail.rawValue)")
        }
    }

    @objc private func sendQuote() {
        guard let quote = current else { return fail(sendLabel, "get a quote first") }
        guard currentScope == configScope() else { return fail(sendLabel, "the config changed since the quote: get a new quote") }
        current = nil
        resetSteps()
        run("Send", sendLabel) { crypto in
            try await self.capWhatLeaves(quote, crypto)
            let result = try await crypto.send(quote, onStep: self.stepHandler())
            self.finished(result)
        }
    }

    @objc private func checkDeliveryTapped() {
        guard let result = lastResult, Self.showsCheckDelivery(result) else { return }
        run("Check delivery", deliveryLabel) { crypto in
            let status = try await crypto.sendStatus(result)
            var lines = ["delivery \(status.state.rawValue)"]
            if let hash = status.destinationTxHash { lines.append("destination tx \(hash)") }
            if let vendor = status.vendorState { lines.append("vendor \(vendor)") }
            if let refund = status.refund {
                let parts = [refund.amount, refund.token, refund.network, refund.transactionHash].compactMap { $0 }
                lines.append("refund " + (parts.isEmpty ? "named, with no details" : parts.joined(separator: " · ")))
            }
            self.deliveryLabel.text = lines.joined(separator: "\n")
            self.deliveryLabel.textColor = status.state == .delivered ? Theme.green : Theme.textDim
            diag.sdk("crypto: delivery \(status.state.rawValue)")
        }
    }

    // SECURITY: the cap on what leaves, the fee included, from a balances read made now.
    private func capWhatLeaves(_ quote: WirexSendQuote, _ crypto: WirexCrypto) async throws {
        balances = try await crypto.balances()
        if let refusal = TradeGuards.sendRefusal(environment: LiveConfig.shared.environment, quote: quote, balances: balances) {
            throw Refusal(description: refusal)
        }
    }

    private func finished(_ result: WirexSendResult) {
        held[result.sendId]?.result = result
        lastResult = result
        sendLabel.text = "sent"
        sendLabel.textColor = Theme.textDim
        var lines = ["send \(result.sendId) · \(result.rail.rawValue)"]
        if let hash = result.transactionHash { lines.append("tx \(hash)") }
        if let at = result.executedAt { lines.append("executed at \(at)") }
        if let id = result.quoteId { lines.append("rhino.fi quote \(id)") }
        if let id = result.depositId { lines.append("Across deposit \(id)") }
        resultLabel.text = lines.joined(separator: "\n")
        resultLabel.textColor = Theme.green
        deliveryLabel.text = nil
        syncButtons()
    }

    /// `Check delivery` reads a send to another network; a transfer on the account's own chain has nothing to read.
    static func showsCheckDelivery(_ result: WirexSendResult?) -> Bool {
        guard let result else { return false }
        return result.rail != .transfer
    }

    // MARK: - Pending

    @objc private func loadPending() {
        run("Load pending", pendingLabel) { crypto in
            self.pending = try await crypto.pendingSends()
            self.pendingLabel.text = self.pending.isEmpty ? "no pending sends" : "\(self.pending.count) pending"
            self.pendingLabel.textColor = Theme.textDim
            self.renderPending()
        }
    }

    private func renderPending() {
        pendingRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actionButtons.removeAll { button in resumeButtons.contains { $0 === button } }
        resumeButtons = []
        for (index, row) in pending.enumerated() {
            let label = UILabel()
            style(label)
            let known = balances.first { $0.token.lowercased() == row.token.lowercased() }
            let what = known.map { "\(Self.amount(row.units, row.decimals)) \($0.symbol)" }
                ?? "\(Self.amount(row.units, row.decimals)) of \(short(row.token))"
            label.text = "\(short(row.hash)) · \(what) → \(row.destination)\nvalid until \(row.validBefore)"
            var views: [UIView] = [label]
            if Self.heldQuote(for: row.hash, in: held.values.map(\.quote)) != nil {
                let resume = button("Resume", #selector(resumeRow(_:)))
                resume.tag = index
                resumeButtons.append(resume)
                views.append(buttonRow(resume))
            } else {
                views.append(hint("no quote held for this send"))
            }
            pendingRows.addArrangedSubview(card(views))
        }
        syncButtons()
    }

    /// A row names no `sendId`: a held quote is its send's when their hashes agree, in lower case.
    static func heldQuote(for hash: String, in quotes: [WirexSendQuote]) -> WirexSendQuote? {
        quotes.first { $0.requestHash.lowercased() == hash.lowercased() }
    }

    @objc private func resumeRow(_ sender: UIButton) {
        guard pending.indices.contains(sender.tag),
              let quote = Self.heldQuote(for: pending[sender.tag].hash, in: held.values.map(\.quote))
        else { return fail(pendingLabel, "no quote held for this send") }
        resetSteps()
        run("Resume", pendingLabel) { crypto in
            try await self.capWhatLeaves(quote, crypto)
            let result = try await crypto.resumeSend(sendId: quote.sendId, quote: quote, onStep: self.stepHandler())
            self.pendingLabel.text = "resumed \(result.sendId)"
            self.pendingLabel.textColor = Theme.textDim
            self.finished(result)
        }
    }

    // MARK: - Deposit

    @objc private func getDepositAddress() {
        let family = Self.families[familyControl.selectedSegmentIndex]
        run("Get deposit address", depositLabel) { crypto in
            let deposit = try await crypto.depositAddress(family: family)
            var lines = ["family \(deposit.family)", "address \(deposit.address)"]
            for network in deposit.networks {
                let tokens = network.tokens.map { "\($0.symbol) \($0.minUsd)–\($0.maxUsd) USD" }.joined(separator: ", ")
                lines.append("\(network.network): \(tokens)")
            }
            self.depositLabel.text = lines.joined(separator: "\n")
            self.depositLabel.textColor = Theme.textDim
        }
    }

    // MARK: - Steps

    private func resetSteps() {
        stepRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stepLabels = [:]
        resultLabel.text = nil
        deliveryLabel.text = nil
        lastResult = nil
        syncButtons()
    }

    /// `onStep` arrives off the main thread; each event updates its step's row in place.
    private func stepHandler() -> WirexCrypto.StepHandler {
        { [weak self] event in
            diag.sdk("crypto: \(event.step.rawValue) \(event.state.rawValue)\(event.reason.map { " \($0)" } ?? "")")
            DispatchQueue.main.async { self?.show(event) }
        }
    }

    private func show(_ event: WirexCryptoStepEvent) {
        let label = stepLabels[event.step] ?? {
            let label = UILabel()
            style(label)
            stepLabels[event.step] = label
            stepRows.addArrangedSubview(label)
            return label
        }()
        var parts = [event.step.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0), event.state.rawValue]
        if let reason = event.reason { parts.append(reason) }
        if let hash = event.userOpHash { parts.append("userOp \(short(hash))") }
        if let hash = event.transactionHash { parts.append("tx \(short(hash))") }
        label.text = parts.joined(separator: " · ")
        label.textColor = event.state == .failed ? Theme.pink : (event.state == .done ? Theme.green : Theme.textDim)
    }

    // MARK: - Running a member

    /// Gets the session's crypto, runs `body` on the main actor with every action disabled, and shows a
    /// failure in `label` as the error line every platform shares.
    private func run(_ name: String, _ label: UILabel, _ body: @escaping @MainActor (WirexCrypto) async throws -> Void) {
        diag.tap(name)
        view.endEditing(true)
        guard !busy else { return }
        let crypto: WirexCrypto
        do {
            crypto = try TradeSession.shared.crypto()
        } catch {
            return fail(label, TradeErrorText.line(error))
        }
        busy = true
        syncButtons()
        label.text = "\(name)…"
        label.textColor = Theme.textDim
        Task { @MainActor in
            do {
                try await body(crypto)
            } catch {
                let line = TradeErrorText.line(error)
                diag.err("crypto: \(name) failed: \(line)")
                self.fail(label, line)
            }
            self.busy = false
            self.syncButtons()
        }
    }

    private func fail(_ label: UILabel, _ line: String) {
        label.text = line
        label.textColor = Theme.pink
        syncButtons()
    }

    private func syncButtons() {
        for button in actionButtons {
            let enabled = !busy && (button !== sendButton || current != nil)
            button.isEnabled = enabled
            button.alpha = enabled ? 1 : 0.4
        }
        checkDeliveryRow?.isHidden = !Self.showsCheckDelivery(lastResult)
    }

    // MARK: - Formatting

    /// The quote's rail, fee and what arrives. To another network the pay token is the chain's USDC, at
    /// 6 decimals; on the own chain its decimals come from the last balances read, or the units show raw.
    private func describe(_ quote: WirexSendQuote) -> String {
        let decimals: Int? = quote.rail == .transfer
            ? balances.first { $0.token.lowercased() == quote.payToken.lowercased() }?.decimals
            : 6
        let format = { (units: String) in decimals.map { Self.amount(units, $0) } ?? "\(units) base units" }
        let arrives = quote.rail == .across ? "\(quote.arrives) base units" : format(quote.arrives)
        var lines = [
            "send \(quote.sendId)",
            "rail \(quote.rail.rawValue) · to \(quote.network)",
            "amount \(format(quote.amount)) \(quote.token) · fee \(format(quote.fee))",
            "arrives \(arrives)",
            "pays \(format(quote.payUnits)) of \(short(quote.payToken))",
        ]
        if let unwrap = quote.unwrap { lines.append("unwraps \(unwrap.units) base units of \(short(unwrap.token))") }
        if let until = TimeInterval(quote.validUntil) {
            lines.append("valid for \(max(0, Int(until - Date().timeIntervalSince1970))) s")
        }
        return lines.joined(separator: "\n")
    }

    /// Base units as decimal text at `decimals`, or the units as they came when they are not digits.
    static func amount(_ units: String, _ decimals: Int) -> String {
        TradeGuards.value(units: units, decimals: decimals).map { "\($0)" } ?? units
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    private func button(_ title: String, _ action: Selector) -> UIButton {
        let button = pill(title)
        button.addTarget(self, action: action, for: .touchUpInside)
        actionButtons.append(button)
        return button
    }
}
