import UIKit

/// The Config (debug) tab: a per-field form over `LiveConfig`, so QA types every integration
/// parameter and credential straight into the running build — no rebuild, no source edit, no pasted
/// JSON. One binary, any partner's data.
///
/// Mirrors the React Native example's Config screen: the same field contract (PARTNER-CONFIG.md) and
/// the same two tiers — non-secret integration parameters, and secrets held in memory only. Every
/// surface reads `LiveConfig` live, so a value typed here takes effect on the next call; a change to a
/// value a session captured (the card id) rebuilds that session through `LiveConfig.credentialsDidChange`.
final class ConfigViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let statusLabel = UILabel()
    private var fields: [ConfigField] = []
    private var environmentChips: [UIButton] = []

    // Non-secret integration parameters, in the same order the RN example lists them.
    private struct FieldSpec { let key: String; let label: String; let hint: String?; let secure: Bool }
    private static let integration: [FieldSpec] = [
        FieldSpec(key: "chainId", label: "Chain ID", hint: "X-Chain-Id — Wirex assigns per integration", secure: false),
        FieldSpec(key: "email", label: "User email", hint: "X-User-Email", secure: false),
        FieldSpec(key: "wallet", label: "User wallet", hint: "X-User-Wallet (EOA)", secure: false),
        FieldSpec(key: "cardId", label: "Card ID", hint: "the card Reveal / Collect act on", secure: false),
        FieldSpec(key: "cardholderName", label: "Cardholder name", hint: nil, secure: false),
        FieldSpec(key: "baasApiUrl", label: "BaaS API URL", hint: "for the Wallet \u{201C}Fetch estimate\u{201D} helper", secure: false),
    ]
    private static let secrets: [FieldSpec] = [
        FieldSpec(key: "bearer", label: "Bearer token", hint: "getAccessToken — Wirex bearer for the user", secure: true),
        FieldSpec(key: "actionToken", label: "Step-up action token", hint: "getActionToken — card data / PIN", secure: true),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Config"
        view.backgroundColor = Theme.bg
        buildLayout()
        refreshStatus()
        // A seed deep link that arrives while this tab is on screen changes the store without a
        // viewWillAppear; mirror the new values into the fields, skipping the one being edited.
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncFields), name: LiveConfig.credentialsDidChange, object: nil,
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Reflect whatever another path (a launch argument, a seed deep link) put in the store.
        syncFields()
    }

    @objc private func syncFields() {
        fields.forEach { field in
            guard !field.isFirstResponder else { return }
            let value = LiveConfig.shared.credential(field.configKey)
            if field.text != value { field.text = value }
        }
        syncEnvironmentChips()
        captureSwitch.isOn = !LiveConfig.shared.isScreenProtectionDisabled
        refreshStatus()
    }

    // MARK: - Layout

    private func buildLayout() {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false

        content.addArrangedSubview(titleLabel("Configuration"))
        content.addArrangedSubview(caption(
            "Type a partner's parameters here; every screen reads them live. Secrets stay in memory only."
        ))

        content.addArrangedSubview(sectionLabel("Seed link"))
        content.addArrangedSubview(seedLinkCard())

        content.addArrangedSubview(sectionLabel("Environment"))
        content.addArrangedSubview(environmentRow())

        content.addArrangedSubview(sectionLabel("Integration parameters"))
        content.addArrangedSubview(group(Self.integration))

        content.addArrangedSubview(sectionLabel("Secrets · memory only"))
        content.addArrangedSubview(group(Self.secrets))

        content.addArrangedSubview(sectionLabel("Screen capture"))
        content.addArrangedSubview(screenCaptureCard())

        content.addArrangedSubview(sectionLabel("Credentials status"))
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.numberOfLines = 0
        statusLabel.textColor = Theme.textDim
        let statusCard = card([statusLabel, pillButton("Refresh status", color: Theme.surfaceAlt, textColor: Theme.teal, action: #selector(refreshStatus))])
        content.addArrangedSubview(statusCard)

        let reset = pillButton("Reset all", color: .clear, textColor: Theme.pink, action: #selector(resetAll))
        reset.backgroundColor = Theme.pink.withAlphaComponent(0.13)
        reset.layer.borderWidth = 1
        reset.layer.borderColor = Theme.pink.cgColor
        let resetRow = UIStackView(arrangedSubviews: [reset, UIView()])
        resetRow.axis = .horizontal
        resetRow.spacing = 0
        content.setCustomSpacing(26, after: statusCard)
        content.addArrangedSubview(resetRow)

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

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)
    }

    /// The same `wirexqa://seed?d=…` link the app opens as a deep link, pasted instead — for a device
    /// where opening the link is awkward (a chat that strips the scheme, a locked-down browser).
    private let seedField = ConfigField()
    private let seedStatus = UILabel()

    private func seedLinkCard() -> UIView {
        seedField.placeholder = "wirexqa://seed?d=…"
        seedField.keyboardType = .URL
        seedField.returnKeyType = .done
        seedField.addTarget(self, action: #selector(applySeedLink), for: .editingDidEndOnExit)
        seedStatus.text = "Paste the link the QA kit prints (the same one the app opens as a deep link); Apply fills every field below."
        seedStatus.font = .systemFont(ofSize: 12)
        seedStatus.textColor = Theme.textFaint
        seedStatus.numberOfLines = 0
        let apply = pillButton("Apply", color: Theme.accent, textColor: Theme.onAccent, action: #selector(applySeedLink))
        let applyRow = UIStackView(arrangedSubviews: [apply, UIView()])
        applyRow.axis = .horizontal
        return card([seedField, applyRow, seedStatus])
    }

    @objc private func applySeedLink() {
        let applied = LiveConfig.shared.applySeedLink(seedField.text ?? "")
        seedStatus.text = applied.map { "Applied \($0) value\($0 == 1 ? "" : "s")" } ?? "Not a wirexqa://seed link"
        seedStatus.textColor = applied == nil ? Theme.pink : Theme.green
        if applied != nil { seedField.text = "" }
        view.endEditing(true)
        syncFields()
    }

    private func environmentRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        for name in ["test", "production"] {
            let chip = UIButton(type: .custom)
            chip.setTitle(name, for: .normal)
            chip.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
            chip.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
            chip.layer.cornerRadius = 20
            chip.layer.borderWidth = 1
            chip.accessibilityIdentifier = name
            chip.addTarget(self, action: #selector(pickEnvironment(_:)), for: .touchUpInside)
            environmentChips.append(chip)
            row.addArrangedSubview(chip)
        }
        row.addArrangedSubview(UIView())
        syncEnvironmentChips()
        return row
    }

    private let captureSwitch = UISwitch()

    /// DEV/TEST ONLY. Off = `dangerouslyDisableScreenProtection: true` on Reveal, Collect and 3DS, so QA can
    /// capture the surfaces (the Simulator renders the secure layer blank otherwise). A seed link can set
    /// the same key (`disableScreenProtection`). Never ship a build with it off to cardholders.
    private func screenCaptureCard() -> UIView {
        let label = UILabel()
        label.text = "Screen-capture protection"
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = Theme.text
        let hint = UILabel()
        hint.text = "On — card data is HIDDEN from screenshots / recording on Reveal, Collect & 3DS (the secure default).\nOff — data is VISIBLE so QA can capture it for a test."
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = Theme.textFaint
        hint.numberOfLines = 0
        let texts = UIStackView(arrangedSubviews: [label, hint])
        texts.axis = .vertical
        texts.spacing = 2
        captureSwitch.onTintColor = Theme.accent
        captureSwitch.isOn = !LiveConfig.shared.isScreenProtectionDisabled
        captureSwitch.addTarget(self, action: #selector(captureSwitchChanged), for: .valueChanged)
        captureSwitch.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [texts, captureSwitch])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return card([row])
    }

    @objc private func captureSwitchChanged() {
        LiveConfig.shared.setCredential("disableScreenProtection", captureSwitch.isOn ? "" : "true")
    }

    private func group(_ specs: [FieldSpec]) -> UIView {
        var views: [UIView] = []
        for spec in specs {
            let field = ConfigField()
            field.configKey = spec.key
            field.text = LiveConfig.shared.credential(spec.key)
            field.isSecureTextEntry = spec.secure
            field.placeholder = spec.secure ? "paste…" : ""
            field.addTarget(self, action: #selector(fieldChanged(_:)), for: .editingChanged)
            field.addTarget(self, action: #selector(fieldEnded(_:)), for: .editingDidEnd)
            fields.append(field)

            let label = UILabel()
            label.text = spec.label
            label.font = .systemFont(ofSize: 14, weight: .bold)
            label.textColor = Theme.text

            var stack: [UIView] = [label]
            if let hint = spec.hint {
                let hintLabel = UILabel()
                hintLabel.text = hint
                hintLabel.font = .systemFont(ofSize: 12)
                hintLabel.textColor = Theme.textFaint
                hintLabel.numberOfLines = 0
                stack.append(hintLabel)
            }
            stack.append(field)
            let fieldStack = UIStackView(arrangedSubviews: stack)
            fieldStack.axis = .vertical
            fieldStack.spacing = 4
            views.append(fieldStack)
        }
        return card(views, spacing: 12)
    }

    // MARK: - Actions

    @objc private func pickEnvironment(_ sender: UIButton) {
        LiveConfig.shared.setCredential("environment", sender.currentTitle ?? "test")
        syncEnvironmentChips()
    }

    private func syncEnvironmentChips() {
        let current = LiveConfig.shared.environment
        for chip in environmentChips {
            let on = chip.currentTitle == current
            chip.backgroundColor = on ? Theme.accent : Theme.surface
            chip.layer.borderColor = (on ? Theme.accent : Theme.border).cgColor
            chip.setTitleColor(on ? Theme.onAccent : Theme.textDim, for: .normal)
        }
    }

    /// Mid-edit: keep the store live without posting, so screens do not rebuild on every keystroke.
    @objc private func fieldChanged(_ sender: ConfigField) {
        LiveConfig.shared.setCredential(sender.configKey, sender.text ?? "", notify: false)
    }

    /// On blur: post the change, so a screen that captured the value (the card id) rebuilds once.
    @objc private func fieldEnded(_ sender: ConfigField) {
        LiveConfig.shared.setCredential(sender.configKey, sender.text ?? "", notify: true)
        refreshStatus()
    }

    @objc private func refreshStatus() {
        statusLabel.text = LiveConfig.shared.credentialsStatus()
    }

    @objc private func resetAll() {
        LiveConfig.shared.resetCredentials()
        fields.forEach { $0.text = "" }
        syncEnvironmentChips()
        refreshStatus()
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    // MARK: - Styling helpers (the RN example's dark palette)

    private func titleLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 24, weight: .heavy)
        label.textColor = Theme.text
        return label
    }

    private func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = Theme.textDim
        label.numberOfLines = 0
        return label
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = .systemFont(ofSize: 12, weight: .heavy)
        label.textColor = Theme.textFaint
        return label
    }

    private func card(_ views: [UIView], spacing: CGFloat = 12) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.backgroundColor = Theme.surface
        stack.layer.cornerRadius = 20
        stack.layer.borderWidth = 1
        stack.layer.borderColor = Theme.border.cgColor
        return stack
    }

    private func pillButton(_ title: String, color: UIColor, textColor: UIColor, action: Selector) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.setTitleColor(textColor, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        button.backgroundColor = color
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
        button.layer.cornerRadius = 14
        button.addTarget(self, action: action, for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
}

/// A text field that carries the `LiveConfig` key it edits, so one `@objc` handler serves every field.
final class ConfigField: UITextField {
    var configKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 15)
        textColor = Theme.text
        backgroundColor = Theme.surfaceAlt
        autocapitalizationType = .none
        autocorrectionType = .no
        // A JWT is base64url (`-`, `_`) and JSON needs straight quotes; iOS substitution corrupts both
        // into something that still looks right and is rejected by the backend.
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        clearButtonMode = .whileEditing
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = Theme.border.cgColor
        heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private let inset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: inset) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: inset) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: inset) }
}

