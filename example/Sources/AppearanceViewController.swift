import UIKit
import WirexMobileSDK

/// One place to restyle every field on both surfaces.
///
/// Appearance is a tab of its own and applies to BOTH surfaces: both screens listen for
/// `LiveConfig.appearanceDidChange`, so a preset or a pasted document lands everywhere at once. That
/// is also the invariant worth watching here — restyling must not clear what is typed into the
/// collect form, and must not unmask a reveal row.
///
/// Presets are hardcoded on purpose. They are the fastest way to see the token vocabulary do something
/// visible, and each one is chosen to exercise a group of tokens rather than to look nice.
final class AppearanceViewController: UIViewController {
    private var borders = BorderedViews()

    /// Borders drawn with a dynamic colour have to be re-resolved by hand; see `BorderedViews`.
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        borders.refresh()
        // The device changed appearance, so the document does too.
        //
        // Swapped HERE, by the host. That is the point of handing the SDK one appearance rather than
        // two: an application with a design system knows the theme changed and supplies the palette
        // for it. The SDK resolves no theme.
        if traitCollection.userInterfaceStyle != previous?.userInterfaceStyle,
           let activePreset {
            writeAndApply(activePreset)
        }
    }


    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let appearanceField = UITextView()

    /// The preset whose document is in the field, so a theme change can re-write it. Nil once
    /// someone types their own — a theme change must not overwrite what they just wrote.
    private var activePreset: Preset?
    private let status = UILabel()
    private var keyboardAvoider: KeyboardAvoider?

    // ── The presets ─────────────────────────────────────────────────────────────

    private struct Preset {
        let name: String
        /// What it is here to demonstrate. Shown under the button, so the tab teaches the vocabulary.
        let exercises: String
        let light: [String: Any]
        let dark: [String: Any]
    }

    // Each variant is COMPLETE, because nothing merges them.
    //
    // The SDK takes one appearance and resolves no theme, so the document handed over in dark is
    // the whole document — not a patch on the light one. A partial dark map used to work by
    // accident, back when the SDK layered one over the other; under this contract it silently
    // drops every token it omits, and a preset that sets only colours would lose its geometry the
    // moment the theme flipped.
    //
    // Presets that set NO colours carry the same map twice on purpose: geometry does not change
    // with the theme, and duplicating it is how that stays true when someone edits one of them.
    private let presets: [Preset] = [
        Preset(
            name: "SDK defaults",
            exercises: "every token unset — the mode's own defaults",
            light: [:],
            dark: [:]
        ),
        Preset(
            name: "Boxed",
            exercises: "colorBackground, borderWidth, borderRadius, paddingValue*",
            light: [
                "surfaceColor": "#FFFFFF",
                "colorBackground": "#F1F5F9",
                "colorBorder": "#CBD5E1",
                "borderWidth": 1,
                "borderRadius": 16,
                "paddingHorizontal": 14,
                "paddingVertical": 12,
                "paddingValueHorizontal": 12,
                "paddingValueVertical": 10,
                "colorText": "#0F172A",
                "colorLabel": "#64748B",
            ],
            dark: [
                "surfaceColor": "#0B1120",
                "colorBackground": "#1E293B",
                "colorBorder": "#334155",
                "borderWidth": 1,
                "borderRadius": 16,
                "paddingHorizontal": 14,
                "paddingVertical": 12,
                "paddingValueHorizontal": 12,
                "paddingValueVertical": 10,
                "colorText": "#F8FAFC",
                "colorLabel": "#94A3B8",
            ]
        ),
        Preset(
            name: "Right-aligned",
            exercises: "textAlignBase, textAlignLabel — the two the collect field ignored",
            light: [
                "textAlignBase": "right",
                "textAlignLabel": "right",
                "colorBackground": "#F8FAFC",
                "paddingValueHorizontal": 12,
                "borderRadius": 12,
            ],
            dark: [
                "textAlignBase": "right",
                "textAlignLabel": "right",
                "colorBackground": "#111827",
                "paddingValueHorizontal": 12,
                "borderRadius": 12,
            ]
        ),
        Preset(
            name: "Large type",
            exercises: "fontSizeBase, lineHeightBase, controlMinHeight, iconSize",
            light: [
                "fontSizeBase": 24,
                "lineHeightBase": 34,
                "fontSizeLabel": 15,
                "lineHeightLabel": 20,
                "controlMinHeight": 56,
                "iconSize": 24,
                "spacingLabel": 8,
                "spacingUnit": 20,
            ],
            dark: [
                "fontSizeBase": 24,
                "lineHeightBase": 34,
                "fontSizeLabel": 15,
                "lineHeightLabel": 20,
                "controlMinHeight": 56,
                "iconSize": 24,
                "spacingLabel": 8,
                "spacingUnit": 20,
            ]
        ),
        Preset(
            name: "Compact",
            exercises: "the same tokens the other way — a dense list",
            light: [
                "fontSizeBase": 15,
                "lineHeightBase": 20,
                "fontSizeLabel": 11,
                "lineHeightLabel": 14,
                "controlMinHeight": 36,
                "iconSize": 12,
                "spacingLabel": 2,
                "spacingUnit": 6,
                "paddingHorizontal": 8,
                "paddingVertical": 6,
            ],
            dark: [
                "fontSizeBase": 15,
                "lineHeightBase": 20,
                "fontSizeLabel": 11,
                "lineHeightLabel": 14,
                "controlMinHeight": 36,
                "iconSize": 12,
                "spacingLabel": 2,
                "spacingUnit": 6,
                "paddingHorizontal": 8,
                "paddingVertical": 6,
            ]
        ),
        Preset(
            name: "High contrast",
            exercises: "colorFocus and colorError, which drive the caret and the error text",
            light: [
                "surfaceColor": "#000000",
                "colorBackground": "#000000",
                "colorText": "#FFFFFF",
                "colorLabel": "#FFD400",
                "colorPlaceholder": "#7A7A7A",
                "colorFocus": "#FFD400",
                "colorError": "#FF453A",
                "colorBorder": "#FFD400",
                "borderWidth": 2,
                "borderRadius": 4,
            ],
            dark: [
                "surfaceColor": "#000000",
                "colorBackground": "#000000",
                "colorText": "#FFFFFF",
                "colorLabel": "#FFD400",
                "colorPlaceholder": "#7A7A7A",
                "colorFocus": "#FFD400",
                "colorError": "#FF453A",
                "colorBorder": "#FFD400",
                "borderWidth": 2,
                "borderRadius": 4,
            ]
        ),
    ]

    // ── Lifecycle ───────────────────────────────────────────────────────────────

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Appearance"
        view.backgroundColor = .systemBackground
        buildLayout()
        keyboardAvoider = KeyboardAvoider(scrollView: scroll, root: view)
        scroll.keyboardDismissMode = .interactive
    }

    // ── Actions ─────────────────────────────────────────────────────────────────

    @objc private func applyPreset(_ sender: UIButton) {
        let preset = presets[sender.tag]
        activePreset = preset
        writeAndApply(preset)
        status.text = "applied '\(preset.name)' — both surfaces restyled"
    }

    /// Puts the variant for the CURRENT theme into the field, and hands that document to the SDK.
    private func writeAndApply(_ preset: Preset) {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let tokens = isDark ? preset.dark : preset.light
        appearanceField.text = Self.pretty(tokens)
        LiveConfig.shared.setAppearance(tokens)
    }

    @objc private func applyAppearance() {
        activePreset = nil
        report(LiveConfig.shared.applyAppearance(json: appearanceField.text))
    }

    @objc private func reset() {
        activePreset = nil
        LiveConfig.shared.resetAppearance()
        appearanceField.text = ""
        status.text = "reset to the SDK defaults"
    }

    private func report(_ outcome: ConfigOutcome) {
        switch outcome {
        case let .merged(summary): status.text = summary
        case let .rejected(reason): status.text = "rejected: \(reason)"
        }
    }

    private static func pretty(_ tokens: [String: Any]) -> String {
        guard !tokens.isEmpty,
              let data = try? JSONSerialization.data(
                  withJSONObject: tokens,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    // ── Layout ──────────────────────────────────────────────────────────────────

    private func buildLayout() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
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

        stack.addArrangedSubview(heading("Presets"))
        stack.addArrangedSubview(caption(
            "Applied to BOTH surfaces at once. Watch that a restyle never clears the collect form "
                + "or unmasks a reveal row — that is the invariant, not a detail."
        ))

        for (index, preset) in presets.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(preset.name, for: .normal)
            button.tag = index
            button.contentHorizontalAlignment = .leading
            button.addTarget(self, action: #selector(applyPreset(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            stack.addArrangedSubview(caption(preset.exercises))
        }

        stack.addArrangedSubview(heading("Appearance (JSON)"))
        stack.addArrangedSubview(caption(
            "ONE document, which is what the SDK takes — it resolves no theme. Choosing a preset or "
            + "a mode rewrites this field with the palette for what is showing; type here and it is "
            + "yours until you pick another preset."
        ))
        configure(appearanceField)
        stack.addArrangedSubview(appearanceField)
        stack.addArrangedSubview(button("Apply", #selector(applyAppearance)))
        stack.addArrangedSubview(button("Reset", #selector(reset)))

        status.numberOfLines = 0
        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabel
        status.text = "—"
        stack.addArrangedSubview(status)
    }

    private func configure(_ field: UITextView) {
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        borders.track(field)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        // iOS rewrites `-` into an en dash inside pasted text, and a hex colour survives that only by
        // luck. Keep these three off on every field here.
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.heightAnchor.constraint(equalToConstant: 132).isActive = true
    }

    private func heading(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    private func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
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
