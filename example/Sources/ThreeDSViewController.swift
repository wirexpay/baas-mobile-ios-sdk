import UIKit
import WirexMobileSDK

/// The 3DS step-up, end to end, with the orchestrator URL pasted in.
///
/// A real host takes `three_ds_state.url` from its own `POST /v1/cards/topup/execute` reply. This
/// shows the SDK's part: the origin refusal, the states, the challenge, and the outcome.
final class ThreeDSViewController: UIViewController {

    private let urlField = UITextField()
    private let startButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    /// The SDK's view. Placed at FULL SIZE for the session's whole life and left there — it draws
    /// nothing until a challenge needs the user, and the host must not collapse or fade it.
    private let challengeView = WirexThreeDSView()

    private var session: WirexThreeDSSession?

    /// Rebuilt whenever the Config tab's environment or its Screen capture switch changes: both are
    /// read at construction.
    private var threeDS: WirexThreeDS?
    private var threeDSTestMode: Bool?
    private var threeDSProtectionDisabled: Bool?

    private func currentThreeDS() -> WirexThreeDS {
        let testMode = LiveConfig.shared.isTestMode
        let protectionDisabled = LiveConfig.shared.isScreenProtectionDisabled
        if let threeDS, threeDSTestMode == testMode, threeDSProtectionDisabled == protectionDisabled { return threeDS }
        let fresh = WirexThreeDS(
            testMode: testMode,
            logging: WirexLogging(level: .info, sink: ConsoleLogSink()),
            // DEV/TEST ONLY — the Config tab's Screen capture switch, the same one Reveal and Collect
            // read. Off = the challenge stays visible while the screen is recorded (device clouds).
            dangerouslyDisableScreenProtection: protectionDisabled
        )
        threeDS = fresh
        threeDSTestMode = testMode
        threeDSProtectionDisabled = protectionDisabled
        return fresh
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "3DS"
        view.backgroundColor = .systemBackground
        buildControls()
        buildChallengeHost()
        restyle()
        NotificationCenter.default.addObserver(
            self, selector: #selector(restyle), name: LiveConfig.appearanceDidChange, object: nil
        )
        // A seed link (deep link or the Config tab's field) may carry `threeDsUrl`: prefill the field.
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncFromConfig), name: LiveConfig.credentialsDidChange, object: nil
        )
        syncFromConfig()
        // No snapshot until a session exists.
        statusLabel.text = "no session"
        cancelButton.isEnabled = false

    }

    @objc private func syncFromConfig() {
        let seeded = LiveConfig.shared.credential("threeDsUrl")
        if !seeded.isEmpty, urlField.text != seeded, !urlField.isFirstResponder { urlField.text = seeded }
    }

    /// A run that was given a URL on the command line starts on its own.
    ///
    /// Fires once, for scripted runs. A URL typed into the field still needs the button.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard session == nil, !LaunchArgs.threeDsUrl.isEmpty else { return }
        start()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard traitCollection.userInterfaceStyle != previous?.userInterfaceStyle else { return }
        restyle()
    }

    // MARK: - Layout

    private func buildControls() {
        urlField.placeholder = "three_ds_state.url"
        urlField.text = LaunchArgs.threeDsUrl
        urlField.borderStyle = .roundedRect
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.keyboardType = .URL
        urlField.clearButtonMode = .whileEditing

        startButton.setTitle("Start step-up", for: .normal)
        startButton.addTarget(self, action: #selector(start), for: .touchUpInside)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        statusLabel.numberOfLines = 0
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        let buttons = UIStackView(arrangedSubviews: [startButton, cancelButton])
        buttons.spacing = 16

        let stack = UIStackView(arrangedSubviews: [urlField, buttons, statusLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    /// THE WHOLE SCREEN, for the session's whole life.
    ///
    /// Never collapsed or faded; the SDK hides its own content.
    private func buildChallengeHost() {
        challengeView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(challengeView)
        NSLayoutConstraint.activate([
            challengeView.topAnchor.constraint(equalTo: view.topAnchor),
            challengeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            challengeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            challengeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func restyle() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        challengeView.appearance = LiveConfig.shared.appearance(osIsDark: isDark)
    }

    // MARK: - Driving the step-up

    @objc private func start() {
        diag.tap("Start step-up")
        urlField.resignFirstResponder()
        session?.destroy()

        // Scheme, host and path only — the query carries the session token.
        diag.app("3ds: url \(DiagLog.describe(url: urlField.text ?? "")) protectionDisabled=\(LiveConfig.shared.isScreenProtectionDisabled)")
        let session = currentThreeDS().session(orchestratorUrl: urlField.text ?? "")
        self.session = session
        session.onChange = { [weak self] snapshot in self?.render(snapshot) }
        challengeView.bind(session)
        session.start()
    }

    @objc private func cancel() {
        diag.tap("Cancel")
        session?.cancel()
    }

    private func render(_ snapshot: WirexThreeDSSnapshot) {
        // `cancel()` does nothing once the session has settled, so the button is disabled then.
        cancelButton.isEnabled = snapshot.state != .settled
        startButton.setTitle(snapshot.state == .settled ? "Start another" : "Start step-up", for: .normal)

        var lines = ["state: \(snapshot.state.rawValue)"]
        if let outcome = snapshot.outcome {
            lines.append("status: \(outcome.status.wireStatus)")
            if let error = outcome.error {
                lines.append("code: \(error.code.wireCode)")
                lines.append("retryable: \(error.retryable)")
                if let message = error.message { lines.append("message: \(message)") }
            } else {
                // A dismissal carries no error.
                lines.append("error: none")
            }
        }
        statusLabel.text = lines.joined(separator: "\n")
        diag.sdk("3ds: " + lines.joined(separator: " "))
    }
}
