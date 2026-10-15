import UIKit
import WirexMobileSDK

/// Native iOS integration of the card-reveal SDK.
///
/// UIKit rather than SwiftUI, because the SDK's row IS a `UIView` — a SwiftUI host would wrap it in
/// `UIViewRepresentable` and add a layer that obscures what is being demonstrated. A SwiftUI app
/// integrates the same way, through that wrapper.
///
/// What this screen is for:
///
///  - the composite rows the SDK draws: label, sealed value, and its own copy button
///  - masked by default, with an explicit reveal
///  - light/dark theme resolution, and host tokens overriding it
///  - the partial-failure rule: under scenario `cvv_fails` the CVV row shows its placeholder while
///    the session stays ready, because the PAN did load
///  - capture-protection state, reported per row
///
/// What it deliberately cannot do, and no amount of example code would change: read a value back.
/// There is no accessor, and no programmatic copy.
final class RevealViewController: UIViewController {
    private var borders = BorderedViews()

    /// Borders drawn with a dynamic colour have to be re-resolved by hand; see `BorderedViews`.
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        borders.refresh()
    }


    /// Keeps the focused field above the keyboard. Shared with the collect screen — its first version
    /// lived here and looked for the focused field in a hard-coded list of text views, which a card
    /// field could never be in.
    private var keyboardAvoider: KeyboardAvoider?

    private let credentials = HostCredentialProvider()
    /// Nil when no environment is configured to talk to; `unavailable` then says why.
    private lazy var reveal: WirexReveal? = {
        switch Self.configuredEnvironment() {
        case .failure(let reason):
            unavailable = reason
            return nil
        case .success(let environment):
            return makeReveal(environment)
        }
    }()

    private var unavailable: WirexEnvironmentUnavailable?

    private func makeReveal(_ environment: WirexEnvironment) -> WirexReveal {
        WirexReveal(
        // The environment is a NAME (e.g. "test" / "production"); the SDK resolves it to the
        // endpoints it ships with. The app passes a name, never a URL.
        environment: environment,
        credentials: credentials,
        // Diagnostics at INFO in this example (OFF by default in the SDK), written to the platform's
        // unified log — the collect screen passes its own sink to show the other half. Everything a
        // sink receives has already been through the redactor; the level gate runs before the sink, so
        // nothing reaches here that the level did not permit. Values and tokens are never among the fields.
        logging: osLogLogging(level: .info)
        )
    }

    /// The SDK, once `viewDidLoad` has established there is one. Every call site below runs only
    /// after that guard, so the force-unwrap is a statement about control flow rather than a risk.
    private func requireReveal() -> WirexReveal {
        guard let reveal else { preconditionFailure("reached without an environment") }
        return reveal
    }

    private var session: WirexRevealSession?
    private var rows: [WirexRevealField: WirexRevealFieldView] = [:]

    private let rowStack = UIStackView()
    private let credentialsField = UITextView()
    private let credentialsStatus = UILabel()
    private let statusLabel = UILabel()
    private let scrollView = UIScrollView()


    /// What the live session was built from, so a re-apply can tell whether it is stale.
    private var sessionIdentity = ""

    private var isMasked = true

    /// Resolved from the compiled-in config name, or a reason it could not be.
    ///
    /// NOT a crash. That was the right answer while the only failure was a typo in the config —
    /// reaching production by accident, or looking like a working integration while reaching
    /// nothing, are both worse than stopping. It is the wrong answer now that a second failure
    /// exists and is the NORMAL state of a fresh example: no environment has been configured yet, so
    /// an example built from a clone resolves none until you set one. Dying on launch teaches a
    /// partner nothing; the screen says which of the two happened instead.
    private static func configuredEnvironment() -> Result<WirexEnvironment, WirexEnvironmentUnavailable> {
        do {
            return .success(try WirexEnvironment.resolve(
                WirexSdkConfig.environment,
                chainId: LiveConfig.shared.credential("chainId")
            ))
        } catch let unavailable as WirexEnvironmentUnavailable {
            return .failure(unavailable)
        } catch {
            return .failure(.unknownName(name: WirexSdkConfig.environment, known: WirexEnvironment.allNames))
        }
    }

    /// What the screen shows instead of itself when there is no environment to talk to.
    private func unavailableView(_ unavailable: WirexEnvironmentUnavailable) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.layoutMargins = UIEdgeInsets(top: 24, left: 16, bottom: 16, right: 16)
        stack.isLayoutMarginsRelativeArrangement = true

        let title = UILabel()
        title.text = "Reveal — unavailable"
        title.font = .preferredFont(forTextStyle: .headline)

        let detail = UILabel()
        detail.numberOfLines = 0
        detail.font = .preferredFont(forTextStyle: .footnote)
        switch unavailable {
        case .notBuilt(let name, _):
            detail.text = "The SDK has no configuration for '\(name)'.\n"
                + "Set the environment Wirex assigned (test / production)."
        case .unknownName(let name, let known):
            detail.text = "wirex-card-sdk.json names '\(name)', which is not one of "
                + known.joined(separator: ", ")
        case .malformedEndpoints(let name):
            detail.text = "The SDK could not resolve valid endpoints for '\(name)'."
        case .missingChainId(let name):
            detail.text = "No chain id for '\(name)'. Supply `chainId` in the credentials JSON."
        }

        let note = UILabel()
        note.numberOfLines = 0
        note.font = .preferredFont(forTextStyle: .caption1)
        note.textColor = .secondaryLabel
        note.text = "The SDK could not resolve this environment. Check the environment name it was "
            + "given (test / production)."

        [title, detail, note].forEach(stack.addArrangedSubview)
        return stack
    }

    /// `cardholderName` is not sensitive and is not fetched — the host already has it.
    private let fields: [WirexRevealField] = [.cardholderName, .pan, .expiry, .cvv, .pin]

    /// A real card belonging to the token's user. Pasted into the app (the "credentials" box).
    private var cardId: String { LiveConfig.shared.credential("cardId") }

    /// Launch arguments, so the example can be driven by a script.
    ///
    /// Tapping cannot be automated from `simctl`, and a smoke test that only ever sees the first
    /// frame verifies almost nothing. These let a UI test drive the screen on launch.
    ///
    ///     xcrun simctl launch <udid> com.wirexapp.baas.example -wirexAutoLoad -wirexReveal
    ///
    ///   -wirexAutoLoad     call load() once the session exists
    ///   -wirexReveal       unmask after loading
    ///   -wirexTheme dark   start in dark mode
    private enum LaunchOption {
        static let all = ProcessInfo.processInfo.arguments
        static var autoLoad: Bool { all.contains("-wirexAutoLoad") }
        static var reveal: Bool { all.contains("-wirexReveal") }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // Resolved BEFORE anything is built. A checkout has no endpoints — that is the shape of this
        // repository, not a fault — and the screen has to say so rather than die or draw rows that
        // cannot load.
        guard reveal != nil else {
            let message = unavailableView(unavailable ?? .notBuilt(name: WirexSdkConfig.environment, variables: []))
            message.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(message)
            NSLayoutConstraint.activate([
                message.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                message.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                message.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            return
        }

        buildLayout()
        installKeyboardHandling()
        createSession()

        if LaunchOption.autoLoad {
            Task {
                await runLoad()
                if LaunchOption.reveal { applyMask(false) }
            }
        }
    }

    // MARK: - Keyboard

    /// Keeps the JSON fields above the keyboard, and gives the user a way to dismiss it.
    ///
    /// Neither is optional here. The fields are `UITextView`s, which have no return key to end
    /// editing, so without a dismissal gesture the keyboard is stuck up for the rest of the run —
    /// and the whole point of these panels is pasting a fresh `action_token` into a field you can
    /// see. There was no keyboard handling at all before.
    private func installKeyboardHandling() {
        scrollView.keyboardDismissMode = .onDrag

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        // Otherwise the gesture swallows taps meant for the buttons inside the scroll view.
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)

        keyboardAvoider = KeyboardAvoider(scrollView: scrollView, root: view)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: LiveConfig.appearanceDidChange,
            object: nil
        )
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    /// A restyle only: it must never change `isMasked`, re-fetch, or reveal.
    @objc private func appearanceDidChange() {
        restyle()
    }

    // MARK: - Session

    private func createSession() {
        rows.values.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        rowStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        sessionIdentity = "\(cardId)|" + LiveConfig.shared.credential("cardholderName")
        // `session` now rejects a blank cardId for every surface, native included — so the example
        // has to say so rather than showing four rows that will fail one request later.
        let created: WirexRevealSession
        do {
            created = try requireReveal().session(
                cardId: cardId,
                fields: fields,
                // Host-supplied, never fetched: a real host already has it from the card list it rendered.
                cardholderName: LiveConfig.shared.credential("cardholderName")
            )
        } catch {
            session = nil
            let code = (error as? WirexError)?.code.rawValue ?? "unknown"
            statusLabel.text = "no session — \(code). Paste a cardId in Credentials (JSON)."
            flash("cardId is required")
            return
        }
        created.onChange = { [weak self] snapshot in
            // A snapshot can change on any thread — a background clear, for instance.
            DispatchQueue.main.async { self?.renderStatus(snapshot) }
        }
        session = created

        for field in fields {
            let row = WirexRevealFieldView()
            row.bind(session: created, field: field, strings: strings, appearance: currentAppearance())
            // This app's tabs detach the screen rather than hide it, and the user is coming straight
            // back — so a detach here is not a hand-off to anyone, and re-masking would make them
            // reveal again for no gain. A list recycling rows would leave this at its default.
            row.masksWhenDetached = false
            row.onCopy = { [weak self] copied in
                // Only ever a boolean. The value is not in this callback and cannot be.
                self?.flash(copied ? "Copied \(field.rawValue)" : "Copy refused")
            }
            row.onRevealRefused = { [weak self] in
                self?.isMasked = true
                self?.flash("Reveal refused — the screen is being captured or the row is off screen")
                if let snapshot = self?.session?.snapshot { self?.renderStatus(snapshot) }
            }
            row.mask()
            rows[field] = row
            rowStack.addArrangedSubview(row)
        }
        renderStatus(created.snapshot)
    }

    private func load() {
        Task { await runLoad() }
    }

    /// Loads, and reports the two outcomes `load()` throws rather than publishes.
    ///
    /// A failure to fetch is in the snapshot. What `load()` throws is a stop: the user declined the
    /// action-token prompt, or the task was cancelled. The snapshot is already settled when it does.
    private func runLoad() async {
        guard let session else { return }
        do {
            try await session.load()
        } catch is WirexDeclined {
            flash("Declined — the reveal was abandoned")
        } catch {
            // Cancelled: nothing to report.
        }
        renderStatus(session.snapshot)
    }

    private func applyMask(_ masked: Bool) {
        isMasked = masked
        rows.values.forEach { masked ? $0.mask() : $0.reveal() }
        if let snapshot = session?.snapshot { renderStatus(snapshot) }
    }

    /// Rebuilds the session when a credential the session CAPTURED has changed.
    ///
    /// Deliberately not unconditional: a rebuild drops loaded values and re-masks, so doing it for
    /// a pasted `actionToken` — read lazily and therefore already live — would throw away work for
    /// nothing.
    private func recreateSessionIfIdentityChanged() {
        let identity = "\(LiveConfig.shared.credential("cardId"))|"
            + LiveConfig.shared.credential("cardholderName")
        guard identity != sessionIdentity else { return }
        sessionIdentity = identity
        createSession()
        flash("session rebuilt — cardId or cardholderName changed")
    }

    /// Restyles from whatever `LiveConfig` currently holds.
    ///
    /// Separate from `applyTheme` on purpose, and the separation is load-bearing: a notification
    /// handler that calls `applyTheme` SETS the selection, which posts the notification again, so
    /// tapping a preset recurses until the stack runs out.
    private func restyle() {
        let resolved = currentAppearance()
        rows.values.forEach { $0.setAppearance(resolved) }
        if let snapshot = session?.snapshot { renderStatus(snapshot) }
    }

    // MARK: - Presentation

    /// Every string the SDK draws comes from here.
    ///
    /// The SDK ships no locale packs on purpose: a card SDK must not invent English copy, least of
    /// all copy a screen reader reads aloud. A real app would pull these from its own catalogue.
    private let strings = WirexRevealStrings(
        fieldLabels: [
            .cardholderName: "Cardholder",
            .pan: "Card number",
            .expiry: "Expires",
            .cvv: "CVV",
            .pin: "PIN",
        ],
        maskedPlaceholder: "••••",
        copy: "Copy",
        copied: "Copied",
        accessibilityShown: "shown",
        accessibilityHidden: "hidden",
        loadError: "Could not load card details"
    )

    /// The theme mode picks every colour default; the two tokens here override it.
    ///
    /// Supplying a partial set is the normal case, and the reason resolution works this way — a host
    /// never has to enumerate the tokens it does not care about.
    /// The host picks; the SDK draws what it is given.
    private func currentAppearance() -> WirexAppearance {
        LiveConfig.shared.appearance(osIsDark: traitCollection.userInterfaceStyle == .dark)
    }

    private func renderStatus(_ snapshot: WirexRevealSnapshot) {
        let protection = rows.values.first?.isScreenshotProtectionActive
        let loaded = snapshot.loaded.map(\.rawValue).sorted()
        let failed = snapshot.failed.map(\.rawValue).sorted()
        statusLabel.text = """
        state: \(snapshot.state)
        loaded: \(loaded.isEmpty ? ["—"] : loaded)
        failed: \(failed.isEmpty ? ["—"] : failed)
        masked: \(isMasked)   capture-protected: \(protection.map(String.init) ?? "unknown")
        """
    }

    private func flash(_ message: String) {
        let banner = UILabel()
        banner.text = "  \(message)"
        banner.font = .systemFont(ofSize: 13)
        banner.textColor = .white
        banner.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            banner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            banner.heightAnchor.constraint(equalToConstant: 32),
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { banner.removeFromSuperview() }
    }

    // MARK: - Layout

    private func buildLayout() {
        let title = UILabel()
        title.text = "Wirex card reveal — native iOS"
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let subtitle = UILabel()
        subtitle.text = "Values are fetched and drawn by the SDK. This app cannot read them."
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0

        rowStack.axis = .vertical
        rowStack.spacing = 8

        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .secondaryLabel

        let controls = UIStackView(arrangedSubviews: [
            buttonRow([("Load", { [weak self] in self?.load() }),
                       ("Reveal", { [weak self] in self?.applyMask(false) }),
                       ("Mask", { [weak self] in self?.applyMask(true) })]),
            buttonRow([("Clear", { [weak self] in
                            self?.session?.clear()
                            if let snapshot = self?.session?.snapshot { self?.renderStatus(snapshot) }
                        }),
                       ("New session", { [weak self] in
                            self?.createSession()
                            self?.refreshCredentialsStatus()
                        }),
                       ("Decline next", { [weak self] in
                            self?.credentials.declineNextActionToken = true
                            self?.flash("The next action-token will be declined")
                        })]),
        ])
        controls.axis = .vertical
        controls.spacing = 8

        let content = UIStackView(arrangedSubviews: [
            title, subtitle, rowStack, statusLabel, controls,
            buildCredentialsPanel(),
        ])
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32),
            content.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])
    }

    // MARK: - Runtime configuration panels

    /// A header that shows and hides its body. Collapsed by default: this is operator plumbing, and
    /// the point of the screen is the rows above it.
    private func buildPanel(title: String, body: UIView) -> UIView {
        body.isHidden = true
        let header = ClosureButton(title: "▸ \(title)") { }
        header.contentHorizontalAlignment = .leading
        header.onTap = { [weak header] in
            body.isHidden.toggle()
            header?.setTitle("\(body.isHidden ? "▸" : "▾") \(title)", for: .normal)
        }

        let panel = UIStackView(arrangedSubviews: [header, body])
        panel.axis = .vertical
        panel.spacing = 8
        return panel
    }

    private func textArea(_ placeholder: String) -> UITextView {
        let view = UITextView()
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        borders.track(view)
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.text = placeholder
        view.heightAnchor.constraint(equalToConstant: 96).isActive = true
        return view
    }

    /// Paste any subset of the keys. Absent keys keep their current values, so an expired
    /// `actionToken` is replaced by pasting only that one — no rebuild, nothing else disturbed.
    private func buildCredentialsPanel() -> UIView {
        credentialsField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        borders.track(credentialsField)
        credentialsField.autocorrectionType = .no
        credentialsField.autocapitalizationType = .none
        // SECURITY-adjacent: iOS substitutes curly quotes and en/em dashes by default. A JWT is
        // base64url — it contains `-` and `_` — and JSON needs straight quotes, so leaving these on
        // lets an edit silently corrupt a pasted credential into something that still parses as
        // JSON but is rejected by the backend as an invalid token.
        credentialsField.smartQuotesType = .no
        credentialsField.smartDashesType = .no
        credentialsField.smartInsertDeleteType = .no
        credentialsField.text = #"{ "actionToken": "" }"#
        credentialsField.heightAnchor.constraint(equalToConstant: 110).isActive = true

        credentialsStatus.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        credentialsStatus.numberOfLines = 0
        credentialsStatus.textColor = .secondaryLabel
        refreshCredentialsStatus()

        let hint = UILabel()
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 0
        hint.text = "keys: bearer · email · wallet · cardId · actionToken · cardholderName — merged, absent kept"

        let apply = ClosureButton(title: "Apply credentials") { [weak self] in
            guard let self else { return }
            switch LiveConfig.shared.applyCredentials(json: self.credentialsField.text) {
            case .merged(let summary):
                self.flash(summary)
                self.refreshCredentialsStatus()
                // A session captures `cardId` and `cardholderName` at creation; only the bearer and
                // the action token are read lazily per call. So pasting a corrected card id and
                // pressing Load kept using the OLD one — the request went to `/v1/cards//details`
                // and pan, expiry and cvv all failed, while the panel showed fresh credentials.
                // Rebuilding here is what "apply" has to mean.
                self.recreateSessionIfIdentityChanged()
            case .rejected(let reason):
                self.flash("credentials: \(reason)")
            }
        }

        let body = UIStackView(arrangedSubviews: [hint, credentialsField, apply, credentialsStatus])
        body.axis = .vertical
        body.spacing = 8
        return buildPanel(title: "Credentials (JSON)", body: body)
    }

    private func refreshCredentialsStatus() {
        credentialsStatus.text = LiveConfig.shared.credentialsStatus()
    }

    /// `UIAction` is iOS 14+, and this example builds against the SDK's iOS 13 floor — the same
    /// constraint that made the SDK grow its own `ClosureButton`.
    private func buttonRow(_ actions: [(String, () -> Void)]) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        for (title, action) in actions {
            stack.addArrangedSubview(ClosureButton(title: title, action: action))
        }
        return stack
    }
}


/// Target/action rather than `addAction(_:for:)`, which is iOS 14+.
private final class ClosureButton: UIButton {
    /// Mutable so a panel header can rebind its own toggle after construction.
    var onTap: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.onTap = action
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 12)
        setTitleColor(.systemBlue, for: .normal)
        addTarget(self, action: #selector(fire), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    @objc private func fire() { onTap() }
}
