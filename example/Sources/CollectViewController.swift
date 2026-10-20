import UIKit
import WirexMobileSDK

/// The card-ENTRY screen: the mirror of `RevealViewController`.
///
/// What it is here to demonstrate, in order of importance:
///
/// 1. **No API returns what the user typed.** Nothing on the form or the field hands the value to
///    the host — the boundary is the public API, not the object graph.
/// 2. **Live state without content.** Every keystroke reports validity, touched-ness and the scheme.
///    That is all a real Continue button needs.
/// 3. **Tokenisation.** The entered card goes straight to the card service and what comes back is an
///    opaque id plus BIN and last four — out of PCI scope by construction.
///
/// Credentials come from `LiveConfig`, shared with the reveal screen: paste a bearer once and both
/// screens use it.
final class CollectViewController: UIViewController {
    private var borders = BorderedViews()

    /// Borders drawn with a dynamic colour have to be re-resolved by hand; see `BorderedViews`.
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        borders.refresh()
    }


    /// Keeps the focused field above the keyboard. The collect screen had none at all — a card field
    /// below the fold scrolled under the keyboard and stayed there.
    private var keyboardAvoider: KeyboardAvoider?
    private let credentials = HostCredentialProvider()
    private var collect: WirexCollect?
    private var form: WirexCollectForm?
    private var profile: WirexCollectProfile = .topup

    /// Which of the three error-line policies the form is using. Switchable, to see the difference.
    private var errorLine: WirexErrorLine = .animated
    private let errorLines = UISegmentedControl(items: ["animated", "reserved", "hidden"])

    /// Every string the form draws, read from the JSON document below.
    ///
    /// A partner integrating this has its own translation store, so the SDK takes a document rather
    /// than a table of Swift constants — the same shape the appearance panel takes.
    private var strings = WirexCollectStrings.fromJson(CollectViewController.defaultStringsJson)
        ?? WirexCollectStrings()
    private let stringsField = UITextView()

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let formHolder = UIView()
    private let stateLabel = UILabel()
    private let resultLabel = UILabel()
    private var tokenizeButton = UIButton(type: .system)
    private let profiles = UISegmentedControl(items: ["topup", "oct-destination"])
    /// The environment + chain id the form was built for. Only those are read when it is built; the
    /// bearer is read per call, so a pasted token must not clear a half-typed card.
    private var lastConfigKey = ""
    private var currentConfigKey: String { LiveConfig.shared.environment + "|" + LiveConfig.shared.credential("chainId") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Collect"
        view.backgroundColor = .systemBackground
        buildLayout()
        keyboardAvoider = KeyboardAvoider(scrollView: scroll, root: view)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: LiveConfig.appearanceDidChange,
            object: nil
        )
        // The environment or chain id changed on the Config tab: rebuild the form so the fresh
        // connection takes effect. A rebuild clears what is typed, which is honest here — the
        // connection the form talks over has changed. A pasted bearer does NOT rebuild.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(credentialsDidChange),
            name: LiveConfig.credentialsDidChange,
            object: nil
        )
        scroll.keyboardDismissMode = .interactive
        rebuildForm()
    }

    @objc private func credentialsDidChange() {
        guard currentConfigKey != lastConfigKey else { return }
        rebuildForm()
    }

    private var hasFocusedOnce = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Focus the first field on first appearance. An example convenience, not SDK behaviour — but
        // it is also the cheapest proof that a `UIKeyInput` view raises the keyboard at all, which is
        // the load-bearing question about this whole approach.
        guard !hasFocusedOnce else { return }
        hasFocusedOnce = true
        form?.focusFirstIncompleteField()
    }

    // ── The SDK ─────────────────────────────────────────────────────────────────

    private func rebuildForm() {
        lastConfigKey = currentConfigKey
        // A fresh instance per rebuild, because the environment name and the credentials can change
        // between rebuilds. The same reason the reveal screen rebuilds its session on Apply.
        // `resolve` rather than `named`, because the two failures behind a nil are fixed in
        // different places and the message already distinguishes them: a name outside the closed set
        // is this file's mistake, a known name the SDK has no endpoints for is a configuration issue.
        let environment: WirexEnvironment
        do {
            environment = try WirexEnvironment.resolve(
                LiveConfig.shared.environment,
                chainId: LiveConfig.shared.credential("chainId")
            )
        } catch let unavailable as WirexEnvironmentUnavailable {
            resultLabel.text = String(describing: unavailable)
            return
        } catch {
            resultLabel.text = "Unknown environment '\(LiveConfig.shared.environment)'"
            return
        }
        let collect = WirexCollect(
            environment: environment,
            credentials: credentials,
            // A HOST sink: diagnostics land in this app's own console instead of the unified log.
            // The reveal screen leaves it out and gets the platform default — both are supported.
            logging: WirexLogging(level: .info, sink: ConsoleLogSink())
        )
        self.collect = collect

        form?.removeFromSuperview()
        let form = collect.form(
            profile: profile,
            appearance: LiveConfig.shared.appearance(osIsDark: traitCollection.userInterfaceStyle == .dark),
            // Every string the form draws, supplied by the host. The SDK ships no locale packs, so
            // this is the integration a partner actually performs — the defaults exist only so a form
            // that supplies nothing still renders.
            strings: strings
        )
        form.errorLine = errorLine
        form.onChange = { [weak self] state in self?.render(state) }
        // Moving between fields while the keyboard is already up fires no keyboard notification, so
        // this is the only thing that tells the screen to scroll the new field into view.
        form.onFocusedFieldChanged = { [weak self] _ in self?.keyboardAvoider?.focusDidChange() }
        form.translatesAutoresizingMaskIntoConstraints = false
        formHolder.addSubview(form)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: formHolder.topAnchor),
            form.bottomAnchor.constraint(equalTo: formHolder.bottomAnchor),
            form.leadingAnchor.constraint(equalTo: formHolder.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: formHolder.trailingAnchor),
        ])
        self.form = form
        render(form.state)
    }

    private func render(_ state: WirexCollectState) {
        let perField = state.fields.map { field -> String in
            let mark = field.isValid ? "ok" : (field.isEmpty ? "empty" : "invalid")
            let touched = field.isTouched ? "" : " (untouched)"
            return "\(field.field.rawValue): \(mark)\(touched)"
        }
        stateLabel.text = """
        complete: \(state.isComplete)
        brand: \(state.brand.rawValue)
        \(perField.joined(separator: "\n"))
        """
        tokenizeButton.isEnabled = state.isComplete && !(form?.isSubmitting ?? false)
        tokenizeButton.alpha = tokenizeButton.isEnabled ? 1 : 0.4
    }

    // ── Actions ─────────────────────────────────────────────────────────────────

    /// Switches the policy on the LIVE form — no rebuild, so what is typed survives.
    @objc private func switchErrorLine(_ sender: UISegmentedControl) {
        errorLine = [.animated, .reserved, .hidden][sender.selectedSegmentIndex]
        form?.errorLine = errorLine
    }

    @objc private func switchProfile(_ sender: UISegmentedControl) {
        profile = sender.selectedSegmentIndex == 0 ? .topup : .octDestination
        resultLabel.text = "—"
        rebuildForm()
    }

    @objc private func tokenize() {
        guard let form else { return }
        resultLabel.text = "submitting…"
        tokenizeButton.isEnabled = false

        Task { @MainActor in
            do {
                switch profile {
                case .topup:
                    // A real host collects these in its own UI: a billing address is not card data and
                    // is outside the sealed surface on purpose.
                    let token = try await form.tokenizeTopUp(
                        WirexTopUpTokenizeParams(
                            billingDetails: WirexBillingDetails(
                                line1: "1 Example Street",
                                zipCode: "SW1A 1AA",
                                city: "London",
                                country: "GB"
                            ),
                            label: nil
                        )
                    )
                    resultLabel.text = """
                    linked
                    cardId: \(token.cardId)
                    \(token.brand.rawValue) •••• \(token.last4)  bin \(token.bin)
                    expiry: \(token.expiryMonth)/\(token.expiryYear)
                    """
                case .octDestination:
                    let token = try await form.tokenizeOctDestination(
                        WirexOctTokenizeParams(
                            cardLabel: "Example recipient",
                            isSaved: false,
                            isThirdParty: true
                        )
                    )
                    resultLabel.text = """
                    registered
                    externalCardId: \(token.externalCardId)
                    \(token.brand.rawValue) •••• \(token.last4)  bin \(token.bin)
                    """
                }
            } catch let error as WirexError {
                // The WHOLE error, not `code` and `retryable` picked out of it.
                //
                // `detail` is SPI — a host cannot branch on it, deliberately — but `description`
                // carries it, and that is the difference between "failed" and "the service rejected
                // the request" (`badRequest`) or "the connection died" (`transport`). Printing two
                // fields threw away the one that says which, and a screen that reports a failure
                // without saying what kind sends whoever is integrating to a packet capture.
                resultLabel.text = "failed: \(error)"
            } catch {
                resultLabel.text = "failed"
            }
            render(form.state)
        }
    }

    /// The wording document, applied live.
    ///
    /// Rebuilds the form, because labels and placeholders are read when a row is built — which also
    /// clears what is typed. That is honest: a host changing its LOCALE mid-form is not a case worth
    /// pretending about, and the SDK's own restyle path (the Appearance tab) is the one that must
    /// preserve input.
    @objc private func applyStrings() {
        guard let parsed = WirexCollectStrings.fromJson(stringsField.text) else {
            resultLabel.text = "strings: not valid JSON"
            return
        }
        strings = parsed
        rebuildForm()
        resultLabel.text = "strings applied — the form was rebuilt"
    }

    @objc private func resetStrings() {
        stringsField.text = Self.defaultStringsJson
        applyStrings()
    }

    @objc private func clearForm() {
        form?.clear()
        resultLabel.text = "—"
    }

    // ── Keyboard shortcuts, for driving this harness ─────────────────────────────
    //
    // Example code, not SDK behaviour. A scripted run on a simulator has a hardware keyboard and no
    // reliable way to synthesise a tap, and a human debugging with a keyboard attached gets the same
    // affordance for free.

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "t", modifierFlags: .command, action: #selector(tokenize),
                         discoverabilityTitle: "Tokenize"),
            UIKeyCommand(input: "k", modifierFlags: .command, action: #selector(clearForm),
                         discoverabilityTitle: "Clear"),
            UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(focusNext),
                         discoverabilityTitle: "Focus the next incomplete field"),
            UIKeyCommand(input: "1", modifierFlags: .command, action: #selector(selectTopup),
                         discoverabilityTitle: "Profile: topup"),
            UIKeyCommand(input: "2", modifierFlags: .command, action: #selector(selectOct),
                         discoverabilityTitle: "Profile: oct-destination"),
        ]
    }

    /// A restyle, not a rebuild. Rebuilding would drop what the user has typed, which is the one
    /// thing an appearance change must never do.
    @objc private func appearanceDidChange() {
        form?.apply(appearance: LiveConfig.shared.appearance(osIsDark: traitCollection.userInterfaceStyle == .dark))
    }

    @objc private func focusNext() { form?.focusFirstIncompleteField() }

    @objc private func selectTopup() { setProfile(.topup) }
    @objc private func selectOct() { setProfile(.octDestination) }

    private func setProfile(_ next: WirexCollectProfile) {
        guard profile != next else { return }
        profile = next
        profiles.selectedSegmentIndex = next == .topup ? 0 : 1
        resultLabel.text = "—"
        rebuildForm()
    }

    // ── Layout ──────────────────────────────────────────────────────────────────

    private func buildLayout() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32),
        ])

        profiles.selectedSegmentIndex = 0
        profiles.addTarget(self, action: #selector(switchProfile(_:)), for: .valueChanged)
        stack.addArrangedSubview(profiles)

        errorLines.selectedSegmentIndex = 0
        errorLines.addTarget(self, action: #selector(switchErrorLine(_:)), for: .valueChanged)
        stack.addArrangedSubview(errorLines)
        stack.addArrangedSubview(caption(
            "Error line: ANIMATED keeps the form compact and slides a message in — everything below "
                + "it moves. RESERVED keeps a line's height always, so nothing ever moves and the "
                + "form is taller. HIDDEN draws none, for a host rendering its own from onChange."
        ))

        stack.addArrangedSubview(heading("The sealed form"))
        formHolder.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(formHolder)

        stack.addArrangedSubview(heading("Reported state — no content"))
        stateLabel.numberOfLines = 0
        stateLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        stateLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(stateLabel)

        tokenizeButton = button("Tokenize", #selector(tokenize))
        stack.addArrangedSubview(tokenizeButton)
        stack.addArrangedSubview(button("Clear", #selector(clearForm)))

        stack.addArrangedSubview(heading("Result"))
        resultLabel.numberOfLines = 0
        resultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultLabel.text = "—"
        stack.addArrangedSubview(resultLabel)

        // Test cards, so the screen is usable without hunting for a valid number.
        //
        // SEVERAL of them, and the caption says why: the card service links a number to an account
        // ONCE. A second attempt with the same number is a 400 — `detail: badRequest` — and reads
        // exactly like a broken integration. With one number here, the first person to run the
        // example twice concludes the SDK is broken; `4242 4242 4242 4242` in particular is the
        // number everyone reaches for, so on any account that has seen a demo it is already spent.
        //
        // Fields rather than labels, because they have to be COPYABLE: there is no API to set a
        // sealed field's value, which is the point of the surface, so the only way in is a paste.
        stack.addArrangedSubview(heading("Test cards"))
        stack.addArrangedSubview(caption(
            "Copy one, then long-press the card number field and paste. Pasting goes through the "
                + "same filter a keystroke does — separators are dropped and an over-long paste is "
                + "truncated."
        ))
        for number in Self.testCardNumbers {
            let field = UITextField()
            field.text = number
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.borderStyle = .roundedRect
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            // Same reason as the JSON fields below: iOS rewrites a pasted `-` into an en dash, and a
            // card number that has been through that fails the digit filter.
            field.smartDashesType = .no
            field.smartQuotesType = .no
            field.smartInsertDeleteType = .no
            stack.addArrangedSubview(field)
        }
        stack.addArrangedSubview(caption(
            "Visa and Mastercard test numbers. Expiry: any future MM/YY. CVV: any 3 digits.\n\n"
                + "ONE LINK PER NUMBER PER ACCOUNT. Tokenising a number this account has already "
                + "linked fails with detail badRequest — the service says the card belongs to "
                + "another account, and the SDK does not pass backend text through. Move to the next "
                + "number rather than debugging the failure."
        ))

        // Credentials and identity are entered on the Config tab now, shared by every surface.

        // LAST, below everything. It is a tall editor for a thing most runs never touch, and
        // anywhere higher it pushes the form — the actual subject of the screen — off the
        // first screenful.
        stack.addArrangedSubview(heading("Strings (JSON)"))
        stack.addArrangedSubview(caption(
            "labels · placeholders · errors[field|\"*\"][incomplete|invalid|expired]. A null "
                + "suppresses that message; an absent key falls through to the SDK's own English. "
                + "Shape and precedence are fixed by the SDK."
        ))
        stringsField.text = Self.defaultStringsJson
        stringsField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        borders.track(stringsField)
        stringsField.autocorrectionType = .no
        stringsField.autocapitalizationType = .none
        // iOS rewrites `-` into an en dash inside pasted text, and a JSON document survives that only
        // by luck.
        stringsField.smartQuotesType = .no
        stringsField.smartDashesType = .no
        stringsField.smartInsertDeleteType = .no
        stringsField.heightAnchor.constraint(equalToConstant: 180).isActive = true
        stack.addArrangedSubview(stringsField)
        stack.addArrangedSubview(button("Apply strings", #selector(applyStrings)))
        stack.addArrangedSubview(button("Reset strings", #selector(resetStrings)))
    }

    /// Deliberately NOT the SDK's own wording, so the screen proves the hook is live rather than that
    /// it exists. The wildcard row is the shape most hosts want: one sentence per reason.
    fileprivate static let defaultStringsJson = """
    {
      "labels": {
        "number": "Card number", "expiry": "Expires", "cvv": "CVV", "name": "Cardholder"
      },
      "errors": {
        "*": {
          "incomplete": "Finish this field — it is incomplete",
          "invalid": "That does not look right",
          "expired": "That card has expired"
        },
        "number": { "invalid": "Check the card number and try again" }
      }
    }
    """

    /// Enough numbers that running the example a few times does not exhaust them.
    ///
    /// All standard scheme test numbers, so they pass the Luhn check the number field runs and
    /// detect as the brand shown beside the field.
    private static let testCardNumbers = [
        "4242 4242 4242 4242",
        "4111 1111 1111 1111",
        "4000 0566 5566 5556",
        "5555 5555 5555 4444",
    ]

    private func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        return label
    }

    private func heading(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    private func button(_ title: String, _ action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.contentHorizontalAlignment = .leading
        return button
    }
}