/// The React Native example's palette, so the Config tab reads as the same product on every platform.
enum Theme {
    static let bg = UIColor(red: 0x0E / 255, green: 0x0E / 255, blue: 0x1A / 255, alpha: 1)
    static let surface = UIColor(red: 0x17 / 255, green: 0x17 / 255, blue: 0x2A / 255, alpha: 1)
    static let surfaceAlt = UIColor(red: 0x1F / 255, green: 0x1F / 255, blue: 0x38 / 255, alpha: 1)
    static let border = UIColor(red: 0x2A / 255, green: 0x2A / 255, blue: 0x47 / 255, alpha: 1)
    static let accent = UIColor(red: 0x57 / 255, green: 0x53 / 255, blue: 0xEA / 255, alpha: 1)
    static let pink = UIColor(red: 0xFF / 255, green: 0x40 / 255, blue: 0x7F / 255, alpha: 1)
    static let green = UIColor(red: 0x3C / 255, green: 0xC6 / 255, blue: 0x5E / 255, alpha: 1)
    static let teal = UIColor(red: 0x57 / 255, green: 0xC9 / 255, blue: 0xF9 / 255, alpha: 1)
    static let text = UIColor.white
    static let textDim = UIColor(red: 0xA0 / 255, green: 0xA0 / 255, blue: 0xC0 / 255, alpha: 1)
    static let textFaint = UIColor(red: 0x6D / 255, green: 0x6D / 255, blue: 0x8A / 255, alpha: 1)
    static let onAccent = UIColor.white
}
