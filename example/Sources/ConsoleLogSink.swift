import Foundation
import WirexMobileSDK

/// Prints SDK diagnostics to the console so a run can be followed from the outside.
///
/// A sink is host code. The SDK hands it an event name and named fields, already scrubbed — there is
/// no free-text message API, so there is no convenient place for a card value to appear: only
/// non-sensitive diagnostics travel (field names, presence flags, HTTP status, durations, correlation
/// ids, error codes). A real app would forward this to its own logger.
///
/// Conforms to BOTH the card logger's sink (`WirexLogSink`) and the wallet logger's
/// (`WirexWalletLogSink`) — they are separate protocols with their own level type — so one instance
/// can be handed to every surface.
///
/// `write` is called on whatever thread produced the event, so a sink has to be safe to call from
/// several at once. Synchronising that is the sink's job, not the SDK's.
final class ConsoleLogSink: WirexLogSink, WirexWalletLogSink {
    private let lock = NSLock()

    func write(level: WirexLogLevel, event: String, fields: [String: String]) {
        emit(level: "\(level)", event: event, fields: fields)
    }

    func write(level: WirexWalletLogLevel, event: String, fields: [String: String]) {
        emit(level: "\(level)", event: event, fields: fields)
    }

    /// The console and the diagnostic log the Config tab shares — the same scrubbed line in both.
    private func emit(level: String, event: String, fields: [String: String]) {
        let rendered = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        // `print` writes the line and its terminator as separate calls, so two events on two
        // threads interleave into one unreadable line without this.
        lock.wirexWithLock { print("[wirex] \(event) \(rendered)") }
        diag.sdk("\(level) \(event) \(rendered)".trimmingCharacters(in: .whitespaces))
    }
}

