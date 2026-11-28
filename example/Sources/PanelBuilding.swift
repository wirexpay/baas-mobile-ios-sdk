import UIKit

/// The Trade and Crypto tabs' building blocks, drawn as the Config tab draws its own.
protocol PanelBuilding {}

extension PanelBuilding {
    func style(_ label: UILabel) {
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = Theme.textDim
        label.numberOfLines = 0
    }

    func titleLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 24, weight: .heavy)
        label.textColor = Theme.text
        return label
    }

    func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = Theme.textDim
        label.numberOfLines = 0
        return label
    }

    func hint(_ text: String) -> UILabel {
        let label = caption(text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = Theme.textFaint
        return label
    }

    func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = .systemFont(ofSize: 12, weight: .heavy)
        label.textColor = Theme.textFaint
        return label
    }

    func labeled(_ name: String, _ control: UIView) -> UIView {
        let label = UILabel()
        label.text = name
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = Theme.text
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        return row
    }

    func card(_ views: [UIView]) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.backgroundColor = Theme.surface
        stack.layer.cornerRadius = 20
        stack.layer.borderWidth = 1
        stack.layer.borderColor = Theme.border.cgColor
        return stack
    }

    func buttonRow(_ buttons: UIButton...) -> UIView {
        let row = UIStackView(arrangedSubviews: buttons + [UIView()])
        row.axis = .horizontal
        row.spacing = 8
        return row
    }

    /// A pill button in the accent colour, the look of every action on these tabs.
    func pill(_ title: String) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.setTitleColor(Theme.onAccent, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        button.backgroundColor = Theme.accent
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
        button.layer.cornerRadius = 14
        button.accessibilityIdentifier = title
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    /// A hash cut to its ends, for a table row.
    func short(_ hash: String) -> String {
        hash.count > 14 ? "\(hash.prefix(8))…\(hash.suffix(6))" : hash
    }
}

extension PanelBuilding {
    /// Who signs, where, and where the bearer comes from. The key shows only as its address.
    func signerSummary() -> String {
        let config = LiveConfig.shared
        let key = config.credential("ownerKey")
        let signs: String
        if key.isEmpty {
            signs = "no ownerKey: set it on the Config tab or in the launch environment"
        } else if let signer = try? TestOnlySigner(hexKey: key) {
            signs = "signs as \(signer.address)"
        } else {
            signs = "ownerKey is not a 32-byte hex private key"
        }
        let chain = config.credential("chainId").isEmpty ? "—" : config.credential("chainId")
        let company = config.credential("companyId").isEmpty ? "—" : config.credential("companyId")
        let bearer = config.credential("bearer").isEmpty ? "from the login with ownerKey" : "pasted, wins over the login"
        return "environment \(config.environment) · chain \(chain)\ncompany \(company)\n\(signs)\nbearer \(bearer)"
    }

    /// The environment, chain and key a quote belongs to. A quote made under another is not sent.
    func configScope() -> String {
        let config = LiveConfig.shared
        let address = (try? TestOnlySigner(hexKey: config.credential("ownerKey")))?.address ?? ""
        return [config.environment, config.credential("chainId"), address].joined(separator: "|")
    }
}
