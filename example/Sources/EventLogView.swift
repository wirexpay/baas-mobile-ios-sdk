import UIKit

/// A scrolling, append-only log with timestamps. The Availability and Checkout tabs share it so a
/// run on this platform can be compared line by line with the same run on the other three.
final class EventLogView: UITextView {
    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func append(_ line: String) {
        text = (text ?? "") + "\(Self.clock.string(from: Date())) \(line)\n"
        scrollRangeToVisible(NSRange(location: (text as NSString).length, length: 0))
    }
}
