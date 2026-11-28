import UIKit
import WirexMobileSDK

/// The Trade tab: stocks and coins through the SDK's `WirexTrade`, with the same panels, buttons and
/// wording on every platform's example. The tab signs with the test user's key, held in memory.
final class TradeViewController: UIViewController, PanelBuilding {

    private let scrollView = UIScrollView()
    private var keyboardAvoider: KeyboardAvoider?

    private let signerLabel = UILabel()
    private let accountLabel = UILabel()
    private let catalogLabel = UILabel()
    private let catalogRows = UIStackView()
    private let quoteLabel = UILabel()
    private let tradeLabel = UILabel()
    private let stepRows = UIStackView()
    private let orderLabel = UILabel()
    private let ordersLabel = UILabel()
    private let orderRows = UIStackView()

    private let marketControl = UISegmentedControl(items: ["stock", "coin"])
    private let sideControl = UISegmentedControl(items: ["buy", "sell"])
    private let symbolField = ConfigField()
    private let amountField = ConfigField()
    private var actionButtons: [UIButton] = []
    private var executeButton: UIButton?
    private var resumeButtons: [UIButton] = []

    /// The last quote, kept for `Resume` of the same order after an `Execute` that could not carry on.
    private var quote: WirexTradeQuote?
    /// Where the quote was made. A config change since then means a new quote.
    private var quoteScope = ""
    /// False once the quote ran, or when the cap refused it.
    private var quoteExecutable = false
    private var openOrders: [WirexTradeOpenOrder] = []
    private var stepLabels: [WirexTradeStep: UILabel] = [:]
    private var busy = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Trade"
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

        content.addArrangedSubview(titleLabel("Trade"))
        content.addArrangedSubview(caption(
            "Stocks and coins through the SDK's Trade surface. On production a trade moves real money, at most "
                + "\(TradeGuards.productionCapUSD) USD a trade."
        ))

        content.addArrangedSubview(sectionLabel("Signer"))
        content.addArrangedSubview(card([signerLabel]))

