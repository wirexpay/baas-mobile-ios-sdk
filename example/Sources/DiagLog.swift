import Foundation
import UIKit
import WirexMobileSDK

/// The example's diagnostic log: everything the app and the SDK reported this run, in one place, so a
/// tester can share it with a bug report instead of describing what happened.
///
/// One in-memory ring buffer for the process. Taps, deep links, Config changes, keyboard, SDK events
/// and errors all land here, each line `HH:mm:ss.SSS [tag] message`. The Config tab shows it live and
/// offers Share / Copy / Clear.
///
/// SECURITY: nothing sensitive is ever passed in — callers log key NAMES and value LENGTHS, never a
/// bearer, a token, a card value or an address. `redact` is a second line: a JWT, a card-length digit
/// run or a 0x address that reaches `append` by mistake is masked before it is stored.
final class DiagLog {
    static let shared = DiagLog()

    enum Tag: String {
        case app, link, config, tap, kbd, sdk, err
    }

    private let lock = NSLock()
    private var lines: [String] = []
    private var observers: [ObjectIdentifier: () -> Void] = [:]
    private static let capacity = 2000

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private init() {}

    // MARK: - Writing

    func append(_ tag: Tag, _ message: String) {
        let line = "\(Self.clock.string(from: Date())) [\(tag.rawValue)] \(Self.redact(message))"
        lock.wirexWithLock {
            lines.append(line)
            if lines.count > Self.capacity { lines.removeFirst(lines.count - Self.capacity) }
        }
        // Mirrored to stdout so a run on the Simulator can be followed from the outside.
        print("[diag] \(line)")
        notify()
    }

    func clear() {
        lock.wirexWithLock { lines.removeAll() }
        append(.app, "log cleared")
    }

    // MARK: - Reading

    var text: String { lock.wirexWithLock { lines.joined(separator: "\n") } }
    var count: Int { lock.wirexWithLock { lines.count } }

    /// Header plus every line — what Share and Copy hand over.
    var exportText: String {
        let body = text
        return "\(header)\nlines: \(count)\n\n\(body)\n"
    }

    /// Build, OS, device and SDK, so a shared log says what it came from.
    var header: String {
        let bundle = Bundle.main
        let id = bundle.bundleIdentifier ?? "?"
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let screen = scene?.screen
        let size = screen.map { "\(Int($0.bounds.width))x\(Int($0.bounds.height))@\(Int($0.scale))x" } ?? "?"
        let stamp = ISO8601DateFormatter().string(from: Date())
        return """
        app: \(id) \(version) (\(build))
        os: iOS \(device.systemVersion)
        device: \(Self.machine) (\(device.model))
        sdk: WirexMobileSDK \(WirexSdkInfo.version)
        screen: \(size)
        locale: \(Locale.current.identifier)
        exported: \(stamp)
        """
    }

    /// Observers run on the main thread, after every append.
    func observe(_ owner: AnyObject, _ body: @escaping () -> Void) {
        lock.wirexWithLock { observers[ObjectIdentifier(owner)] = body }
    }

    func unobserve(_ owner: AnyObject) {
        lock.wirexWithLock { observers.removeValue(forKey: ObjectIdentifier(owner)) }
    }

    private func notify() {
        let current = lock.wirexWithLock { Array(observers.values) }
        guard !current.isEmpty else { return }
        DispatchQueue.main.async { current.forEach { $0() } }
    }

    // MARK: - Process-wide hooks

    /// Registered once at launch: the launch header, foreground / background and the keyboard.
    func installHooks() {
        header.split(separator: "\n").forEach { append(.app, "launch " + $0) }
        let center = NotificationCenter.default
        // Block observers live only as long as their tokens, so they are kept.
        hooks = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.append(.app, "didBecomeActive")
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.append(.app, "willResignActive")
            },
            center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] note in
                let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                self?.append(.kbd, "shown height=\(Int(frame?.height ?? 0))pt")
            },
            center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
                self?.append(.kbd, "hidden")
            },
        ]
    }

    private var hooks: [NSObjectProtocol] = []

    // MARK: - Redaction

    private static let jwt = try! NSRegularExpression(pattern: "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]+\\.?[A-Za-z0-9_-]*")
    private static let digits = try! NSRegularExpression(pattern: "(?<![0-9])[0-9]{13,19}(?![0-9])")
    private static let address = try! NSRegularExpression(pattern: "0x([0-9a-fA-F]{4})[0-9a-fA-F]{32}([0-9a-fA-F]{4})")

    // SECURITY: the last guard before a line is stored and shared. A token, a PAN-length number or a
    // wallet address is masked whatever path it arrived by; nothing above relies on callers alone.
    static func redact(_ message: String) -> String {
        var s = message
        s = jwt.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "<jwt>")
        s = digits.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "<digits>")
        s = address.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "0x$1…$2")
        return s
    }

    /// A URL with its query dropped: a 3DS orchestrator URL carries the session token there.
    static func describe(url: String) -> String {
        guard let parsed = URL(string: url), let host = parsed.host else { return "(\(url.count) chars, not a URL)" }
        return "\(parsed.scheme ?? "?")://\(host)\(parsed.path) (\(url.count) chars)"
    }

    private static var machine: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

/// Short forms, so a call site reads `diag.tap("Tokenize")`.
enum diag {
    static func app(_ m: String) { DiagLog.shared.append(.app, m) }
    static func link(_ m: String) { DiagLog.shared.append(.link, m) }
    static func config(_ m: String) { DiagLog.shared.append(.config, m) }
    static func tap(_ m: String) { DiagLog.shared.append(.tap, m + " tapped") }
    static func sdk(_ m: String) { DiagLog.shared.append(.sdk, m) }
    static func err(_ m: String) { DiagLog.shared.append(.err, m) }
}