        content.addArrangedSubview(sectionLabel("Account"))
        content.addArrangedSubview(card([
            buttonRow(button("Read account", #selector(readAccount)), button("Set up account", #selector(setUpAccount))),
            accountLabel,
        ]))

        content.addArrangedSubview(sectionLabel("Catalog"))
        catalogRows.axis = .vertical
        catalogRows.spacing = 6
        content.addArrangedSubview(card([buttonRow(button("Load catalog", #selector(loadCatalog))), catalogLabel, catalogRows]))

        content.addArrangedSubview(sectionLabel("Quote"))
        for control in [marketControl, sideControl] {
            control.selectedSegmentIndex = 0
            control.setTitleTextAttributes([.foregroundColor: Theme.textDim], for: .normal)
            control.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        }
        symbolField.placeholder = "symbol, such as AAPL or ETH"
        symbolField.autocapitalizationType = .allCharacters
        amountField.placeholder = "amount"
        amountField.keyboardType = .decimalPad
        content.addArrangedSubview(card([
            labeled("Market", marketControl),
            labeled("Side", sideControl),
            labeled("Symbol", symbolField),
            labeled("Amount", amountField),
            hint("A buy's amount is USD. A sale's amount is the token."),
            buttonRow(button("Get quote", #selector(getQuote))),
            quoteLabel,
        ]))

        content.addArrangedSubview(sectionLabel("Trade"))
        let execute = button("Execute", #selector(executeQuote))
        executeButton = execute
        stepRows.axis = .vertical
        stepRows.spacing = 4
        content.addArrangedSubview(card([buttonRow(execute), tradeLabel, stepRows, orderLabel]))

        content.addArrangedSubview(sectionLabel("Open orders"))
        orderRows.axis = .vertical
        orderRows.spacing = 8
        content.addArrangedSubview(card([buttonRow(button("Load open orders", #selector(loadOpenOrders))), ordersLabel, orderRows]))

        for label in [signerLabel, accountLabel, catalogLabel, quoteLabel, tradeLabel, orderLabel, ordersLabel] {
            style(label)
        }
        [accountLabel, catalogLabel, quoteLabel, tradeLabel, ordersLabel].forEach { $0.text = "—" }
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

    // MARK: - Account and catalog

    @objc private func readAccount() {
        run("Read account", accountLabel) { trade in
            let account = try await trade.account()
            self.show(account)
        }
    }

    @objc private func setUpAccount() {
        resetSteps()
        run("Set up account", accountLabel) { trade in
            let account = try await trade.setUpAccount(onStep: self.stepHandler())
            self.show(account)
        }
    }

    private func show(_ account: WirexTradeAccount) {
        var lines = ["chain \(account.chainId)", "main \(account.mainAccount)"]
        if let investment = account.investmentAccount {
            lines.append("investment \(investment) (\(account.isSetUp ? "set up" : "not set up"))")
        } else {
            lines.append("investment none: the config lists no Base")
        }
        lines.append("cash " + (account.cash.map { "\(Self.amount($0.units, $0.decimals)) USDC" } ?? "—"))
        lines.append(account.holdings.isEmpty ? "holdings none" : "holdings")
        for holding in account.holdings {
            let size = holding.sharesShown.map { "\($0) shares" } ?? Self.amount(holding.units, holding.decimals)
            let value = holding.valueCents.map { " · \($0) USD" } ?? ""
            lines.append("  \(holding.market.rawValue) \(holding.symbol) \(size)\(value)")
        }
        accountLabel.text = lines.joined(separator: "\n")
        accountLabel.textColor = Theme.textDim
    }

    @objc private func loadCatalog() {
        run("Load catalog", catalogLabel) { trade in
            let items = try await trade.catalog()
            self.catalogRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
            self.catalogLabel.text = items.isEmpty ? "nothing to trade" : "\(items.count) symbols: tap one to fill the quote"
            self.catalogLabel.textColor = Theme.textDim
            for item in items {
                let row = UIButton(type: .system)
                row.setTitle("\(item.market.rawValue)  \(item.symbol)", for: .normal)
                row.setTitleColor(Theme.teal, for: .normal)
                row.titleLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
                row.contentHorizontalAlignment = .leading
                row.accessibilityIdentifier = "catalog \(item.symbol)"
                row.addAction(UIAction { [weak self] _ in self?.fillQuote(item) }, for: .touchUpInside)
                self.catalogRows.addArrangedSubview(row)
            }
        }
    }

    private func fillQuote(_ item: WirexTradeCatalogItem) {
        diag.tap("catalog \(item.symbol)")
        marketControl.selectedSegmentIndex = item.market == .stock ? 0 : 1
        symbolField.text = item.symbol
    }

    // MARK: - Quote and execute

    @objc private func getQuote() {
        let market: WirexTradeMarket = marketControl.selectedSegmentIndex == 0 ? .stock : .coin
        let side: WirexTradeSide = sideControl.selectedSegmentIndex == 0 ? .buy : .sell
        let symbol = (symbolField.text ?? "").trimmingCharacters(in: .whitespaces)
        let text = (amountField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return fail(quoteLabel, "set a symbol") }
        guard let amount = TradeGuards.usd(text) else { return fail(quoteLabel, "set a positive amount") }
        // SECURITY: the typed buy amount meets the cap before anything is asked of the backend.
        let environment = LiveConfig.shared.environment
        if side == .buy, let refusal = TradeGuards.refusal(environment: environment, usd: amount) {
            return fail(quoteLabel, refusal)
        }
        quoteExecutable = false
        run("Get quote", quoteLabel) { trade in
            let quote = try await trade.quote(market: market, side: side, symbol: symbol, amount: text)
            self.quote = quote
            self.quoteScope = self.configScope()
            // SECURITY: the quote's own worth meets the cap; a refused quote cannot be executed.
            let refusal = TradeGuards.refusal(environment: environment, quote: quote)
            self.quoteExecutable = refusal == nil
            self.quoteLabel.text = Self.describe(quote) + (refusal.map { "\n\($0)" } ?? "")
            self.quoteLabel.textColor = refusal == nil ? Theme.textDim : Theme.pink
        }
    }

    @objc private func executeQuote() {
        guard let quote, quoteExecutable else { return fail(tradeLabel, "get a quote first") }
        guard quoteScope == configScope() else { return fail(tradeLabel, "the config changed since the quote: get a new quote") }
        // SECURITY: the cap again at Execute, on the environment as it stands now.
        if let refusal = TradeGuards.refusal(environment: LiveConfig.shared.environment, quote: quote) {
            quoteExecutable = false
            syncButtons()
            return fail(tradeLabel, refusal)
        }
        quoteExecutable = false
        resetSteps()
        run("Execute", tradeLabel) { trade in
            let order = try await trade.execute(quote, onStep: self.stepHandler())
            self.tradeLabel.text = "ended"
            self.show(order)
        }
    }

    // MARK: - Open orders

    @objc private func loadOpenOrders() {
        run("Load open orders", ordersLabel) { trade in
            self.openOrders = try await trade.openOrders()
            self.ordersLabel.text = self.openOrders.isEmpty ? "no open orders" : "\(self.openOrders.count) open"
            self.ordersLabel.textColor = Theme.textDim
            self.renderOpenOrders()
        }
    }

    private func renderOpenOrders() {
        orderRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actionButtons.removeAll { button in resumeButtons.contains { $0 === button } }
        resumeButtons = []
        for (index, order) in openOrders.enumerated() {
            let label = UILabel()
            style(label)
            let next = order.nextStep?.rawValue ?? "nothing to run"
            label.text = "\(order.orderId)\n\(order.side.rawValue) \(order.market.rawValue) · \(order.status) · next \(next)"
            let resume = button("Resume", #selector(resumeRow(_:)))
            resume.tag = index
            resumeButtons.append(resume)
            orderRows.addArrangedSubview(card([label, buttonRow(resume)]))
        }
        syncButtons()
    }

    @objc private func resumeRow(_ sender: UIButton) {
        guard openOrders.indices.contains(sender.tag) else { return }
        let order = openOrders[sender.tag]
        // SECURITY: an open order's terms meet the cap before it is carried on.
        if let refusal = TradeGuards.refusal(environment: LiveConfig.shared.environment, order: order) {
            return fail(ordersLabel, refusal)
        }
        let paired = Self.resumeQuote(quote, for: order.orderId)
        resetSteps()
        run("Resume", ordersLabel) { trade in
            let ended = try await trade.resume(orderId: order.orderId, quote: paired, onStep: self.stepHandler())
            self.ordersLabel.text = "resumed \(ended.orderId): \(ended.status)"
            self.ordersLabel.textColor = Theme.textDim
            self.tradeLabel.text = "ended"
            self.show(ended)
        }
    }

    /// The held quote goes with `resume` only when it made that same order.
    static func resumeQuote(_ quote: WirexTradeQuote?, for orderId: String) -> WirexTradeQuote? {
        quote?.orderId == orderId ? quote : nil
    }

    // MARK: - Steps

    private func resetSteps() {
        stepRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stepLabels = [:]
        orderLabel.text = nil
        tradeLabel.text = "—"
        tradeLabel.textColor = Theme.textDim
    }

    /// `onStep` arrives off the main thread; each event updates its step's row in place.
    private func stepHandler() -> WirexTrade.StepHandler {
        { [weak self] event in
            diag.sdk("trade: \(event.step.rawValue) \(event.state.rawValue)\(event.status.map { " \($0)" } ?? "")\(event.reason.map { " \($0)" } ?? "")")
            DispatchQueue.main.async { self?.show(event) }
        }
    }

    private func show(_ event: WirexTradeStepEvent) {
        let label = stepLabels[event.step] ?? {
            let label = UILabel()
            style(label)
            stepLabels[event.step] = label
            stepRows.addArrangedSubview(label)
            return label
        }()
        var parts = [event.step.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0), event.state.rawValue]
        if let status = event.status { parts.append(status) }
        if let reason = event.reason { parts.append(reason) }
        if let hash = event.userOpHash { parts.append("userOp \(short(hash))") }
        if let hash = event.transactionHash { parts.append("tx \(short(hash))") }
        label.text = parts.joined(separator: " · ")
        label.textColor = event.state == .failed ? Theme.pink : (event.state == .done ? Theme.green : Theme.textDim)
    }

    private func show(_ order: WirexTradeOrder) {
        var lines = ["order \(order.orderId)", "status \(order.status)" + (order.statusReason.map { " · \($0)" } ?? "")]
        lines.append("in \(Self.amount(order.amountIn, order.tokenInDecimals))")
        lines.append(
            "out \(Self.amount(order.amountOut, order.tokenOutDecimals)) (estimated "
                + "\(Self.amount(order.estimatedAmountOut, order.tokenOutDecimals)), minimum "
                + "\(Self.amount(order.minimumAmountOut, order.tokenOutDecimals)))"
        )
        if let shares = order.shares {
            let decimals = order.side == .buy ? order.tokenOutDecimals : order.tokenInDecimals
            lines.append("shares \(Self.amount(shares, decimals))")
        }
        if order.refundedAmount != "0" { lines.append("refunded \(Self.amount(order.refundedAmount, order.tokenInDecimals))") }
        if let hash = order.transactionHash { lines.append("tx \(hash)") }
        orderLabel.text = lines.joined(separator: "\n")
        orderLabel.textColor = order.status == "Completed" ? Theme.green : Theme.textDim
    }

    // MARK: - Running a member

    /// Gets the session's trade, runs `body` on the main actor with every action disabled, and shows a
    /// failure in `label` as the error line every platform shares.
    private func run(_ name: String, _ label: UILabel, _ body: @escaping @MainActor (WirexTrade) async throws -> Void) {
        diag.tap(name)
        view.endEditing(true)
        guard !busy else { return }
        let trade: WirexTrade
        do {
            trade = try TradeSession.shared.trade()
        } catch {
            return fail(label, TradeErrorText.line(error))
        }
        busy = true
        syncButtons()
        label.text = "\(name)…"
        label.textColor = Theme.textDim
        Task { @MainActor in
            do {
                try await body(trade)
            } catch {
                let line = TradeErrorText.line(error)
                diag.err("trade: \(name) failed: \(line)")
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
            let enabled = !busy && (button !== executeButton || (quote != nil && quoteExecutable))
            button.isEnabled = enabled
            button.alpha = enabled ? 1 : 0.4
        }
    }

    // MARK: - Formatting

    static func describe(_ quote: WirexTradeQuote) -> String {
        let usdc = quote.side == .buy
        let inName = usdc ? "USDC" : quote.symbol
        let outName = usdc ? quote.symbol : "USDC"
        var lines = [
            "order \(quote.orderId) · \(quote.executionMethod)",
            "in \(amount(quote.amountIn, quote.tokenInDecimals)) \(inName)",
            "out ≈ \(amount(quote.estimatedAmountOut, quote.tokenOutDecimals)) \(outName), "
                + "minimum \(amount(quote.minimumAmountOut, quote.tokenOutDecimals))",
        ]
        if let estimated = quote.estimatedShares {
            let decimals = usdc ? quote.tokenOutDecimals : quote.tokenInDecimals
            let minimum = quote.minimumShares.map { ", minimum \(amount($0, decimals))" } ?? ""
            lines.append("shares ≈ \(amount(estimated, decimals))\(minimum)")
        }
        lines.append("fee \(quote.feeAmount) base units")
        if let fee = quote.transferFee { lines.append("transfer fee \(amount(fee, 6)) USDC") }
        lines.append("sign by \(quote.signBy) · valid until \(quote.validUntil)")
        return lines.joined(separator: "\n")
    }

    /// Base units as decimal text at `decimals`, or the units as they came when they are not digits.
    static func amount(_ units: String, _ decimals: Int) -> String {
        guard let value = TradeGuards.value(units: units, decimals: decimals) else { return units }
        return "\(value)"
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    private func button(_ title: String, _ action: Selector) -> UIButton {
        let button = pill(title)
        button.addTarget(self, action: action, for: .touchUpInside)
        actionButtons.append(button)
        return button
    }
}
